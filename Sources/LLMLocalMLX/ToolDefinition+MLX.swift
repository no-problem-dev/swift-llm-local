import Foundation
import LLMLocalClient
import MLXLMCommon

extension ToolDefinition {
    /// このツール定義を MLX 互換の ``ToolSpec`` ディクショナリに変換します。
    var toolSpec: [String: any Sendable] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": inputSchema.toDictionary(),
            ] as [String: any Sendable],
        ]
    }
}

// MARK: - JSONSchema → Dictionary

extension JSONSchema {
    /// JSONSchema を再帰的に `[String: any Sendable]` に変換します。
    func toDictionary() -> [String: any Sendable] {
        var dict: [String: any Sendable] = ["type": type.rawValue]

        if let description { dict["description"] = description }

        if let properties {
            var propsDict: [String: any Sendable] = [:]
            for (key, value) in properties {
                propsDict[key] = value.toDictionary()
            }
            dict["properties"] = propsDict
        }

        if let required { dict["required"] = required }

        if let items { dict["items"] = items.value.toDictionary() }

        if let additionalProperties { dict["additionalProperties"] = additionalProperties }
        if let minItems { dict["minItems"] = minItems }
        if let maxItems { dict["maxItems"] = maxItems }
        if let minimum { dict["minimum"] = minimum }
        if let maximum { dict["maximum"] = maximum }
        if let `enum` { dict["enum"] = `enum` }

        return dict
    }
}

// MARK: - MLX ToolCall → LLMTool.ToolCall

extension LLMTool.ToolCall {
    /// MLX の ``MLXLMCommon.ToolCall`` から ``LLMTool.ToolCall`` を作成します。
    init(from mlxToolCall: MLXLMCommon.ToolCall) {
        let jsonObject = mlxToolCall.function.arguments.mapValues { $0.anyValue }
        let jsonData = (try? JSONSerialization.data(withJSONObject: jsonObject)) ?? Data()
        self.init(id: UUID().uuidString, name: mlxToolCall.function.name, arguments: jsonData)
    }
}
