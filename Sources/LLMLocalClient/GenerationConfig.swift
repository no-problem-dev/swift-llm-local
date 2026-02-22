/// Configuration parameters for text generation.
public struct GenerationConfig: Sendable {
    /// Maximum number of tokens to generate.
    public var maxTokens: Int
    /// Sampling temperature. Higher values produce more random output.
    public var temperature: Float
    /// Top-p (nucleus) sampling threshold.
    public var topP: Float

    /// Creates a new generation configuration.
    /// - Parameters:
    ///   - maxTokens: Maximum number of tokens to generate. Defaults to 1024.
    ///   - temperature: Sampling temperature. Defaults to 0.7.
    ///   - topP: Top-p sampling threshold. Defaults to 0.9.
    public init(maxTokens: Int = 1024, temperature: Float = 0.7, topP: Float = 0.9) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
    }

    /// Default generation configuration (maxTokens: 1024, temperature: 0.7, topP: 0.9).
    public static let `default` = GenerationConfig()
}
