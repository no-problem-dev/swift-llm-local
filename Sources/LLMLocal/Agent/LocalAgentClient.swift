import Foundation
import LLMClient
import LLMTool
import LLMLocalClient

/// `LLMLocalService` を `AgentCapableClient` に適合させるアダプター
///
/// ローカル LLM をクラウドプロバイダーと同じエージェントセッションで
/// 使用できるようにする。
///
/// `generateFromMessages` API を使用し、チャットテンプレートの
/// 二重適用（double-templating）を回避する。
public final class LocalAgentClient: Sendable {
    private let service: LLMLocalService

    public init(service: LLMLocalService) {
        self.service = service
    }
}

// MARK: - StructuredLLMClient

extension LocalAgentClient: StructuredLLMClient {
    public typealias Model = ModelSpec

    public func generateWithUsage<T: StructuredProtocol>(
        input: LLMInput,
        model: ModelSpec,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        let messages: [LLMMessage] = [.user(input.prompt.render())]
        return try await generateWithUsage(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: ModelSpec,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        let config = GenerationConfig(
            maxTokens: maxTokens ?? 1024,
            temperature: Float(temperature ?? 0.7)
        )

        var fullText = ""
        let stream = await service.generateFromMessages(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt,
            config: config
        )
        for try await output in stream {
            if case .text(let token) = output {
                fullText += token
            }
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let output = try decoder.decode(T.self, from: Data(fullText.utf8))

        return GenerationResult(
            result: output,
            usage: TokenUsage(inputTokens: 0, outputTokens: 0),
            model: model.id,
            rawText: fullText,
            stopReason: .endTurn
        )
    }
}

// MARK: - ToolCallableClient

extension LocalAgentClient: ToolCallableClient {
    public func planToolCalls(
        messages: [LLMMessage],
        model: ModelSpec,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ToolCallResponse {
        let response = try await executeAgentStep(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt.map { Prompt(stringLiteral: $0) },
            tools: tools,
            toolChoice: toolChoice,
            responseSchema: nil,
            maxTokens: maxTokens
        )

        let calls = response.content.compactMap { block -> ToolCall? in
            guard case .toolUse(let id, let name, let input) = block else { return nil }
            return ToolCall(id: id, name: name, arguments: input)
        }

        return ToolCallResponse(
            toolCalls: calls,
            text: response.text.isEmpty ? nil : response.text,
            usage: response.usage,
            stopReason: response.stopReason,
            model: response.model
        )
    }
}

// MARK: - AgentCapableClient

extension LocalAgentClient: AgentCapableClient {
    public func executeAgentStep(
        messages: [LLMMessage],
        model: ModelSpec,
        systemPrompt: Prompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        maxTokens: Int?
    ) async throws -> LLMResponse {
        let config = GenerationConfig(maxTokens: 1024, temperature: 0.7)
        let toolDefs = tools.isEmpty ? [] : tools.definitions

        var textParts: [String] = []
        var toolCalls: [ToolCall] = []

        let stream = await service.generateFromMessages(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt?.render(),
            config: config,
            tools: toolDefs
        )
        for try await output in stream {
            switch output {
            case .text(let token):
                textParts.append(token)
            case .toolCall(let call):
                toolCalls.append(call)
            }
        }

        var contentBlocks: [LLMResponse.ContentBlock] = []

        let fullText = textParts.joined()
        if !fullText.isEmpty {
            contentBlocks.append(.text(fullText))
        }

        for call in toolCalls {
            contentBlocks.append(.toolUse(id: call.id, name: call.name, input: call.arguments))
        }

        let stopReason: LLMResponse.StopReason = toolCalls.isEmpty ? .endTurn : .toolUse

        return LLMResponse(
            content: contentBlocks,
            model: model.id,
            usage: TokenUsage(inputTokens: 0, outputTokens: 0),
            stopReason: stopReason
        )
    }
}
