/// What one completed generation cost, recorded once the stream finishes.
///
/// The three numbers do not come from the same clock, and dividing one by another will not
/// reproduce the third. ``duration`` is always measured by the caller and spans the whole call —
/// including a model load and prompt processing — while ``tokensPerSecond`` reflects the decode
/// phase alone whenever the backend measured it. Read it as "how fast did the model write", not as
/// "how long did the user wait"; ``duration`` answers the second question.
public struct GenerationStats: Sendable {
    /// Tokens the model produced.
    ///
    /// Measured by the backend when it reports usage. Backends that do not — the plain text
    /// generation path — leave the collector counting stream fragments instead, which is close to
    /// the token count but not equal to it.
    public let tokenCount: Int
    /// Decode throughput in tokens per second.
    ///
    /// When the backend measured it, the denominator is generation time only: model loading and
    /// prompt processing are excluded, so the figure stays comparable across prompt lengths. When it
    /// did not, this falls back to fragments divided by ``duration``, which does include load and
    /// prefill and therefore reads far lower on a long prompt or a cold start.
    public let tokensPerSecond: Double
    /// Wall-clock time for the whole call, measured from before the model was loaded.
    ///
    /// This is the latency a user experiences: it covers loading a model that was not resident,
    /// prompt processing, and decoding.
    public let duration: Duration

    /// - Parameters:
    ///   - tokenCount: Tokens the model produced.
    ///   - tokensPerSecond: Decode throughput in tokens per second.
    ///   - duration: Wall-clock time for the whole call.
    public init(tokenCount: Int, tokensPerSecond: Double, duration: Duration) {
        self.tokenCount = tokenCount
        self.tokensPerSecond = tokensPerSecond
        self.duration = duration
    }
}
