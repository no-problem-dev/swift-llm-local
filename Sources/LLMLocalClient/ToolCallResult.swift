import LLMTool

/// One element of a generation stream: answer text, a tool call, or the closing usage record.
public enum GenerationOutput: Sendable {
    /// Fragment of the model's output, not necessarily a whole token or word.
    case text(String)
    /// Tool invocation the backend parsed out of the model's output, with its arguments already
    /// decoded.
    case toolCall(ToolCall)
    /// Token statistics, delivered at most once and always after the last text fragment.
    ///
    /// A stream that ends without it came from a backend that does not measure tokens; that is not
    /// a failure, but usage has to be estimated instead.
    case info(GenerationInfo)
}

/// Token counts and throughput measured by the backend for one generation.
///
/// On-device inference has no billing meter, so these are the only authoritative usage numbers
/// available. They are what upper layers report as usage rather than an estimate from text length.
public struct GenerationInfo: Sendable, Equatable {
    /// Tokens in the prompt the model was given.
    ///
    /// Counted after the chat template was applied, so it includes template scaffolding and the
    /// system prompt. Prompt-cache reuse does not shrink it: the stateless message path reports the
    /// full conversation length even when only the new suffix was actually processed, which keeps
    /// input usage comparable across turns.
    public let promptTokenCount: Int
    /// Tokens the model produced, counted by the runtime rather than inferred from the text.
    public let generationTokenCount: Int
    /// Decode throughput in tokens per second.
    ///
    /// Derived from the generated token count and the decode time alone, so prompt processing is
    /// excluded and the figure does not sag on a long prompt. It is zero when the runtime reported
    /// no measurable decode time.
    public let tokensPerSecond: Double

    /// - Parameters:
    ///   - promptTokenCount: Tokens in the templated prompt.
    ///   - generationTokenCount: Tokens the model produced.
    ///   - tokensPerSecond: Decode throughput in tokens per second.
    public init(promptTokenCount: Int, generationTokenCount: Int, tokensPerSecond: Double) {
        self.promptTokenCount = promptTokenCount
        self.generationTokenCount = generationTokenCount
        self.tokensPerSecond = tokensPerSecond
    }
}
