/// 言語モデルが生成したツール呼び出しリクエスト
public struct ToolCallRequest: Sendable, Equatable {
    /// モデルが呼び出したいツールの名前。
    public let name: String
    /// JSON エンコードされた引数文字列。
    public let argumentsJSON: String

    public init(name: String, argumentsJSON: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// 単一の生成ステップの出力（テキストまたはツール呼び出し）
public enum GenerationOutput: Sendable {
    /// 生成されたテキストチャンク。
    case text(String)
    /// モデルからのツール呼び出しリクエスト。
    case toolCall(ToolCallRequest)
}
