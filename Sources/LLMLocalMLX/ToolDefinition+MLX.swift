import Foundation
import LLMLocalClient
import MLXLMCommon

extension ToolDefinition {
    /// このツール定義を MLX 互換の ``ToolSpec`` ディクショナリに変換します。
    var toolSpec: [String: any Sendable] {
        var properties: [String: any Sendable] = [:]
        var requiredParams: [String] = []

        for param in parameters {
            properties[param.name] = param.type.jsonSchema(description: param.description)
            if param.isRequired {
                requiredParams.append(param.name)
            }
        }

        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": requiredParams,
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ]
    }
}

extension ParameterType {
    /// このパラメータ型を JSON Schema ディクショナリに変換します。
    func jsonSchema(description: String) -> [String: any Sendable] {
        switch self {
        case .string:
            return ["type": "string", "description": description]
        case .integer:
            return ["type": "integer", "description": description]
        case .number:
            return ["type": "number", "description": description]
        case .boolean:
            return ["type": "boolean", "description": description]
        case .array(let elementType):
            return [
                "type": "array",
                "description": description,
                "items": elementType.jsonSchema(description: ""),
            ]
        }
    }
}

extension ToolCallRequest {
    /// MLX の ``ToolCall`` から ``ToolCallRequest`` を作成します。
    init(from toolCall: ToolCall) {
        let jsonObject = toolCall.function.arguments.mapValues { $0.anyValue }
        let jsonData = (try? JSONSerialization.data(withJSONObject: jsonObject)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        self.init(name: toolCall.function.name, argumentsJSON: jsonString)
    }
}
