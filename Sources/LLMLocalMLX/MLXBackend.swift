import LLMLocalClient
import MLX
import MLXLLM
@preconcurrency import MLXLMCommon

/// MLX-based backend for local LLM inference.
///
/// This actor wraps the mlx-swift-lm APIs to provide a conformance
/// to ``LLMLocalBackend``. It manages model loading, text generation,
/// and GPU cache configuration.
public actor MLXBackend: LLMLocalBackend {

    // MARK: - Internal State

    private var chatSession: ChatSession?
    private var loadedSpec: ModelSpec?
    private let gpuCacheLimit: Int

    /// Tracks whether a model load is currently in progress, for exclusive control.
    private var isLoading: Bool = false

    // MARK: - Test Accessors

    /// Exposes the GPU cache limit for testing purposes.
    var gpuCacheLimitValue: Int { gpuCacheLimit }

    /// Exposes the loading state for testing purposes.
    var isLoadingValue: Bool { isLoading }

    // MARK: - Initialization

    /// Creates a new MLXBackend with the specified GPU cache limit.
    ///
    /// - Parameter gpuCacheLimit: Maximum GPU cache size in bytes.
    ///   Defaults to 20 MB (20 * 1024 * 1024).
    public init(gpuCacheLimit: Int = 20 * 1024 * 1024) {
        self.gpuCacheLimit = gpuCacheLimit
    }

    // MARK: - LLMLocalBackend

    public func loadModel(_ spec: ModelSpec) async throws {
        // If same model already loaded, skip
        if loadedSpec == spec { return }

        // If another load is in progress, throw
        guard !isLoading else { throw LLMLocalError.loadInProgress }

        isLoading = true
        defer { isLoading = false }

        await unloadModel()

        MLX.Memory.cacheLimit = gpuCacheLimit

        let hfID: String
        switch spec.base {
        case .huggingFace(let id):
            hfID = id
        case .local(let path):
            hfID = path.path()
        }

        do {
            let modelContainer = try await MLXLMCommon.loadModelContainer(id: hfID)
            chatSession = ChatSession(modelContainer)
            loadedSpec = spec
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

    public func unloadModel() async {
        chatSession = nil
        loadedSpec = nil
    }

    public var isLoaded: Bool { chatSession != nil }

    public var currentModel: ModelSpec? { loadedSpec }

    // MARK: - Private Helpers

    /// Performs the actual generation work within the actor's isolation context.
    /// This avoids sending the non-Sendable `ChatSession` across isolation boundaries.
    private func performGenerate(
        prompt: String,
        config: GenerationConfig,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        guard let session = chatSession else {
            continuation.finish(throwing: LLMLocalError.modelNotLoaded)
            return
        }

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
}
