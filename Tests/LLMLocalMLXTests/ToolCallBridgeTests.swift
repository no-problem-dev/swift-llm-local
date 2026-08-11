import Testing
import Foundation
import LLMTool
import MLXLMCommon
@testable import LLMLocalMLX

/// Covers the MLX → canonical tool call bridge in `ToolDefinition+MLX.swift`.
///
/// The bridge re-serializes MLX's typed arguments into the JSON payload the rest of the stack
/// decodes. Its contract is that `arguments` is always a valid JSON object — an empty `Data`
/// would decode as "not valid JSON" and be blamed on the model. These tests pin that for every
/// shape `MLXLMCommon.JSONValue` can take, which is the whole of what MLX can hand over.
@Suite("MLX ToolCall → LLMTool.ToolCall")
struct ToolCallBridgeTests {

    private func mlxCall(
        name: String = "search",
        _ arguments: [String: MLXLMCommon.JSONValue]
    ) -> MLXLMCommon.ToolCall {
        MLXLMCommon.ToolCall(function: .init(name: name, arguments: arguments))
    }

    @Test("A call with no arguments carries an empty JSON object, never empty bytes")
    func noArgumentsIsEmptyObject() throws {
        let call = LLMTool.ToolCall(from: mlxCall([:]))

        #expect(!call.arguments.isEmpty, "empty Data is not valid JSON and would fail to decode")
        #expect(String(decoding: call.arguments, as: UTF8.self) == "{}")
    }

    @Test("Every JSONValue leaf survives the round trip")
    func everyLeafRoundTrips() throws {
        let arguments: [String: MLXLMCommon.JSONValue] = [
            "text": .string("hello"),
            "count": .int(7),
            // Deliberately not a whole number: JSON has one number type, so 3.0 would come back
            // as an int and the comparison below would fail for a reason that is not a defect.
            "ratio": .double(2.5),
            "flag": .bool(true),
            "missing": .null,
        ]

        let call = LLMTool.ToolCall(from: mlxCall(arguments))
        let decoded = try JSONDecoder().decode(
            [String: MLXLMCommon.JSONValue].self, from: call.arguments
        )

        #expect(decoded == arguments)
    }

    @Test("Nested objects and arrays survive the round trip")
    func nestedStructuresRoundTrip() throws {
        let arguments: [String: MLXLMCommon.JSONValue] = [
            "filter": .object([
                "tags": .array([.string("swift"), .string("mlx")]),
                "range": .object(["min": .int(1), "max": .int(10)]),
            ]),
            "ids": .array([.int(1), .int(2), .int(3)]),
            "mixed": .array([.string("a"), .int(1), .bool(false), .null]),
        ]

        let call = LLMTool.ToolCall(from: mlxCall(arguments))
        let decoded = try JSONDecoder().decode(
            [String: MLXLMCommon.JSONValue].self, from: call.arguments
        )

        #expect(decoded == arguments)
    }

    @Test("Argument values a model is likely to get wrong still produce valid JSON")
    func awkwardValuesStillSerialize() throws {
        // Quotes, backslashes, newlines, non-ASCII and an empty key all go through the same
        // serializer. None of them are a reason for the payload to come out unparseable.
        let arguments: [String: MLXLMCommon.JSONValue] = [
            "quoted": .string(#"he said "hi""#),
            "escaped": .string(#"C:\path\to\file"#),
            "multiline": .string("line one\nline two"),
            "unicode": .string("日本語 🎌"),
            "": .string("empty key"),
            "deep": .array([.array([.array([.int(1)])])]),
        ]

        let call = LLMTool.ToolCall(from: mlxCall(arguments))
        let decoded = try JSONDecoder().decode(
            [String: MLXLMCommon.JSONValue].self, from: call.arguments
        )

        #expect(decoded == arguments)
    }

    @Test("The tool name is carried over unchanged")
    func nameIsCarriedOver() {
        let call = LLMTool.ToolCall(from: mlxCall(name: "get_weather", ["city": .string("Tokyo")]))

        #expect(call.name == "get_weather")
    }

    @Test("Each call gets its own identifier")
    func identifiersAreDistinct() {
        let first = LLMTool.ToolCall(from: mlxCall(["q": .string("a")]))
        let second = LLMTool.ToolCall(from: mlxCall(["q": .string("a")]))

        #expect(first.id != second.id)
        #expect(UUID(uuidString: first.id) != nil)
    }
}
