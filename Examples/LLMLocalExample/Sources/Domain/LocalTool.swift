import LLMLocal

protocol LocalTool: Sendable, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }
    var definition: ToolDefinition { get }
    func execute(arguments: String) async throws -> String
}

extension LocalTool {
    var id: String { definition.name }
}
