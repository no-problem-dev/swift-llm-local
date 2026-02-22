/// Statistics about a completed text generation.
public struct GenerationStats: Sendable {
    /// Number of tokens generated.
    public let tokenCount: Int
    /// Generation throughput in tokens per second.
    public let tokensPerSecond: Double
    /// Total wall-clock duration of the generation.
    public let duration: Duration

    /// Creates a new generation statistics record.
    /// - Parameters:
    ///   - tokenCount: Number of tokens generated.
    ///   - tokensPerSecond: Generation throughput in tokens per second.
    ///   - duration: Total wall-clock duration of the generation.
    public init(tokenCount: Int, tokensPerSecond: Double, duration: Duration) {
        self.tokenCount = tokenCount
        self.tokensPerSecond = tokensPerSecond
        self.duration = duration
    }
}
