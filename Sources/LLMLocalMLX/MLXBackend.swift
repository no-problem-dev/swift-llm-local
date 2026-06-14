import Foundation
import HuggingFace
import LLMClient
import LLMLocalClient
import LLMTool
import MLX
import MLXHuggingFace
import MLXLLM
@preconcurrency import MLXLMCommon
import Tokenizers

/// MLXベースのローカルLLM推論バックエンド
///
/// このアクターは mlx-swift-lm API をラップし、``LLMLocalBackend`` への準拠を提供します。
/// モデルの読み込み、テキスト生成、GPUキャッシュ設定、
/// およびオプションのLoRAアダプターマージを管理します。
///
/// ## モデルの取得
///
/// mlx-swift-lm 3.x はモデル取得を `Downloader` / `TokenizerLoader` として
/// 消費側が注入する設計です。デフォルトでは Hugging Face Hub からダウンロードしますが、
/// 独自のダウンロード戦略（S3、アプリ内バンドル等）を注入できます。
///
/// ## アダプターサポート
///
/// ``ModelSpec`` が ``AdapterSource`` を含む場合、バックエンドは
/// ``AdapterResolving`` インスタンスを介してアダプターをローカルURLに解決し、
/// アダプターパスをMLXモデル読み込みパイプラインに渡します。
///
/// ```swift
/// let backend = MLXBackend(adapterResolver: adapterManager)
/// try await backend.loadModel(specWithAdapter)
/// ```
public actor MLXBackend: LLMLocalBackend {

    // MARK: - Internal State

    private var chatSession: ChatSession?
    private var modelContainer: ModelContainer?
    private var loadedSpec: ModelSpec?
    private let gpuCacheLimit: Int
    private let downloader: any Downloader
    private let tokenizerLoader: any TokenizerLoader

    /// `generateFromMessages` 経路のプロンプト（KV）キャッシュ。
    ///
    /// ターン間でプロンプトの共通接頭辞を再利用し、毎回フルプロンプトを
    /// 再 prefill するコストを避けるための保持領域。`ChatSession` の KV 再利用
    /// と同等の仕組みを、ステートレス API（毎回フルメッセージ配列を受け取る）に
    /// 適用するために、トークン列を比較して接頭辞一致分のキャッシュを再利用する。
    ///
    /// 単一会話・直列生成のときだけ共有される。`delegate_async` 等で同一バックエンドを
    /// 複数の会話（host + ワーカー）が並行共有する場合、進行中の生成があれば後続の生成は
    /// 共有キャッシュに触れず専用の使い捨てキャッシュで回す（``cacheBusy`` で判定）。
    private let promptCacheStore = PromptCacheStore()

    /// 共有プロンプトキャッシュが現在いずれかの生成に占有されているか。
    /// 占有中に始まった別の生成は、KV 文脈の会話間漏れを避けるため共有キャッシュを使わない。
    private var cacheBusy = false

    /// LoRA/QLoRA アダプターのオプションリゾルバー。
    private let adapterResolver: (any AdapterResolving)?

    /// loadModel 中にキャプチャされた直近の解決済みアダプターURL。
    /// アダプター解決が期待されるURLを生成し、モデル読み込みパイプラインに
    /// 渡されることを検証するためにテスト用に公開されています。
    private(set) var lastResolvedAdapterURL: URL?

    /// 新規および既存のチャットセッションに適用されるシステムプロンプト。
    private var _systemPrompt: String?

    /// モデルの読み込みが現在進行中かを追跡します（排他制御用）。
    private var isLoading: Bool = false

    // MARK: - Test Accessors

    /// テスト目的でGPUキャッシュ制限を公開します。
    var gpuCacheLimitValue: Int { gpuCacheLimit }

    /// テスト目的でロード状態を公開します。
    var isLoadingValue: Bool { isLoading }

    /// アダプターリゾルバーが設定されているかどうか。
    var hasAdapterResolver: Bool { adapterResolver != nil }

    // MARK: - Initialization

    /// 指定されたGPUキャッシュ制限とオプションのアダプターリゾルバーで新しい MLXBackend を作成します。
    ///
    /// - Parameters:
    ///   - gpuCacheLimit: GPUキャッシュの最大サイズ（バイト単位）。
    ///     デフォルトは 20 MB（20 * 1024 * 1024）。
    ///   - adapterResolver: LoRA/QLoRA アダプターソースをローカルファイルURLに解決する
    ///     オプションの ``AdapterResolving`` インスタンス。`nil` の場合、アダプター付き
    ///     モデルの読み込みは ``LLMLocalError/adapterMergeFailed(reason:)`` をスローします。
    ///   - downloader: モデルリポジトリのスナップショットを取得するダウンローダー。
    ///     デフォルトは Hugging Face Hub。
    ///   - tokenizerLoader: ローカルディレクトリからトークナイザーを読み込むローダー。
    ///     デフォルトは swift-transformers の `AutoTokenizer`。
    public init(
        gpuCacheLimit: Int = 20 * 1024 * 1024,
        adapterResolver: (any AdapterResolving)? = nil,
        downloader: (any Downloader)? = nil,
        tokenizerLoader: (any TokenizerLoader)? = nil
    ) {
        self.gpuCacheLimit = gpuCacheLimit
        self.adapterResolver = adapterResolver
        // swift-huggingface のキャッシュ経路（#hubDownloader）は iOS で LFS 大ファイルの
        // パス解決に失敗するため、明示 destination 方式の DestinationHubDownloader を既定にする。
        self.downloader = downloader ?? DestinationHubDownloader()
        self.tokenizerLoader = tokenizerLoader ?? #huggingFaceTokenizerLoader()
    }

    // MARK: - LLMLocalBackend

    public func loadModel(_ spec: ModelSpec) async throws {
        try await performLoad(spec, progressHandler: nil)
    }

    public func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        try await performLoad(spec, progressHandler: progressHandler)
    }

    /// オプションの進捗報告付きモデル読み込みの共通実装。
    private func performLoad(
        _ spec: ModelSpec,
        progressHandler: (@Sendable (DownloadProgress) -> Void)?
    ) async throws {
        // If same model already loaded, skip
        if loadedSpec == spec {
            return
        }

        // If another load is in progress, throw
        guard !isLoading else {
            throw LLMLocalError.loadInProgress
        }

        isLoading = true
        defer { isLoading = false }

        await unloadModel()

        // Reset resolved adapter URL
        lastResolvedAdapterURL = nil

        // Resolve adapter before MLX initialization so that adapter
        // errors are reported early, without requiring GPU access.
        let adapterURL = try await resolveAdapter(for: spec)
        lastResolvedAdapterURL = adapterURL

        MLX.Memory.cacheLimit = gpuCacheLimit

        do {
            let modelContainer: ModelContainer
            switch spec.base {
            case .huggingFace(let id):
                modelContainer = try await LLMModelFactory.shared.loadContainer(
                    from: downloader,
                    using: tokenizerLoader,
                    configuration: ModelConfiguration(id: id),
                    progressHandler: { progress in
                        progressHandler?(DownloadProgress(
                            fraction: progress.fractionCompleted,
                            completedBytes: progress.completedUnitCount,
                            totalBytes: progress.totalUnitCount,
                            currentFile: nil
                        ))
                    }
                )
            case .local(let path):
                modelContainer = try await LLMModelFactory.shared.loadContainer(
                    from: path,
                    using: tokenizerLoader
                )
            }

            // Apply adapter if resolved
            if let adapterURL {
                let adapter = try await ModelAdapterFactory.shared.load(
                    from: downloader,
                    configuration: ModelConfiguration(directory: adapterURL)
                )
                try await modelContainer.perform { context in
                    try context.model.load(adapter: adapter)
                }
            }

            self.modelContainer = modelContainer
            chatSession = ChatSession(modelContainer, instructions: _systemPrompt)
            loadedSpec = spec
        } catch let error as LLMLocalError {
            throw error
        } catch {
            throw LLMLocalError.loadFailed(
                modelId: spec.id,
                reason: error.localizedDescription
            )
        }
    }

    public nonisolated func generate(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, Error> {
        makeCancellableStream { [weak self] continuation in
            Task {
                guard let self else {
                    continuation.finish(throwing: LLMLocalError.modelNotLoaded)
                    return
                }
                await self.performGenerate(
                    prompt: prompt,
                    config: config,
                    continuation: continuation
                )
            }
        }
    }

    public nonisolated func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        makeCancellableStream { [weak self] continuation in
            Task {
                guard let self else {
                    continuation.finish(throwing: LLMLocalError.modelNotLoaded)
                    return
                }
                await self.performGenerateWithTools(
                    prompt: prompt,
                    config: config,
                    tools: tools,
                    continuation: continuation
                )
            }
        }
    }

    public func unloadModel() async {
        chatSession = nil
        modelContainer = nil
        loadedSpec = nil
        promptCacheStore.reset()
    }

    public var isLoaded: Bool { chatSession != nil }

    public var currentModel: ModelSpec? { loadedSpec }

    public var systemPrompt: String? { _systemPrompt }

    public func setSystemPrompt(_ prompt: String?) {
        _systemPrompt = prompt
        chatSession?.instructions = prompt
    }

    public func resetSession() {
        guard let container = modelContainer else { return }
        chatSession = ChatSession(container, instructions: _systemPrompt)
        // generateFromMessages 経路の KV キャッシュも会話リセットで破棄する。
        promptCacheStore.reset()
    }

    public nonisolated func generateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        makeCancellableStream { [weak self] continuation in
            Task {
                guard let self else {
                    continuation.finish(throwing: LLMLocalError.modelNotLoaded)
                    return
                }
                await self.performGenerateFromMessages(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    config: config,
                    tools: tools,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Internal Helpers

    /// アダプターが指定されている場合、アダプターソースをローカルURLに解決します。
    ///
    /// spec にアダプターがない場合は `nil` を返します。spec にアダプターがあるが
    /// リゾルバーが設定されていない場合、または解決に失敗した場合はスローします。
    ///
    /// テスト容易性のために別メソッドとして抽出されています。
    /// GPU/Metal アクセスなしで呼び出すことができます。
    func resolveAdapter(for spec: ModelSpec) async throws -> URL? {
        guard let adapterSource = spec.adapter else { return nil }

        guard let resolver = adapterResolver else {
            throw LLMLocalError.adapterMergeFailed(
                reason: "No adapter resolver configured"
            )
        }

        do {
            return try await resolver.resolve(adapterSource)
        } catch let error as LLMLocalError {
            throw error
        } catch {
            throw LLMLocalError.adapterMergeFailed(
                reason: error.localizedDescription
            )
        }
    }

    // MARK: - Private Helpers

    /// アクターの分離コンテキスト内で実際の生成処理を実行します。
    /// Sendable でない `ChatSession` が分離境界を越えて送信されることを回避します。
    private func performGenerate(
        prompt: String,
        config: GenerationConfig,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        guard let session = chatSession else {
            continuation.finish(throwing: LLMLocalError.modelNotLoaded)
            return
        }

        session.generateParameters = config.mlxParameters
        session.additionalContext = config.chatTemplateContext

        do {
            for try await text in session.streamResponse(to: prompt) {
                try Task.checkCancellation()
                continuation.yield(text)
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: LLMLocalError.cancelled)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// アクターの分離コンテキスト内でツール呼び出し付き生成処理を実行します。
    private func performGenerateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition],
        continuation: AsyncThrowingStream<GenerationOutput, Error>.Continuation
    ) async {
        guard let session = chatSession else {
            continuation.finish(throwing: LLMLocalError.modelNotLoaded)
            return
        }

        session.tools = tools.map { $0.toolSpec }
        session.generateParameters = config.mlxParameters
        session.additionalContext = config.chatTemplateContext

        do {
            for try await generation in session.streamDetails(
                to: prompt, images: [], videos: []
            ) {
                try Task.checkCancellation()
                if let output = GenerationOutput(generation) {
                    continuation.yield(output)
                }
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: LLMLocalError.cancelled)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// 構造化メッセージ配列からレスポンスを生成します。
    ///
    /// `ChatSession` を経由せず、トークナイザーの `applyChatTemplate` を直接使用して
    /// チャットテンプレートを1回だけ適用します。
    private func performGenerateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition],
        continuation: AsyncThrowingStream<GenerationOutput, Error>.Continuation
    ) async {
        guard let container = modelContainer else {
            continuation.finish(throwing: LLMLocalError.modelNotLoaded)
            return
        }

        // Build MLX message array (let-binding for Sendable capture)
        let mlxMessages: [[String: any Sendable]] = {
            var msgs: [[String: any Sendable]] = []
            if let systemPrompt, !systemPrompt.isEmpty {
                msgs.append(["role": "system", "content": systemPrompt])
            }
            for msg in messages {
                msgs.append(contentsOf: Self.convertToMLXFormat(msg))
            }
            return msgs
        }()

        let toolSpecs: [[String: any Sendable]]? = tools.isEmpty
            ? nil : tools.map { $0.toolSpec }
        let parameters = config.mlxParameters

        // 別の生成が進行中なら共有キャッシュを使わない（並行する別会話との KV 文脈漏れを防ぐ）。
        // 単一会話の直列生成のときだけ共有キャッシュで prefill を再利用する。
        let useSharedCache = !cacheBusy
        if useSharedCache { cacheBusy = true }
        defer { if useSharedCache { cacheBusy = false } }

        do {
            let additionalContext = config.chatTemplateContext
            let cacheStore = promptCacheStore
            try await container.perform { context in
                let tokens = try context.tokenizer.applyChatTemplate(
                    messages: mlxMessages,
                    tools: toolSpecs,
                    additionalContext: additionalContext
                )
                guard !tokens.isEmpty else { return }

                let cache: [KVCache]
                let suffixStart: Int
                if useSharedCache {
                    // 直前のターンとの共通接頭辞を再利用し、差分（接尾辞）だけを prefill する。
                    (cache, suffixStart) = cacheStore.prepare(for: tokens) {
                        context.model.newCache(parameters: parameters)
                    }
                } else {
                    // 並行生成: 共有キャッシュを汚さないよう専用キャッシュで全量 prefill する。
                    cache = context.model.newCache(parameters: parameters)
                    suffixStart = 0
                }
                let suffix = Array(tokens[suffixStart...])
                let input = LMInput(tokens: MLXArray(suffix))

                let stream = try MLXLMCommon.generate(
                    input: input,
                    cache: cache,
                    parameters: parameters,
                    context: context
                )

                for await generation in stream {
                    guard !Task.isCancelled else { break }
                    if let output = Self.mapGeneration(
                        generation, fullPromptTokenCount: tokens.count
                    ) {
                        continuation.yield(output)
                    }
                }

                // 共有キャッシュを使った場合のみ、次ターンの接頭辞再利用のため状態を記録する。
                if useSharedCache {
                    cacheStore.commit(tokens: tokens, cache: cache)
                }
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: LLMLocalError.cancelled)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// MLX の生成イベントを ``GenerationOutput`` に変換します。
    ///
    /// プロンプトキャッシュ再利用時は MLX に投入されるトークンが接尾辞のみになるため、
    /// `.info` の `promptTokenCount` を「テンプレート適用後の完全なプロンプト長」で
    /// 上書きし、usage 報告の意味（入力トークン総数）を保ちます。
    private static func mapGeneration(
        _ generation: Generation,
        fullPromptTokenCount: Int
    ) -> GenerationOutput? {
        switch generation {
        case .chunk(let text):
            return .text(text)
        case .toolCall(let toolCall):
            return .toolCall(LLMTool.ToolCall(from: toolCall))
        case .info(let info):
            return .info(GenerationInfo(
                promptTokenCount: fullPromptTokenCount,
                generationTokenCount: info.generationTokenCount,
                tokensPerSecond: info.generateTime > 0
                    ? Double(info.generationTokenCount) / info.generateTime : 0
            ))
        @unknown default:
            return nil
        }
    }

    // MARK: - LLMMessage → MLX Format Conversion

    /// `LLMMessage` を MLX 互換のメッセージディクショナリに変換します。
    ///
    /// 1つの `LLMMessage` が複数の MLX メッセージに変換される場合があります
    /// （例: ツール結果は個別の "tool" ロールメッセージになります）。
    private static func convertToMLXFormat(_ message: LLMMessage) -> [[String: any Sendable]] {
        var result: [[String: any Sendable]] = []

        var textContent = ""
        var toolUses: [[String: any Sendable]] = []
        var toolResults: [(callId: String, content: String)] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                textContent += text
            case .toolUse(let id, let name, let input):
                let argsString = String(data: input, encoding: .utf8) ?? "{}"
                toolUses.append([
                    "id": id,
                    "type": "function",
                    "function": [
                        "name": name,
                        "arguments": argsString,
                    ] as [String: any Sendable],
                ])
            case .toolResult(let callId, _, let content):
                toolResults.append((callId: callId, content: content.contentValue))
            case .image, .audio, .video, .document:
                break
            case .thinking:
                // 過去ターンの思考（reasoning）は履歴に含めない。
                // Qwen3 系をはじめ thinking 対応モデルの公式ガイダンスは
                // 「マルチターンの履歴にはモデルの最終出力のみを残し、思考内容は
                // 含めない」こと。再注入するとコンテキストを浪費し、チャット
                // テンプレートの思考区間処理と二重化して出力品質を下げるため破棄する。
                break
            }
        }

        if message.role == .assistant {
            if !toolUses.isEmpty {
                var msg: [String: any Sendable] = [
                    "role": "assistant",
                    "tool_calls": toolUses,
                ]
                if !textContent.isEmpty {
                    msg["content"] = textContent
                }
                result.append(msg)
            } else if !textContent.isEmpty {
                result.append(["role": "assistant", "content": textContent])
            }
        } else {
            // User role
            for tr in toolResults {
                result.append([
                    "role": "tool",
                    "content": tr.content,
                    "tool_call_id": tr.callId,
                ])
            }
            if !textContent.isEmpty {
                result.append(["role": "user", "content": textContent])
            }
        }

        return result
    }
}

// MARK: - Prompt (KV) Cache Reuse

/// `generateFromMessages` 経路でターン間の KV キャッシュを再利用する保持領域。
///
/// `applyChatTemplate` 後のトークン列を直前ターンと比較し、共通接頭辞分の
/// キャッシュを温存して差分だけを prefill させる（標準的なプロンプトキャッシュ手法）。
///
/// ## スレッド安全性
///
/// 本クラスへのアクセスは ``MLXBackend`` がすべて `ModelContainer.perform`
/// （actor で直列化）の内側から行うため、`@unchecked Sendable` とする。
/// `MLXLMCommon.KVCache` が `Sendable` でないため Swift の検査は通せないが、
/// 直列実行の不変条件で安全性を担保する。並行生成はサポートしない。
final class PromptCacheStore: @unchecked Sendable {
    /// 現在キャッシュが表現するトークン列（直近に投入した完全プロンプト）。
    private var tokens: [Int] = []
    /// 直近の生成で構築・更新された KV キャッシュ。
    private var cache: [KVCache]?

    /// キャッシュを破棄します（モデル切替・会話リセット・アンロード時）。
    func reset() {
        tokens = []
        cache = nil
    }

    /// 新しい完全プロンプト `newTokens` に対し、再利用すべきキャッシュと
    /// prefill を開始する接尾辞位置を返します。
    ///
    /// - 再利用不能（初回・接頭辞不一致・トリム不可）なら新規キャッシュ + 位置 0。
    /// - 再利用可能なら共通接頭辞 `p` までトリムしたキャッシュ + 位置 `p`。
    ///   モデルがロジットを出すため最低 1 トークンは必ず投入する。
    func prepare(
        for newTokens: [Int],
        makeCache: () -> [KVCache]
    ) -> (cache: [KVCache], suffixStart: Int) {
        guard let existing = cache, !tokens.isEmpty else {
            return (freshCache(makeCache), 0)
        }

        var prefix = Self.commonPrefixLength(tokens, newTokens)
        // 最低 1 トークンは prefill する必要がある。
        if prefix >= newTokens.count { prefix = newTokens.count - 1 }
        guard prefix > 0 else {
            return (freshCache(makeCache), 0)
        }

        // 既存キャッシュには「前回プロンプト + 前回生成分」が入っている。
        // 先頭 `prefix` トークンだけを残すよう末尾をトリムする。
        let offset = existing.first?.offset ?? 0
        let trimCount = offset - prefix
        if trimCount > 0 {
            guard canTrimPromptCache(existing),
                  trimPromptCache(existing, numTokens: trimCount) == trimCount
            else {
                return (freshCache(makeCache), 0)
            }
        }
        return (existing, prefix)
    }

    /// 生成完了後、次ターンの再利用に備えて状態を記録します。
    func commit(tokens: [Int], cache: [KVCache]) {
        self.tokens = tokens
        self.cache = cache
    }

    private func freshCache(_ makeCache: () -> [KVCache]) -> [KVCache] {
        let fresh = makeCache()
        cache = fresh
        tokens = []
        return fresh
    }

    /// 2 つのトークン列の共通接頭辞長を返します。
    static func commonPrefixLength(_ a: [Int], _ b: [Int]) -> Int {
        let limit = min(a.count, b.count)
        var i = 0
        while i < limit, a[i] == b[i] { i += 1 }
        return i
    }
}

// MARK: - MLX Generation → GenerationOutput

extension GenerationOutput {
    /// MLX の ``MLXLMCommon.Generation`` イベントを ``GenerationOutput`` に変換します。
    ///
    /// 対応するイベントがない場合（未知のケース）は `nil` を返します。
    init?(_ generation: Generation) {
        switch generation {
        case .chunk(let text):
            self = .text(text)
        case .toolCall(let toolCall):
            self = .toolCall(LLMTool.ToolCall(from: toolCall))
        case .info(let info):
            self = .info(GenerationInfo(
                promptTokenCount: info.promptTokenCount,
                generationTokenCount: info.generationTokenCount,
                tokensPerSecond: info.generateTime > 0
                    ? Double(info.generationTokenCount) / info.generateTime : 0
            ))
        @unknown default:
            return nil
        }
    }
}
