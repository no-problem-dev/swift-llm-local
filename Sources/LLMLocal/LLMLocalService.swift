import LLMLocalClient
import LLMLocalMLX
import LLMLocalModels

/// バックエンドとモデルマネージャーを統合し、便利なLLM操作を提供するファサード
///
/// `LLMLocalService` はテキスト生成のための高レベルAPIを提供します。
/// 必要に応じてモデルの読み込みを自動的に処理し、生成統計を追跡します。
/// オプションで ``MemoryMonitor`` を提供して、メモリ圧迫時の自動モデルアンロードを
/// 有効にできます。
///
/// ## 使用例
///
/// ```swift
/// let monitor = MemoryMonitor()
/// let service = LLMLocalService(
///     backend: mlxBackend,
///     modelManager: modelManager,
///     memoryMonitor: monitor
/// )
/// await service.startMemoryMonitoring()
///
/// let stream = await service.generate(
///     model: ModelPresets.gemma2B,
///     prompt: "What is Swift?"
/// )
/// for try await token in stream {
///     print(token, terminator: "")
/// }
/// ```
public actor LLMLocalService {

    private let backend: any LLMLocalBackend
    private let modelManager: ModelManager
    private let memoryMonitor: MemoryMonitor?
    private let modelSwitcher: ModelSwitcher?

    /// 最新の完了した生成の統計情報。まだ生成が完了していない場合は `nil`。
    private(set) public var lastGenerationStats: GenerationStats?

    /// 指定されたバックエンド、モデルマネージャー、およびオプションのメモリモニターと
    /// モデルスイッチャーで新しいサービスを作成します。
    ///
    /// - Parameters:
    ///   - backend: モデルの読み込みとテキスト生成に使用する推論バックエンド。
    ///   - modelManager: キャッシュ照会用のモデルマネージャー。
    ///   - memoryMonitor: メモリ圧迫時の自動モデルアンロード用のオプションメモリモニター。デフォルトは `nil`。
    ///   - modelSwitcher: LRUベースのマルチモデル管理用のオプションモデルスイッチャー。
    ///     指定された場合、バックエンドへの直接呼び出しの代わりにスイッチャーにモデル読み込みを委譲します。デフォルトは `nil`。
    public init(
        backend: any LLMLocalBackend,
        modelManager: ModelManager,
        memoryMonitor: MemoryMonitor? = nil,
        modelSwitcher: ModelSwitcher? = nil
    ) {
        self.backend = backend
        self.modelManager = modelManager
        self.memoryMonitor = memoryMonitor
        self.modelSwitcher = modelSwitcher
    }

    /// 指定されたモデルを使用してプロンプトからテキストを生成します。
    ///
    /// モデルがバックエンドに現在読み込まれていない場合、生成開始前に自動的に
    /// 読み込まれます。生成統計は追跡され、ストリーム完了後に
    /// ``lastGenerationStats`` で参照できます。
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

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
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

    /// 指定されたモデルを使用してツール呼び出しサポート付きのレスポンスを生成します。
    ///
    /// モデルがバックエンドに現在読み込まれていない場合、生成開始前に自動的に
    /// 読み込まれます。生成統計は追跡され、ストリーム完了後に
    /// ``lastGenerationStats`` で参照できます。
    /// テキストチャンクのみがトークン数にカウントされます。
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

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
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

                    // Generate and track stats
                    var tokenCount = 0
                    let innerStream = backend.generateWithTools(
                        prompt: prompt, config: config, tools: tools
                    )
                    for try await output in innerStream {
                        try Task.checkCancellation()
                        if case .text = output {
                            tokenCount += 1
                        }
                        continuation.yield(output)
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

    // MARK: - System Prompt

    /// 現在のシステムプロンプト。設定されていない場合は `nil`。
    public var systemPrompt: String? {
        get async { await backend.systemPrompt }
    }

    /// 以降の生成に使用するシステムプロンプトを設定します。
    ///
    /// プロンプトはバックエンドに転送され、アクティブなチャットセッションに
    /// 即座に適用されます。
    ///
    /// - Parameter prompt: システムプロンプト文字列、またはクリアする場合は `nil`。
    public func setSystemPrompt(_ prompt: String?) async {
        await backend.setSystemPrompt(prompt)
    }

    /// 指定されたモデルがキャッシュされている（ダウンロード済み）かを確認します。
    ///
    /// - Parameter spec: 確認するモデル仕様。
    /// - Returns: モデルがキャッシュに登録されている場合は `true`。
    public func isModelCached(_ spec: ModelSpec) async -> Bool {
        await modelManager.isCached(spec)
    }

    /// 指定されたモデルをバックエンドにプリロードします。
    ///
    /// ユーザーが生成を要求する前にモデルをウォームアップし、
    /// 体感レイテンシを低減するのに有用です。
    ///
    /// - Parameter spec: プリロードするモデル仕様。
    /// - Throws: モデルの読み込みに失敗した場合。
    public func prefetch(_ spec: ModelSpec) async throws {
        try await backend.loadModel(spec)
    }

    /// 指定されたモデルをプリロードし、ダウンロード進捗を報告します。
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

    // MARK: - Memory Monitoring

    /// メモリ監視を開始します。メモリ警告を受信すると、
    /// 現在読み込まれているモデルが自動的にアンロードされます。
    ///
    /// 初期化時に ``MemoryMonitor`` が提供されていない場合、このメソッドは何も行いません。
    public func startMemoryMonitoring() async {
        guard let monitor = memoryMonitor else { return }
        let backend = self.backend
        await monitor.startMonitoring {
            await backend.unloadModel()
        }
    }

    /// メモリ監視を停止します。
    ///
    /// 初期化時に ``MemoryMonitor`` が提供されていない場合、このメソッドは何も行いません。
    public func stopMemoryMonitoring() async {
        await memoryMonitor?.stopMonitoring()
    }

    /// デバイスメモリに基づく推奨コンテキスト長を返します。
    ///
    /// 推奨値はデバイスの物理メモリ総量に基づきます:
    /// - 8GB以下: 2048
    /// - 12GB以上: 4096
    ///
    /// - Returns: 推奨コンテキスト長。メモリモニターが設定されていない場合は `nil`。
    public func recommendedContextLength() async -> Int? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.recommendedContextLength()
    }

    // MARK: - Private

    private func updateStats(_ stats: GenerationStats) {
        lastGenerationStats = stats
    }
}
