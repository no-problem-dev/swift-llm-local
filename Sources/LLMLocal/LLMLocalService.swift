import LLMLocalClient
import LLMLocalMLX
import LLMLocalModels

/// A facade that integrates a backend and model manager for convenient LLM operations.
///
/// `LLMLocalService` provides a high-level API for text generation. It automatically
/// handles model loading when needed and tracks generation statistics. Optionally,
/// a ``MemoryMonitor`` can be provided to enable automatic model unloading on
/// memory pressure.
///
/// ## Usage
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

    /// Statistics from the most recent completed generation, or `nil` if
    /// no generation has completed yet.
    private(set) public var lastGenerationStats: GenerationStats?

    /// Creates a new service with the specified backend, model manager,
    /// and optional memory monitor and model switcher.
    ///
    /// - Parameters:
    ///   - backend: The inference backend to use for model loading and text generation.
    ///   - modelManager: The model manager for cache queries.
    ///   - memoryMonitor: An optional memory monitor for automatic model unloading
    ///     on memory pressure. Defaults to `nil`.
    ///   - modelSwitcher: An optional model switcher for LRU-based multi-model
    ///     management. When provided, model loading is delegated to the switcher
    ///     instead of directly calling the backend. Defaults to `nil`.
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

    /// Generates text from the given prompt using the specified model.
    ///
    /// If the model is not currently loaded in the backend, it will be loaded
    /// automatically before generation begins. Generation statistics are tracked
    /// and available via ``lastGenerationStats`` after the stream completes.
    ///
    /// - Parameters:
    ///   - model: The model specification to use for generation.
    ///   - prompt: The input prompt to generate from.
    ///   - config: Configuration parameters controlling the generation. Defaults to ``GenerationConfig/default``.
    /// - Returns: An asynchronous stream of generated token strings.
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

    /// Generates a response with tool calling support using the specified model.
    ///
    /// If the model is not currently loaded in the backend, it will be loaded
    /// automatically before generation begins. Generation statistics are tracked
    /// and available via ``lastGenerationStats`` after the stream completes.
    /// Only text chunks are counted toward the token count.
    ///
    /// - Parameters:
    ///   - model: The model specification to use for generation.
    ///   - prompt: The input prompt to generate from.
    ///   - tools: The set of tools available to the model.
    ///   - config: Configuration parameters controlling the generation. Defaults to ``GenerationConfig/default``.
    /// - Returns: An asynchronous stream of ``GenerationOutput`` values.
    public func generateWithTools(
        model: ModelSpec,
        prompt: String,
        tools: ToolSet,
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

    /// The current system prompt, or `nil` if none is set.
    public var systemPrompt: String? {
        get async { await backend.systemPrompt }
    }

    /// Sets the system prompt for subsequent generations.
    ///
    /// The prompt is forwarded to the backend and applied to the active
    /// chat session immediately.
    ///
    /// - Parameter prompt: The system prompt string, or `nil` to clear it.
    public func setSystemPrompt(_ prompt: String?) async {
        await backend.setSystemPrompt(prompt)
    }

    /// Checks whether the specified model is cached (has been downloaded).
    ///
    /// - Parameter spec: The model specification to check.
    /// - Returns: `true` if the model is registered in the cache.
    public func isModelCached(_ spec: ModelSpec) async -> Bool {
        await modelManager.isCached(spec)
    }

    /// Preloads the specified model into the backend.
    ///
    /// This is useful for warming up the model before the user requests generation,
    /// reducing perceived latency.
    ///
    /// - Parameter spec: The model specification to preload.
    /// - Throws: An error if the model cannot be loaded.
    public func prefetch(_ spec: ModelSpec) async throws {
        try await backend.loadModel(spec)
    }

    /// Preloads the specified model, reporting download progress.
    ///
    /// - Parameters:
    ///   - spec: The model specification to preload.
    ///   - onProgress: A closure called with download progress updates.
    /// - Throws: An error if the model cannot be loaded.
    public func prefetch(
        _ spec: ModelSpec,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        try await backend.loadModel(spec, progressHandler: onProgress)
    }

    // MARK: - Memory Monitoring

    /// Starts memory monitoring. When a memory warning is received,
    /// the currently loaded model will be automatically unloaded.
    ///
    /// If no ``MemoryMonitor`` was provided at initialization, this method
    /// does nothing.
    public func startMemoryMonitoring() async {
        guard let monitor = memoryMonitor else { return }
        let backend = self.backend
        await monitor.startMonitoring {
            await backend.unloadModel()
        }
    }

    /// Stops memory monitoring.
    ///
    /// If no ``MemoryMonitor`` was provided at initialization, this method
    /// does nothing.
    public func stopMemoryMonitoring() async {
        await memoryMonitor?.stopMonitoring()
    }

    /// Returns the recommended context length based on device memory.
    ///
    /// The recommendation is based on the device's total physical memory:
    /// - 8GB or less: 2048
    /// - 12GB or more: 4096
    ///
    /// - Returns: The recommended context length, or `nil` if no memory
    ///   monitor is configured.
    public func recommendedContextLength() async -> Int? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.recommendedContextLength()
    }

    // MARK: - Private

    private func updateStats(_ stats: GenerationStats) {
        lastGenerationStats = stats
    }
}
