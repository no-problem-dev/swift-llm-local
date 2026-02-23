/// テキスト生成完了後の統計情報
public struct GenerationStats: Sendable {
    /// 生成されたトークン数。
    public let tokenCount: Int
    /// 生成スループット（トークン/秒）。
    public let tokensPerSecond: Double
    /// 生成の実時間（ウォールクロック）。
    public let duration: Duration

    /// 新しい生成統計レコードを作成します。
    /// - Parameters:
    ///   - tokenCount: 生成されたトークン数。
    ///   - tokensPerSecond: 生成スループット（トークン/秒）。
    ///   - duration: 生成の実時間（ウォールクロック）。
    public init(tokenCount: Int, tokensPerSecond: Double, duration: Duration) {
        self.tokenCount = tokenCount
        self.tokensPerSecond = tokensPerSecond
        self.duration = duration
    }
}
