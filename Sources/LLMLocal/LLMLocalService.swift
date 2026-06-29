import LLMClient
import LLMLocalClient
import LLMLocalMLX
import LLMLocalModels

/// バックエンドとモデルレジストリを統合した高レベル LLM 操作ファサード
///
/// テキスト生成のための高レベル API を提供する。
/// 必要に応じてモデルの読み込みを自動的に処理し、生成統計を追跡する。
/// オプションで ``MemoryMonitor`` を渡すと、メモリ圧迫時の自動モデルアンロードを
/// 有効にできる。
///
/// ## 使用例
///
/// ```swift
/// let monitor = MemoryMonitor()
/// let service = LLMLocalService(
///     backend: mlxBackend,
///     modelRegistry: modelRegistry,
///     memoryMonitor: monitor
/// )
/// await service.startMemoryMonitoring()
///
/// let stream = await service.generate(
///     model: ModelPresets.qwen3_0_6B,
///     prompt: "What is Swift?"
/// )
/// for try await token in stream {
///     print(token, terminator: "")
/// }
/// ```
public actor LLMLocalService {

    private let backend: any LLMLocalBackend
    private let modelRegistry: ModelRegistry
    private let memoryMonitor: MemoryMonitor?
    private let modelSwitcher: ModelSwitcher?
    /// ディスク上のダウンロード済みモデルを問い合わせる在庫。
    /// インメモリのレジストリと異なり、アプリ再起動後も実体を正しく反映する。
    private let inventory: LocalModelInventory

    /// 最新の完了した生成の統計情報。まだ生成が完了していない場合は `nil`。
    private(set) public var lastGenerationStats: GenerationStats?

    /// 指定されたバックエンド、モデルレジストリ、およびオプションのメモリモニターと
    /// モデルスイッチャーで新しいサービスを作成する。
    ///
    /// - Parameters:
    ///   - backend: モデルの読み込みとテキスト生成に使用する推論バックエンド。
    ///   - modelRegistry: キャッシュ照会用のモデルレジストリ。
    ///   - memoryMonitor: メモリ圧迫時の自動モデルアンロード用のオプションメモリモニター。デフォルトは `nil`。
    ///   - modelSwitcher: LRUベースのマルチモデル管理用のオプションモデルスイッチャー。
    ///     指定された場合、バックエンドへの直接呼び出しの代わりにスイッチャーにモデル読み込みを委譲する。デフォルトは `nil`。
    public init(
        backend: any LLMLocalBackend,
        modelRegistry: ModelRegistry,
        memoryMonitor: MemoryMonitor? = nil,
        modelSwitcher: ModelSwitcher? = nil,
        inventory: LocalModelInventory = LocalModelInventory()
    ) {
        self.backend = backend
        self.modelRegistry = modelRegistry
        self.memoryMonitor = memoryMonitor
        self.modelSwitcher = modelSwitcher
        self.inventory = inventory
    }

    /// 指定されたモデルを使用してプロンプトからテキストを生成する。
    ///
    /// モデルがバックエンドに現在読み込まれていない場合、生成開始前に自動的に
    /// 読み込まれる。生成統計は追跡され、ストリーム完了後に
    /// ``lastGenerationStats`` で参照できる。
    ///
    /// > Important: このメソッドは**会話継続（ステートフル）API**。内部の
    /// > `ChatSession` を使い回すため、連続して呼び出すと過去のプロンプト・応答が
    /// > 履歴として蓄積される（チャット用途ではこれが望ましい）。
    /// > 各呼び出しを**独立した one-shot** として扱いたい場合は、呼び出し前に
    /// > ``resetChatSession()`` で履歴をクリアするか、会話配列を明示的に渡せて
    /// > 履歴が累積しない ``generateFromMessages(model:messages:systemPrompt:config:tools:)``
    /// > を使用する。
    ///
    /// > Note: この経路の ``GenerationStats/tokensPerSecond`` は、バックエンドが
    /// > 実測トークン統計を流さないためテキストチャンク数による近似値。実測値が
    /// > 必要な場合は ``generateWithTools`` / ``generateFromMessages`` を使用する。
    ///
    /// - Parameters:
    ///   - model: 生成に使用するモデル仕様。
    ///   - prompt: 生成元の入力プロンプト。
    ///   - config: 生成を制御する設定パラメータ。デフォルトは ``GenerationConfig/default``。
    /// - Returns: 生成されたトークン文字列の非同期ストリーム。
    public func generate(
        model: ModelSpec,
        prompt: String,
        config: GenerationConfig = .default
    ) -> AsyncThrowingStream<String, Error> {
        let backend = self.backend
        let modelSwitcher = self.modelSwitcher
        let startTime = ContinuousClock.now

        return makeCancellableStream { [weak self] continuation in
            Task {
                do {
                    // Load model: use switcher if available, otherwise direct backend
                    if let switcher = modelSwitcher {
                        try await switcher.ensureLoaded(model)
                    } else {
                        let currentModel = await backend.currentModel
                        if currentModel != model {
                            try await backend.loadModel(model)
                        }
                    }

                    // Generate tokens and track stats
                    var tokenCount = 0
                    let innerStream = backend.generate(prompt: prompt, config: config)
                    for try await token in innerStream {
                        try Task.checkCancellation()
                        tokenCount += 1
                        continuation.yield(token)
                    }

                    // Record stats
                    let duration = ContinuousClock.now - startTime
                    let seconds = Double(duration.components.seconds)
                        + Double(duration.components.attoseconds) / 1e18
                    let tokensPerSecond = seconds > 0
                        ? Double(tokenCount) / seconds : 0

                    let stats = GenerationStats(
                        tokenCount: tokenCount,
                        tokensPerSecond: tokensPerSecond,
                        duration: duration
                    )
                    await self?.updateStats(stats)

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMLocalError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// 指定されたモデルを使用してツール呼び出しサポート付きのレスポンスを生成する。
    ///
    /// モデルがバックエンドに現在読み込まれていない場合、生成開始前に自動的に
    /// 読み込まれる。生成統計は追跡され、ストリーム完了後に
    /// ``lastGenerationStats`` で参照できる。
    ///
    /// > Important: ``generate(model:prompt:config:)`` と同様に**会話継続
    /// > （ステートフル）API**。独立した呼び出しにしたい場合は事前に
    /// > ``resetChatSession()`` を呼ぶか、``generateFromMessages`` を使用する。
    ///
    /// - Parameters:
    ///   - model: 生成に使用するモデル仕様。
    ///   - prompt: 生成元の入力プロンプト。
    ///   - tools: モデルが使用可能なツール定義。
    ///   - config: 生成を制御する設定パラメータ。デフォルトは ``GenerationConfig/default``。
    /// - Returns: ``GenerationOutput`` 値の非同期ストリーム。
    public func generateWithTools(
        model: ModelSpec,
        prompt: String,
        tools: [ToolDefinition],
        config: GenerationConfig = .default
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        let backend = self.backend
        let modelSwitcher = self.modelSwitcher
        let startTime = ContinuousClock.now

        return makeCancellableStream { [weak self] continuation in
            Task {
                do {
                    try Self.validateToolCallSupport(model: model, tools: tools)

                    // Load model: use switcher if available, otherwise direct backend
                    if let switcher = modelSwitcher {
                        try await switcher.ensureLoaded(model)
                    } else {
                        let currentModel = await backend.currentModel
                        if currentModel != model {
                            try await backend.loadModel(model)
                        }
                    }

                    // Generate and track stats
                    var counter = TokenCounter()
                    let innerStream = backend.generateWithTools(
                        prompt: prompt, config: config, tools: tools
                    )
                    for try await output in innerStream {
                        try Task.checkCancellation()
                        counter.observe(output)
                        continuation.yield(output)
                    }

                    await self?.updateStats(counter.stats(since: startTime))

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMLocalError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// 構造化メッセージ配列からレスポンスを生成する。
    ///
    /// チャットテンプレートは内部で1回だけ適用される。
    /// `MessageFormatter` 等で事前フォーマットした文字列を `generate()` に渡す場合と異なり、
    /// 二重テンプレート適用を回避する。
    ///
    /// 履歴は累積しない（毎回フルメッセージ配列を受け取る）ステートレス API。
    /// 一方でバックエンド（MLX）は直前ターンと共通するプロンプト接頭辞の KV キャッシュを
    /// 再利用するため、エージェントループのように会話が伸びても prefill コストは差分のみに
    /// 抑えられる。
    ///
    /// - Parameters:
    ///   - model: 生成に使用するモデル仕様。
    ///   - messages: 会話履歴のメッセージ配列。
    ///   - systemPrompt: システムプロンプト（オプション）。
    ///   - config: 生成を制御する設定パラメータ。デフォルトは ``GenerationConfig/default``。
    ///   - tools: モデルが使用可能なツール定義。
    /// - Returns: ``GenerationOutput`` 値の非同期ストリーム。
    public func generateFromMessages(
        model: ModelSpec,
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig = .default,
        tools: [ToolDefinition] = []
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        let backend = self.backend
        let modelSwitcher = self.modelSwitcher
        let startTime = ContinuousClock.now

        return makeCancellableStream { [weak self] continuation in
            Task {
                do {
                    try Self.validateToolCallSupport(model: model, tools: tools)

                    // Load model: use switcher if available, otherwise direct backend
                    if let switcher = modelSwitcher {
                        try await switcher.ensureLoaded(model)
                    } else {
                        let currentModel = await backend.currentModel
                        if currentModel != model {
                            try await backend.loadModel(model)
                        }
                    }

                    // Generate and track stats
                    var counter = TokenCounter()
                    let innerStream = backend.generateFromMessages(
                        messages: messages,
                        systemPrompt: systemPrompt,
                        config: config,
                        tools: tools
                    )
                    for try await output in innerStream {
                        try Task.checkCancellation()
                        counter.observe(output)
                        continuation.yield(output)
                    }

                    await self?.updateStats(counter.stats(since: startTime))

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMLocalError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Tool Call Capability

    /// ツールコール非対応モデルへのツール付きリクエストを拒否する。
    ///
    /// ツールコール対応はバックエンドではなくモデル（チャットテンプレート）に
    /// 依存するため、型レベルではなくモデルプロファイルで検証する。
    /// プロファイル未設定のモデルは検証をスキップする（対応未知として許容）。
    private static func validateToolCallSupport(
        model: ModelSpec,
        tools: [ToolDefinition]
    ) throws {
        guard !tools.isEmpty,
              model.profile?.toolCallSupport == ToolCallSupport.unsupported
        else { return }
        throw LLMLocalError.toolCallsUnsupported(modelId: model.id)
    }

    // MARK: - System Prompt

    /// 現在のシステムプロンプト。設定されていない場合は `nil`。
    public var systemPrompt: String? {
        get async { await backend.systemPrompt }
    }

    /// 以降の生成に使用するシステムプロンプトを設定する。
    ///
    /// プロンプトはバックエンドに転送され、アクティブなチャットセッションに即座に適用される。
    ///
    /// - Parameter prompt: システムプロンプト文字列、またはクリアする場合は `nil`。
    public func setSystemPrompt(_ prompt: String?) async {
        await backend.setSystemPrompt(prompt)
    }

    // MARK: - Downloaded Models (disk truth)

    /// 指定モデルがディスク上に**完全な形でダウンロード済み**かを返す。
    ///
    /// ダウンロード状態の唯一の真実はディスクの実体（完全なスナップショット）。
    /// アプリ再起動後も正しく判定できる。エンジン選択 UI の「DL 済みのみ選択可」判定や
    /// 一覧画面のバッジ表示はこれを使う。
    public func isDownloaded(_ spec: ModelSpec) -> Bool {
        inventory.isDownloaded(spec)
    }

    /// 候補のうちダウンロード済みのものを ``DownloadedModel``（実サイズ・DL 時刻込み）で返す。
    public func downloadedModels(among specs: [ModelSpec]) -> [DownloadedModel] {
        inventory.downloadedModels(among: specs)
    }

    /// 指定モデルのディスク実サイズ（バイト単位）。未ダウンロードなら `nil`。
    public func downloadSize(of spec: ModelSpec) -> Int64? {
        inventory.diskSize(of: spec)
    }

    /// 候補のうちダウンロード済みモデルの合計ディスク使用量（バイト単位）。
    public func totalDownloadedSize(among specs: [ModelSpec]) -> Int64 {
        inventory.totalDiskSize(among: specs)
    }

    /// 指定モデルのダウンロード済みファイルをディスクから削除する（容量解放）。
    ///
    /// 現在ロード中のモデルを削除する場合は、先に ``backend`` をアンロードする。
    /// `.local` 指定のモデルは外部所有のため削除しない。
    ///
    /// - Parameter spec: 削除するモデル仕様。
    /// - Throws: ディレクトリ削除に失敗した場合。
    public func deleteDownload(_ spec: ModelSpec) async throws {
        // 削除対象が現在ロード中なら、ファイルを掴んだままにしないようアンロードする。
        if await backend.currentModel == spec {
            await backend.unloadModel()
        }
        try inventory.delete(spec)
    }

    /// 指定されたモデルをバックエンドにプリロードする。
    ///
    /// ユーザーが生成を要求する前にモデルをウォームアップし、体感レイテンシを低減するのに有用。
    ///
    /// - Parameter spec: プリロードするモデル仕様。
    /// - Throws: モデルの読み込みに失敗した場合。
    public func prefetch(_ spec: ModelSpec) async throws {
        try await backend.loadModel(spec)
    }

    /// 指定されたモデルをプリロードし、ダウンロード進捗を報告する。
    ///
    /// - Parameters:
    ///   - spec: プリロードするモデル仕様。
    ///   - onProgress: ダウンロード進捗の更新時に呼び出されるクロージャ。
    /// - Throws: モデルの読み込みに失敗した場合。
    public func prefetch(
        _ spec: ModelSpec,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        try await backend.loadModel(spec, progressHandler: onProgress)
    }

    // MARK: - Session Management

    /// チャットセッションの会話履歴をリセットする。
    ///
    /// モデルは読み込まれたまま保持し、会話のみをクリアして新しい会話を開始する。
    public func resetChatSession() async {
        await backend.resetSession()
    }

    // MARK: - Memory Monitoring

    /// メモリ監視を開始する。メモリ警告を受信すると、現在読み込まれているモデルが自動的にアンロードされる。
    ///
    /// 初期化時に ``MemoryMonitor`` が提供されていない場合、何も行わない。
    public func startMemoryMonitoring() async {
        guard let monitor = memoryMonitor else { return }
        let backend = self.backend
        await monitor.startMonitoring {
            await backend.unloadModel()
        }
    }

    /// メモリ監視を停止する。
    ///
    /// 初期化時に ``MemoryMonitor`` が提供されていない場合、何も行わない。
    public func stopMemoryMonitoring() async {
        await memoryMonitor?.stopMonitoring()
    }

    /// デバイスメモリに基づく推奨コンテキスト長を返す。
    ///
    /// - 8GB 以下: 2048
    /// - 12GB 以上: 4096
    ///
    /// - Returns: 推奨コンテキスト長。メモリモニターが設定されていない場合は `nil`。
    public func recommendedContextLength() async -> Int? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.recommendedContextLength()
    }

    /// デバイスの物理メモリ総量をバイト単位で返す。
    ///
    /// - Returns: 総メモリ量。メモリモニターが設定されていない場合は `nil`。
    public func totalMemory() async -> UInt64? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.totalMemory()
    }

    /// 現在利用可能なメモリをバイト単位で返す。
    ///
    /// - Returns: 利用可能メモリ量。メモリモニターが設定されていない場合は `nil`。
    public func availableMemory() async -> UInt64? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.availableMemory()
    }

    /// 指定されたモデルがこのデバイスで実行可能かを判定する。
    ///
    /// 判定基準: モデルの推定メモリ使用量 ≤ デバイス総メモリ × 0.8。
    ///
    /// - Parameter spec: 確認するモデル仕様。
    /// - Returns: 実行可能な場合は `true`。メモリモニターが未設定の場合は `nil`。
    public func isModelCompatible(_ spec: ModelSpec) async -> Bool? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.isModelCompatible(spec)
    }

    /// デバイスで実行可能なモデルの最大メモリ量をバイト単位で返す。
    ///
    /// デバイス総メモリの 80% を上限とする。
    /// - Returns: 最大許容メモリ量。メモリモニターが未設定の場合は `nil`。
    public func maxAllowedModelMemory() async -> UInt64? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.maxAllowedModelMemory()
    }

    // MARK: - Private

    private func updateStats(_ stats: GenerationStats) {
        lastGenerationStats = stats
    }
}

/// 生成ストリームからトークン統計を集計するヘルパー
///
/// バックエンドが ``GenerationInfo`` を流した場合は実測値を優先し、
/// 流さない場合はテキストチャンク数で近似する。
private struct TokenCounter {
    private var chunkCount = 0
    private var info: GenerationInfo?

    mutating func observe(_ output: GenerationOutput) {
        switch output {
        case .text:
            chunkCount += 1
        case .info(let generationInfo):
            info = generationInfo
        case .toolCall:
            break
        }
    }

    func stats(since startTime: ContinuousClock.Instant) -> GenerationStats {
        let duration = ContinuousClock.now - startTime
        if let info {
            return GenerationStats(
                tokenCount: info.generationTokenCount,
                tokensPerSecond: info.tokensPerSecond,
                duration: duration
            )
        }
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return GenerationStats(
            tokenCount: chunkCount,
            tokensPerSecond: seconds > 0 ? Double(chunkCount) / seconds : 0,
            duration: duration
        )
    }
}
