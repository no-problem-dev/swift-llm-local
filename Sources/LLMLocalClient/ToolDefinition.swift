/// 言語モデルが生成中に呼び出し可能なツールの定義
public struct ToolDefinition: Sendable {
    /// ツールの名前（モデルが参照に使用）。
    public let name: String
    /// ツールの機能を説明する人間可読な説明文。
    public let description: String
    /// ツールが受け付けるパラメータ。
    public let parameters: [ParameterDefinition]

    public init(name: String, description: String, parameters: [ParameterDefinition]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// ``ToolDefinition`` の単一パラメータの定義
public struct ParameterDefinition: Sendable {
    /// パラメータ名。
    public let name: String
    /// パラメータの JSON Schema 型。
    public let type: ParameterType
    /// パラメータの人間可読な説明文。
    public let description: String
    /// パラメータが必須かどうか。
    public let isRequired: Bool

    public init(name: String, type: ParameterType, description: String, isRequired: Bool) {
        self.name = name
        self.type = type
        self.description = description
        self.isRequired = isRequired
    }

    /// 必須パラメータ定義を作成します。
    public static func required(
        _ name: String, type: ParameterType, description: String
    ) -> Self {
        .init(name: name, type: type, description: description, isRequired: true)
    }

    /// オプションパラメータ定義を作成します。
    public static func optional(
        _ name: String, type: ParameterType, description: String
    ) -> Self {
        .init(name: name, type: type, description: description, isRequired: false)
    }
}

/// ツールパラメータがサポートする JSON Schema 型
public indirect enum ParameterType: Sendable {
    case string
    case integer
    case number
    case boolean
    case array(elementType: ParameterType)
}
