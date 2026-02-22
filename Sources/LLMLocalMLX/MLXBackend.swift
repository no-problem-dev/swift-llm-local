import Foundation
import LLMLocalClient
import MLX
import MLXLLM
@preconcurrency import MLXLMCommon

/// MLX-based backend for local LLM inference.
///
/// This actor wraps the mlx-swift-lm APIs to provide a conformance
/// to ``LLMLocalBackend``. It manages model loading, text generation,
/// GPU cache configuration, and optional LoRA adapter merging.
///
/// ## Adapter Support
///
/// When a ``ModelSpec`` includes an ``AdapterSource``, the backend resolves
/// the adapter to a local URL via an ``AdapterResolving`` instance and passes
/// the adapter path to the MLX model loading pipeline.
///
/// ```swift
/// let backend = MLXBackend(adapterResolver: adapterManager)
/// try await backend.loadModel(specWithAdapter)
/// ```
public actor MLXBackend: LLMLocalBackend {

    // MARK: - Internal State

    private var chatSession: ChatSession?
    private var loadedSpec: ModelSpec?
    private let gpuCacheLimit: Int

    /// Optional resolver for LoRA/QLoRA adapters.
    private let adapterResolver: (any AdapterResolving)?

    /// The most recently resolved adapter URL, captured during loadModel.
    /// Exposed for testing to verify that adapter resolution produces
    /// the expected URL and passes it to the model loading pipeline.
    private(set) var lastResolvedAdapterURL: URL?

    /// Tracks whether a model load is currently in progress, for exclusive control.
    private var isLoading: Bool = false

    // MARK: - Test Accessors

    /// Exposes the GPU cache limit for testing purposes.
    var gpuCacheLimitValue: Int { gpuCacheLimit }

    /// Exposes the loading state for testing purposes.
    var isLoadingValue: Bool { isLoading }

    /// Whether an adapter resolver has been configured.
    var hasAdapterResolver: Bool { adapterResolver != nil }

    // MARK: - Initialization

    /// Creates a new MLXBackend with the specified GPU cache limit and optional adapter resolver.
    ///
    /// - Parameters:
    ///   - gpuCacheLimit: Maximum GPU cache size in bytes.
    ///     Defaults to 20 MB (20 * 1024 * 1024).
    ///   - adapterResolver: An optional ``AdapterResolving`` instance for resolving
    ///     LoRA/QLoRA adapter sources to local file URLs. When `nil`, loading a model
    ///     with an adapter will throw ``LLMLocalError/adapterMergeFailed(reason:)``.
    public init(
        gpuCacheLimit: Int = 20 * 1024 * 1024,
        adapterResolver: (any AdapterResolving)? = nil
    ) {
        self.gpuCacheLimit = gpuCacheLimit
        self.adapterResolver = adapterResolver
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
            // Load base model
            let modelContainer = try await MLXLMCommon.loadModelContainer(id: hfID)

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

            chatSession = ChatSession(modelContainer)
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

    public func unloadModel() async {
        chatSession = nil
        loadedSpec = nil
    }

    public var isLoaded: Bool { chatSession != nil }

    public var currentModel: ModelSpec? { loadedSpec }

    // MARK: - Internal Helpers

    /// Resolves an adapter source to a local URL if an adapter is specified.
    ///
    /// Returns `nil` when the spec has no adapter. Throws when the spec has
    /// an adapter but no resolver is configured, or when resolution fails.
    ///
    /// Extracted as a separate method for testability -- this can be called
    /// without requiring GPU/Metal access.
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
