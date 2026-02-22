/// Describes a tool that can be invoked by the language model during generation.
public struct ToolDefinition: Sendable {
    /// The name of the tool (used by the model to reference it).
    public let name: String
    /// A human-readable description of what the tool does.
    public let description: String
    /// The parameters the tool accepts.
    public let parameters: [ParameterDefinition]

    public init(name: String, description: String, parameters: [ParameterDefinition]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Describes a single parameter for a ``ToolDefinition``.
public struct ParameterDefinition: Sendable {
    /// The parameter name.
    public let name: String
    /// The JSON Schema type of the parameter.
    public let type: ParameterType
    /// A human-readable description of the parameter.
    public let description: String
    /// Whether the parameter is required.
    public let isRequired: Bool

    public init(name: String, type: ParameterType, description: String, isRequired: Bool) {
        self.name = name
        self.type = type
        self.description = description
        self.isRequired = isRequired
    }

    /// Creates a required parameter definition.
    public static func required(
        _ name: String, type: ParameterType, description: String
    ) -> Self {
        .init(name: name, type: type, description: description, isRequired: true)
    }

    /// Creates an optional parameter definition.
    public static func optional(
        _ name: String, type: ParameterType, description: String
    ) -> Self {
        .init(name: name, type: type, description: description, isRequired: false)
    }
}

/// JSON Schema types supported by tool parameters.
public indirect enum ParameterType: Sendable {
    case string
    case integer
    case number
    case boolean
    case array(elementType: ParameterType)
}
