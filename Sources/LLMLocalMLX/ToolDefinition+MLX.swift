import LLMTool
import LLMClient
import Foundation
import LLMLocalClient
import MLXLMCommon

extension ToolDefinition {
    /// Renders this tool into the OpenAI-shaped dictionary the chat template expects.
    ///
    /// MLX does not send tools over a wire protocol: the dictionary is passed to the model's own
    /// Jinja chat template, which writes the tools into the prompt in whatever syntax that model
    /// family was trained on. Whether the schema survives that rendering intact — nested objects,
    /// enums, constraints — is up to the template, and there is no error if it drops something.
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
    /// Flattens the schema into nested dictionaries, recursing through properties and items.
    ///
    /// Only keys that are set are emitted, so the rendered prompt stays as small as the schema
    /// allows — prompt tokens are the scarce resource on device.
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
        if let exclusiveMinimum { dict["exclusiveMinimum"] = exclusiveMinimum }
        if let exclusiveMaximum { dict["exclusiveMaximum"] = exclusiveMaximum }
        if let minLength { dict["minLength"] = minLength }
        if let maxLength { dict["maxLength"] = maxLength }
        if let pattern { dict["pattern"] = pattern }
        if let format { dict["format"] = format }
        if let `enum` { dict["enum"] = `enum` }

        return dict
    }
}

// MARK: - MLX ToolCall → LLMTool.ToolCall

extension LLMTool.ToolCall {
    /// Builds a canonical tool call from what MLX parsed out of the model's text.
    ///
    /// The model emits a tool call as text, and MLX's parser for that model family turns it into
    /// a name and typed arguments; those arguments are re-serialized here into the JSON payload
    /// the rest of the stack expects. Nothing validates them against the tool's schema, so a model
    /// that hallucinates an argument name produces a well-formed call that fails at execution.
    ///
    /// There is no provider-assigned identifier on device — unlike Anthropic or OpenAI, nothing
    /// upstream mints one — so a fresh UUID is generated. The caller must echo that same id back
    /// on the tool result for the result to be matched to this call in the next prompt.
    init(from mlxToolCall: MLXLMCommon.ToolCall) {
        let jsonObject = mlxToolCall.function.arguments.mapValues { $0.anyValue }
        let jsonData = (try? JSONSerialization.data(withJSONObject: jsonObject)) ?? Data()
        self.init(id: UUID().uuidString, name: mlxToolCall.function.name, arguments: jsonData)
    }
}
