import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocal

@Suite("LLMLocalService - Tool Calling")
struct LLMLocalServiceToolTests {

    // MARK: - Test Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMLocalServiceToolTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func sampleSpec() -> ModelSpec {
        ModelSpec(
            id: "test-model-2b",
            base: .huggingFace(id: "mlx-community/test-model-2b"),
            contextLength: 4096,
            displayName: "Test Model 2B",
            description: "Test model"
        )
    }

    private static let sampleTools: [ToolDefinition] = [
        ToolDefinition(
            name: "get_weather",
            description: "Get the current weather",
            inputSchema: .object(
                properties: [
                    "location": .string(description: "The city name"),
                    "unit": .string(description: "Temperature unit"),
                ],
                required: ["location"]
            )
        )
    ]

    // MARK: - Text-only response

    @Test("returns text-only output when model produces no tool calls")
    func textOnlyResponse() async throws {
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        var outputs: [GenerationOutput] = []
        let stream = await service.generateWithTools(
            model: Self.sampleSpec(),
            prompt: "Hello",
            tools: Self.sampleTools
        )
        for try await output in stream {
            outputs.append(output)
        }

        #expect(outputs.count == 3)
        for output in outputs {
            guard case .text = output else {
                Issue.record("Expected .text but got \(output)")
                return
            }
        }
    }

    // MARK: - Tool call response

    @Test("returns tool call output when model produces a tool call")
    func toolCallResponse() async throws {
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockBackend()
        let toolCall = ToolCall(
            id: "test-id",
            name: "get_weather",
            arguments: Data("{\"location\":\"Tokyo\"}".utf8)
        )
        await backend.setMockToolOutputs([
            .text("Let me check"),
            .toolCall(toolCall),
        ])
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        var outputs: [GenerationOutput] = []
        let stream = await service.generateWithTools(
            model: Self.sampleSpec(),
            prompt: "Weather in Tokyo?",
            tools: Self.sampleTools
        )
        for try await output in stream {
            outputs.append(output)
        }

        #expect(outputs.count == 2)
        guard case .text(let text) = outputs[0] else {
            Issue.record("Expected .text")
            return
        }
        #expect(text == "Let me check")
        guard case .toolCall(let call) = outputs[1] else {
            Issue.record("Expected .toolCall")
            return
        }
        #expect(call.name == "get_weather")
        #expect(String(data: call.arguments, encoding: .utf8) == "{\"location\":\"Tokyo\"}")
    }

    // MARK: - Tool definitions passed to backend

    @Test("passes tool definitions to backend")
    func toolDefinitionsPassedToBackend() async throws {
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        let stream = await service.generateWithTools(
            model: Self.sampleSpec(),
            prompt: "Hello",
            tools: Self.sampleTools
        )
        for try await _ in stream {}

        let called = await backend.generateWithToolsCalled
        #expect(called == true)
        let defs = await backend.lastToolDefinitions
        #expect(defs?.count == 1)
        #expect(defs?.first?.name == "get_weather")
    }

    // MARK: - Error propagation

    @Test("propagates backend error")
    func propagatesError() async throws {
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockBackend()
        await backend.setShouldThrow(.loadFailed(modelId: "test", reason: "test error"))
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        let stream = await service.generateWithTools(
            model: Self.sampleSpec(),
            prompt: "Hello",
            tools: Self.sampleTools
        )
        await #expect(throws: LLMLocalError.self) {
            for try await _ in stream {}
        }
    }

    // MARK: - Stats tracking

    @Test("tracks stats counting only text tokens")
    func statsTrackTextTokensOnly() async throws {
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockBackend()
        let toolCall = ToolCall(
            id: "test-id",
            name: "get_weather",
            arguments: Data("{}".utf8)
        )
        await backend.setMockToolOutputs([
            .text("a"),
            .text("b"),
            .toolCall(toolCall),
            .text("c"),
        ])
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        let stream = await service.generateWithTools(
            model: Self.sampleSpec(),
            prompt: "Hello",
            tools: Self.sampleTools
        )
        for try await _ in stream {}

        let stats = await service.lastGenerationStats
        #expect(stats != nil)
        #expect(stats?.tokenCount == 3) // "a", "b", "c" — toolCall not counted
    }
}
