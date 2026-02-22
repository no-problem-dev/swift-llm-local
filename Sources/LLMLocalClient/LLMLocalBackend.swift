/// Abstraction for a local LLM inference backend.
///
/// Conforming types provide the ability to load models, generate text, and manage model lifecycle.
/// All conforming types must be `Sendable` to support concurrent access.
public protocol LLMLocalBackend: Sendable {
    /// Loads the specified model into memory for inference.
    /// - Parameter spec: The model specification describing which model to load.
    /// - Throws: An error if the model cannot be loaded.
    func loadModel(_ spec: ModelSpec) async throws

    /// Generates text from the given prompt, streaming tokens as they are produced.
    /// - Parameters:
    ///   - prompt: The input prompt to generate from.
    ///   - config: Configuration parameters controlling the generation.
    /// - Returns: An asynchronous stream of generated token strings.
    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error>

    /// Unloads the currently loaded model, freeing memory.
    func unloadModel() async

    /// Whether a model is currently loaded and ready for inference.
    var isLoaded: Bool { get async }

    /// The specification of the currently loaded model, or `nil` if no model is loaded.
    var currentModel: ModelSpec? { get async }
}
