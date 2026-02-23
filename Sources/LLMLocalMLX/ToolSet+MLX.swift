import Foundation
import LLMLocalClient
import MLXLMCommon

extension ToolSet {
    /// Converts this tool set to MLX-compatible tool spec dictionaries.
    ///
    /// Each tool is converted to the standard function-calling format expected
    /// by MLX chat sessions. The ``Tool/inputSchema`` is serialized to a
    /// `[String: Any]` dictionary and placed under the `"parameters"` key.
    var mlxToolSpecs: [[String: any Sendable]] {
        tools.map { tool in
            var parametersDict: [String: any Sendable] = [:]
            if let schemaData = try? tool.inputSchema.toJSONData(),
               let schemaDict = try? JSONSerialization.jsonObject(with: schemaData) as? [String: any Sendable] {
                parametersDict = schemaDict
            }

            return [
                "type": "function",
                "function": [
                    "name": tool.toolName,
                    "description": tool.toolDescription,
                    "parameters": parametersDict,
                ] as [String: any Sendable],
            ]
        }
    }
}

extension ToolCallRequest {
    /// Creates a ``ToolCallRequest`` from an MLX ``MLXLMCommon/ToolCall``.
    init(from toolCall: MLXLMCommon.ToolCall) {
        let jsonObject = toolCall.function.arguments.mapValues { $0.anyValue }
        let jsonData = (try? JSONSerialization.data(withJSONObject: jsonObject)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        self.init(name: toolCall.function.name, argumentsJSON: jsonString)
    }
}
