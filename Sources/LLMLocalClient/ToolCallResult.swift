import LLMTool

/// 単一の生成ステップの出力（テキスト・ツール呼び出し・完了情報）
public enum GenerationOutput: Sendable {
    /// 生成されたテキストチャンク。
    case text(String)
    /// モデルからのツール呼び出しリクエスト。
    case toolCall(ToolCall)
    /// 生成完了時のトークン統計。ストリームの最後に1回だけ流れる。
    case info(GenerationInfo)
}

/// 生成完了時のトークン統計
///
/// バックエンドが実測したトークン数を上位層（usage 報告・統計）に伝搬する。
public struct GenerationInfo: Sendable, Equatable {
    /// 入力プロンプトのトークン数。
    public let promptTokenCount: Int
    /// 生成されたトークン数。
    public let generationTokenCount: Int
    /// 生成スループット（トークン/秒）。
    public let tokensPerSecond: Double

    /// 生成統計を初期化する。
    /// - Parameters:
    ///   - promptTokenCount: 入力プロンプトのトークン数。
    ///   - generationTokenCount: 生成されたトークン数。
    ///   - tokensPerSecond: 生成スループット（トークン/秒）。
    public init(promptTokenCount: Int, generationTokenCount: Int, tokensPerSecond: Double) {
        self.promptTokenCount = promptTokenCount
        self.generationTokenCount = generationTokenCount
        self.tokensPerSecond = tokensPerSecond
    }
}
