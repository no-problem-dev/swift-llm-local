import LLMTool

/// 単一の生成ステップの出力（テキストまたはツール呼び出し）
public enum GenerationOutput: Sendable {
    /// 生成されたテキストチャンク。
    case text(String)
    /// モデルからのツール呼び出しリクエスト。
    case toolCall(ToolCall)
}
