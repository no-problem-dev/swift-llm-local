import Foundation
import Testing
import LLMClient
import LLMTool
import LLMLocalClient
import LLMAgentStep
@testable import LLMLocal

// MARK: - Test Fixtures

@Structured("テスト用の挨拶")
struct TestGreeting {
    @StructuredField("挨拶文")
    var message: String
}

private struct WeatherTool: Tool {
    var toolName: String { "get_weather" }
    var toolDescription: String { "Get the current weather" }
    var inputSchema: JSONSchema {
        .object(
            properties: ["location": .string(description: "The city name")],
            required: ["location"]
        )
    }

    func execute(with argumentsData: Data) async throws -> ToolResult {
        .text("sunny")
    }
}

// MARK: - Generic Dispatch Helpers
//
// These helpers force every LocalAgentClient call through a protocol-constrained generic.
// Calling the concrete type directly would hide a signature mismatch, because nothing would
// check that the concrete method actually satisfies the protocol requirement. When the witness
// is missing, the call silently resolves to the protocol extension default, where
// generateWithUsage recurses forever and streamAgentStep emits no deltas.

private func generateStructured<C: StructuredLLMClient, T: StructuredProtocol>(
    _ client: C,
    messages: [LLMMessage],
    model: C.Model,
    temperature: Double? = nil,
    maxTokens: Int? = nil
) async throws -> GenerationResult<T> {
    try await client.generateWithUsage(
        messages: messages,
        model: model,
        systemPrompt: nil,
        temperature: temperature,
        maxTokens: maxTokens
    )
}

private func planViaProtocol<C: ToolCallableClient>(
    _ client: C,
    messages: [LLMMessage],
    model: C.Model,
    tools: ToolSet,
    temperature: Double? = nil
) async throws -> ToolCallResponse {
    try await client.planToolCalls(
        messages: messages,
        model: model,
        tools: tools,
        toolChoice: nil,
        systemPrompt: nil,
        temperature: temperature,
        maxTokens: nil,
        cachePolicy: .implicit
    )
}

private func executeViaProtocol<C: AgentCapableClient>(
    _ client: C,
    messages: [LLMMessage],
    model: C.Model,
    tools: ToolSet,
    systemPrompt: SystemPrompt? = nil,
    maxTokens: Int? = nil
) async throws -> LLMResponse {
    try await client.executeAgentStep(
        messages: messages,
        model: model,
        systemPrompt: systemPrompt,
        tools: tools,
        toolChoice: nil,
        responseSchema: nil,
        thinkingMode: .disabled,
        reasoningEffort: nil,
        maxTokens: maxTokens,
        cachePolicy: .implicit
    )
}

private func streamViaProtocol<C: AgentCapableClient>(
    _ client: C,
    messages: [LLMMessage],
    model: C.Model,
    tools: ToolSet
) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
    client.streamAgentStep(
        messages: messages,
        model: model,
        systemPrompt: nil,
        tools: tools,
        toolChoice: nil,
        responseSchema: nil,
        thinkingMode: .disabled,
        reasoningEffort: nil,
        maxTokens: nil,
        cachePolicy: .implicit
    )
}

// MARK: - Tests

@Suite("LocalAgentClient", .timeLimit(.minutes(1)))
struct LocalAgentClientTests {

    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalAgentClientTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func makeClient(
        backend: MockBackend,
        cacheDirectory: URL
    ) throws -> LocalAgentClient {
        let registry = try ModelRegistry(cacheDirectory: cacheDirectory)
        let service = try LLMLocalService(backend: backend, modelRegistry: registry)
        return LocalAgentClient(service: service)
    }

    private static func spec(toolCallSupport: ToolCallSupport?) -> ModelSpec {
        ModelSpec(
            id: "test-model",
            base: .huggingFace(id: "mlx-community/test-model"),
            contextLength: 4096,
            displayName: "Test Model",
            description: "Test model",
            estimatedMemoryBytes: 1_000_000_000,
            profile: toolCallSupport.map {
                ModelProfile(
                    summary: "test",
                    modelFamily: "Test",
                    toolCallSupport: $0,
                    japaneseSupport: .basic,
                    modalities: [.text]
                )
            }
        )
    }

    private static let tools = ToolSet { WeatherTool() }

    private static let sampleToolCall = ToolCall(
        id: "call-1",
        name: "get_weather",
        arguments: Data(#"{"location":"Tokyo"}"#.utf8)
    )

    private static let sampleInfo = GenerationInfo(
        promptTokenCount: 120,
        generationTokenCount: 45,
        tokensPerSecond: 30
    )

    // MARK: - StructuredLLMClient (a missing witness recurses forever, so these time out)

    @Test("generateWithUsage はプロトコル経由で witness にディスパッチされ JSON をデコードする")
    func structuredDispatch() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        await backend.setMockToolOutputs([
            .text(#"{"message":"hi"}"#),
            .info(Self.sampleInfo),
        ])
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        let result: GenerationResult<TestGreeting> = try await generateStructured(
            client,
            messages: [.user("greet me")],
            model: Self.spec(toolCallSupport: .excellent)
        )

        #expect(result.result.message == "hi")
        #expect(result.usage.inputTokens == 120)
        #expect(result.usage.outputTokens == 45)
    }

    @Test("Markdown コードフェンス付き JSON もデコードできる")
    func structuredDecodesFencedJSON() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        await backend.setMockToolOutputs([
            .text("```json\n"),
            .text(#"{"message":"fenced"}"#),
            .text("\n```"),
        ])
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        let result: GenerationResult<TestGreeting> = try await generateStructured(
            client,
            messages: [.user("greet me")],
            model: Self.spec(toolCallSupport: .excellent)
        )

        #expect(result.result.message == "fenced")
    }

    // MARK: - ToolCallableClient

    @Test("planToolCalls はツールコールと実測 usage を返す")
    func planToolCallsDispatch() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        await backend.setMockToolOutputs([
            .text("checking"),
            .toolCall(Self.sampleToolCall),
            .info(Self.sampleInfo),
        ])
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        let response = try await planViaProtocol(
            client,
            messages: [.user("weather?")],
            model: Self.spec(toolCallSupport: .excellent),
            tools: Self.tools
        )

        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls.first?.name == "get_weather")
        #expect(response.text == "checking")
        #expect(response.usage.inputTokens == 120)
        #expect(response.usage.outputTokens == 45)
    }

    @Test("planToolCalls の temperature が GenerationConfig に貫通する")
    func temperaturePassthrough() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        _ = try await planViaProtocol(
            client,
            messages: [.user("hi")],
            model: Self.spec(toolCallSupport: .excellent),
            tools: Self.tools,
            temperature: 0.2
        )

        let config = await backend.lastConfig
        #expect(config?.temperature == 0.2)
    }

    // MARK: - AgentCapableClient

    @Test("executeAgentStep は thinking/text/toolUse ブロックを組み立てる")
    func executeAgentStepBlocks() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        await backend.setMockToolOutputs([
            .text("<think>planning</think>"),
            .text("Answer"),
            .toolCall(Self.sampleToolCall),
            .info(Self.sampleInfo),
        ])
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        let response = try await executeViaProtocol(
            client,
            messages: [.user("weather?")],
            model: Self.spec(toolCallSupport: .excellent),
            tools: Self.tools
        )

        #expect(response.content.count == 3)
        guard case .thinking(let thinking, _) = response.content[0] else {
            Issue.record("Expected .thinking but got \(response.content[0])")
            return
        }
        #expect(thinking == "planning")
        guard case .text(let text) = response.content[1] else {
            Issue.record("Expected .text but got \(response.content[1])")
            return
        }
        #expect(text == "Answer")
        guard case .toolUse(_, let name, _) = response.content[2] else {
            Issue.record("Expected .toolUse but got \(response.content[2])")
            return
        }
        #expect(name == "get_weather")
        #expect(response.stopReason == .toolUse)
        #expect(response.usage.inputTokens == 120)
    }

    @Test("executeAgentStep の maxTokens と systemPrompt がバックエンドに貫通する")
    func maxTokensAndSystemPromptPassthrough() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        _ = try await executeViaProtocol(
            client,
            messages: [.user("hi")],
            model: Self.spec(toolCallSupport: .excellent),
            tools: Self.tools,
            systemPrompt: "You are a helpful assistant",
            maxTokens: 512
        )

        let config = await backend.lastConfig
        #expect(config?.maxTokens == 512)
        let systemPrompt = await backend.lastSystemPrompt
        #expect(systemPrompt?.contains("helpful assistant") == true)
    }

    @Test("maxTokens 未指定はバックエンドに nil（コンテキスト上限まで）として渡る")
    func maxTokensNilPassthrough() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        _ = try await executeViaProtocol(
            client,
            messages: [.user("hi")],
            model: Self.spec(toolCallSupport: .excellent),
            tools: Self.tools
        )

        let config = await backend.lastConfig
        #expect(config?.maxTokens == nil)
    }

    @Test("streamAgentStep はローカル witness が使われ delta が流れる")
    func streamAgentStepEmitsDeltas() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        await backend.setMockToolOutputs([
            .text("<think>plan</think>"),
            .text("Answer"),
            .info(Self.sampleInfo),
        ])
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        var thinkingDeltas: [String] = []
        var textDeltas: [String] = []
        var completed: LLMResponse?
        let stream = streamViaProtocol(
            client,
            messages: [.user("hi")],
            model: Self.spec(toolCallSupport: .excellent),
            tools: Self.tools
        )
        for try await event in stream {
            switch event {
            case .delta(.thinkingDelta(let text)):
                thinkingDeltas.append(text)
            case .delta(.textDelta(let text)):
                textDeltas.append(text)
            case .completed(let response):
                completed = response
            default:
                break
            }
        }

        // If dispatch falls back to the protocol extension default, which just wraps the
        // non-streaming call, no delta is emitted at all. This is where a witness regression
        // surfaces.
        #expect(!thinkingDeltas.isEmpty)
        #expect(!textDeltas.isEmpty)
        #expect(completed != nil)
        #expect(completed?.usage.inputTokens == 120)
    }

    // MARK: - Tool Call Capability Guard

    @Test("toolCallSupport == .unsupported のモデルにツールを渡すと throw する")
    func unsupportedModelThrows() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        await #expect(throws: LLMLocalError.toolCallsUnsupported(modelId: "test-model")) {
            _ = try await executeViaProtocol(
                client,
                messages: [.user("hi")],
                model: Self.spec(toolCallSupport: .unsupported),
                tools: Self.tools
            )
        }
    }

    @Test("toolCallSupport == .unsupported でもツールなしなら生成できる")
    func unsupportedModelWithoutToolsSucceeds() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        await backend.setMockToolOutputs([.text("plain answer")])
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        let response = try await executeViaProtocol(
            client,
            messages: [.user("hi")],
            model: Self.spec(toolCallSupport: .unsupported),
            tools: ToolSet()
        )

        #expect(response.text == "plain answer")
        #expect(response.stopReason == .endTurn)
    }

    @Test("プロファイル未設定のモデルはツール対応未知として許容する")
    func noProfileModelAllowed() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend()
        await backend.setMockToolOutputs([.toolCall(Self.sampleToolCall)])
        let client = try Self.makeClient(backend: backend, cacheDirectory: dir)

        let response = try await planViaProtocol(
            client,
            messages: [.user("hi")],
            model: Self.spec(toolCallSupport: nil),
            tools: Self.tools
        )

        #expect(response.toolCalls.count == 1)
    }

    // MARK: - JSON Payload Extraction

    @Test("extractJSONPayload はフェンスなし・言語タグ付き・タグなしフェンスを処理する")
    func extractJSONPayloadVariants() throws {
        #expect(LocalAgentClient.extractJSONPayload(from: #"{"a":1}"#) == #"{"a":1}"#)
        #expect(
            LocalAgentClient.extractJSONPayload(from: "```json\n{\"a\":1}\n```") == #"{"a":1}"#
        )
        #expect(
            LocalAgentClient.extractJSONPayload(from: "```\n{\"a\":1}\n```") == #"{"a":1}"#
        )
        #expect(
            LocalAgentClient.extractJSONPayload(from: "  {\"a\":1}\n") == #"{"a":1}"#
        )
    }
}
