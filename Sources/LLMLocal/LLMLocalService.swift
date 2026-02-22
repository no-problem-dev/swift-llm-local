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

    /// Statistics from the most recent completed generation, or `nil` if
    /// no generation has completed yet.
    private(set) public var lastGenerationStats: GenerationStats?

    /// Creates a new service with the specified backend, model manager,
    /// and optional memory monitor.
    ///
    /// - Parameters:
    ///   - backend: The inference backend to use for model loading and text generation.
    ///   - modelManager: The model manager for cache queries.
    ///   - memoryMonitor: An optional memory monitor for automatic model unloading
    ///     on memory pressure. Defaults to `nil`.
    public init(
        backend: any LLMLocalBackend,
        modelManager: ModelManager,
        memoryMonitor: MemoryMonitor? = nil
    ) {
        self.backend = backend
        self.modelManager = modelManager
        self.memoryMonitor = memoryMonitor
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
        let startTime = ContinuousClock.now

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                do {
                    // Load model if not already loaded
                    let currentModel = await backend.currentModel
                    if currentModel != model {
                        try await backend.loadModel(model)
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
