/// Abstraction for a local LLM inference backend.
///
/// Conforming types provide the ability to load models, generate text, and manage model lifecycle.
/// All conforming types must be `Sendable` to support concurrent access.
public protocol LLMLocalBackend: Sendable {
    /// Loads the specified model into memory for inference.
    /// - Parameter spec: The model specification describing which model to load.
    /// - Throws: An error if the model cannot be loaded.
    func loadModel(_ spec: ModelSpec) async throws

    /// Loads the specified model into memory, reporting download progress.
    ///
    /// - Parameters:
    ///   - spec: The model specification describing which model to load.
    ///   - progressHandler: A closure called with download progress updates.
    /// - Throws: An error if the model cannot be loaded.
    func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws

    /// Generates text from the given prompt, streaming tokens as they are produced.
    /// - Parameters:
    ///   - prompt: The input prompt to generate from.
    ///   - config: Configuration parameters controlling the generation.
    /// - Returns: An asynchronous stream of generated token strings.
    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error>

    /// Generates a response with tool calling support, streaming output chunks.
    ///
    /// Each element of the returned stream is either a text chunk or a tool call request
    /// parsed by the underlying model.
    /// - Parameters:
    ///   - prompt: The input prompt to generate from.
    ///   - config: Configuration parameters controlling the generation.
    ///   - tools: The set of tools available to the model.
    /// - Returns: An asynchronous stream of ``GenerationOutput`` values.
    func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: ToolSet
    ) -> AsyncThrowingStream<GenerationOutput, Error>

    /// Unloads the currently loaded model, freeing memory.
    func unloadModel() async

    /// Whether a model is currently loaded and ready for inference.
    var isLoaded: Bool { get async }

    /// The specification of the currently loaded model, or `nil` if no model is loaded.
    var currentModel: ModelSpec? { get async }

    /// The current system prompt, or `nil` if none is set.
    var systemPrompt: String? { get async }

    /// Sets the system prompt for subsequent generations.
    func setSystemPrompt(_ prompt: String?) async
}

// MARK: - System Prompt

extension LLMLocalBackend {
    /// Default implementation returns `nil`.
    public var systemPrompt: String? { nil }

    /// Default implementation is a no-op.
    public func setSystemPrompt(_ prompt: String?) async {}
}

// MARK: - Default Implementation

extension LLMLocalBackend {
    /// Default implementation that ignores the progress handler and delegates to `loadModel(_:)`.
    public func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        try await loadModel(spec)
    }

    /// Default implementation that ignores tools and wraps each token as `.text`.
    public func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: ToolSet
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        let stream = generate(prompt: prompt, config: config)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await token in stream {
                        continuation.yield(.text(token))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
