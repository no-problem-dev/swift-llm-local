/// A tool invocation request produced by the language model.
public struct ToolCallRequest: Sendable, Equatable {
    /// The name of the tool the model wants to call.
    public let name: String
    /// The arguments as a JSON-encoded string.
    public let argumentsJSON: String

    public init(name: String, argumentsJSON: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// The output of a single generation step, which can be either text or a tool call.
public enum GenerationOutput: Sendable {
    /// A chunk of generated text.
    case text(String)
    /// A tool invocation request from the model.
    case toolCall(ToolCallRequest)
}
