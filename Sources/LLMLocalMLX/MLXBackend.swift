import Foundation
import LLMLocalClient
import LLMTool
import MLX
import MLXLLM
@preconcurrency import MLXLMCommon

/// MLXベースのローカルLLM推論バックエンド
///
/// このアクターは mlx-swift-lm API をラップし、``LLMLocalBackend`` への準拠を提供します。
/// モデルの読み込み、テキスト生成、GPUキャッシュ設定、
/// およびオプションのLoRAアダプターマージを管理します。
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
    public init(
        gpuCacheLimit: Int = 20 * 1024 * 1024,
        adapterResolver: (any AdapterResolving)? = nil
    ) {
        self.gpuCacheLimit = gpuCacheLimit
        self.adapterResolver = adapterResolver
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
        if loadedSpec == spec { return }

        // If another load is in progress, throw
        guard !isLoading else { throw LLMLocalError.loadInProgress }

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

        let hfID: String
        switch spec.base {
        case .huggingFace(let id):
            hfID = id
        case .local(let path):
            hfID = path.path()
        }

        do {
            // Load base model (with or without progress tracking)
            let modelContainer: ModelContainer
            if let progressHandler {
                let config = ModelConfiguration(id: hfID)
                modelContainer = try await LLMModelFactory.shared.loadContainer(
                    configuration: config,
                    progressHandler: { progress in
                        progressHandler(DownloadProgress(
                            fraction: progress.fractionCompleted,
                            completedBytes: progress.completedUnitCount,
                            totalBytes: progress.totalUnitCount,
                            currentFile: nil
                        ))
                    }
                )
            } else {
                modelContainer = try await MLXLMCommon.loadModelContainer(id: hfID)
            }

            // Apply adapter if resolved
            if let adapterURL {
                let adapterConfig = ModelConfiguration(directory: adapterURL)
                let adapter = try await ModelAdapterFactory.shared.load(
                    configuration: adapterConfig
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
        AsyncThrowingStream { continuation in
            Task { [weak self] in
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
        AsyncThrowingStream { continuation in
            Task { [weak self] in
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
    }

    public nonisolated func generateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
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

        do {
            for try await generation in session.streamDetails(
                to: prompt, images: [], videos: []
            ) {
                try Task.checkCancellation()
                switch generation {
                case .chunk(let text):
                    continuation.yield(.text(text))
                case .toolCall(let toolCall):
                    continuation.yield(.toolCall(LLMTool.ToolCall(from: toolCall)))
                case .info:
                    break
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

        do {
            try await container.perform { context in
                let tokens = try context.tokenizer.applyChatTemplate(
                    messages: mlxMessages,
                    tools: toolSpecs
                )
                let input = LMInput(tokens: MLXArray(tokens))

                let stream = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: context
                )

                for await generation in stream {
                    guard !Task.isCancelled else { break }
                    switch generation {
                    case .chunk(let text):
                        continuation.yield(.text(text))
                    case .toolCall(let toolCall):
                        continuation.yield(.toolCall(LLMTool.ToolCall(from: toolCall)))
                    case .info:
                        break
                    }
                }
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: LLMLocalError.cancelled)
        } catch {
            continuation.finish(throwing: error)
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
            case .toolResult(let callId, _, let content, _):
                toolResults.append((callId: callId, content: content))
            case .image, .audio, .video:
                break
            case .thinking:
                break // Local LLM では thinking は無視
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
