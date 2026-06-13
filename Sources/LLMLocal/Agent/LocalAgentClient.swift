import Foundation
import LLMClient
import LLMTool
import LLMAgentStep
import LLMLocalClient

/// `LLMLocalService` を `AgentCapableClient` に適合させるアダプター
///
/// ローカル LLM をクラウドプロバイダーと同じエージェントセッションで
/// 使用できるようにする。
///
/// `generateFromMessages` API を使用し、チャットテンプレートの
/// 二重適用（double-templating）を回避する。
///
/// `<think>` タグを検出し、既存の thinking パイプライン
/// （`thinkingDelta` → `AgentStep` → `SessionPhaseEvent`）に統合する。
///
/// ## クラウド専用パラメータの扱い
///
/// `cachePolicy` / `reasoningEffort` / `thinkingMode` はローカル推論に対応する
/// 概念がないため受け取って無視します（graceful degradation）。
/// ローカルモデルの思考は `<think>` タグとして出力され、`thinkingMode` に
/// かかわらず thinking パイプラインへ流れます。
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
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        try await generateWithUsage(
            messages: [.user(input.prompt.render())],
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: ModelSpec,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        let outcome = try await runGeneration(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            tools: ToolSet(),
            temperature: temperature,
            maxTokens: maxTokens
        )

        let jsonText = Self.extractJSONPayload(from: outcome.text)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let output = try decoder.decode(T.self, from: Data(jsonText.utf8))

        return GenerationResult(
            result: output,
            usage: outcome.usage,
            model: model.id,
            rawText: outcome.text,
            stopReason: .endTurn
        )
    }

    /// モデル出力から JSON ペイロードを抽出します。
    ///
    /// ローカルモデルは JSON を Markdown コードフェンスで包むことが多いため、
    /// フェンスがあれば内側を取り出します。
    static func extractJSONPayload(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ToolCallableClient

extension LocalAgentClient: ToolCallableClient {
    public func planToolCalls(
        messages: [LLMMessage],
        model: ModelSpec,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> ToolCallResponse {
        let outcome = try await runGeneration(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens
        )

        return ToolCallResponse(
            toolCalls: outcome.toolCalls,
            text: outcome.text.isEmpty ? nil : outcome.text,
            usage: outcome.usage,
            stopReason: outcome.stopReason,
            model: model.id
        )
    }
}

// MARK: - AgentCapableClient

extension LocalAgentClient: AgentCapableClient {
    public func executeAgentStep(
        messages: [LLMMessage],
        model: ModelSpec,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> LLMResponse {
        let outcome = try await runGeneration(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            tools: tools,
            temperature: nil,
            maxTokens: maxTokens
        )
        return outcome.response(model: model)
    }

    public func streamAgentStep(
        messages: [LLMMessage],
        model: ModelSpec,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        makeCancellableStream { continuation in
            Task {
                do {
                    let outcome = try await self.runGeneration(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        temperature: nil,
                        maxTokens: maxTokens,
                        onDelta: { continuation.yield(.delta($0)) }
                    )
                    continuation.yield(.completed(outcome.response(model: model)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Generation Core

extension LocalAgentClient {
    /// 1 回の生成ストリームを消費した結果。
    struct GenerationOutcome {
        var thinkingText = ""
        var textParts: [String] = []
        var toolCalls: [ToolCall] = []
        var usage = TokenUsage(inputTokens: 0, outputTokens: 0)

        var text: String { textParts.joined() }

        var stopReason: LLMResponse.StopReason {
            toolCalls.isEmpty ? .endTurn : .toolUse
        }

        func response(model: ModelSpec) -> LLMResponse {
            var contentBlocks: [LLMResponse.ContentBlock] = []
            if !thinkingText.isEmpty {
                contentBlocks.append(.thinking(text: thinkingText, signature: nil))
            }
            if !text.isEmpty {
                contentBlocks.append(.text(text))
            }
            for call in toolCalls {
                contentBlocks.append(.toolUse(id: call.id, name: call.name, input: call.arguments))
            }
            return LLMResponse(
                content: contentBlocks,
                model: model.id,
                usage: usage,
                stopReason: stopReason
            )
        }
    }

    /// 全 conformance が共有する生成コア。
    ///
    /// サービスの生成ストリームを消費し、`<think>` タグを thinking として分離、
    /// ツールコールと実測トークン数を収集します。
    /// `onDelta` を渡すとテキスト/思考の差分をリアルタイムに通知します。
    private func runGeneration(
        messages: [LLMMessage],
        model: ModelSpec,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        temperature: Double?,
        maxTokens: Int?,
        onDelta: (@Sendable (StreamDelta) -> Void)? = nil
    ) async throws -> GenerationOutcome {
        // モデルの推奨生成設定（サンプリング・KV・思考モード）を基準に、
        // 呼び出し側が明示した maxTokens / temperature だけを上書きする。
        var config = model.recommendedGeneration
        config.maxTokens = maxTokens
        if let temperature { config.temperature = Float(temperature) }

        var parser = ThinkTagParser()
        var outcome = GenerationOutcome()

        func consume(_ chunk: ThinkTagParser.ParsedChunk) {
            switch chunk {
            case .thinking(let text):
                outcome.thinkingText += text
                onDelta?(.thinkingDelta(text))
            case .text(let text):
                outcome.textParts.append(text)
                onDelta?(.textDelta(text))
            }
        }

        let stream = await service.generateFromMessages(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt?.render(),
            config: config,
            tools: tools.isEmpty ? [] : tools.definitions
        )
        for try await output in stream {
            switch output {
            case .text(let token):
                for chunk in parser.process(token) { consume(chunk) }
            case .toolCall(let call):
                outcome.toolCalls.append(call)
            case .info(let info):
                outcome.usage = TokenUsage(
                    inputTokens: info.promptTokenCount,
                    outputTokens: info.generationTokenCount
                )
            }
        }
        for chunk in parser.finalize() { consume(chunk) }

        return outcome
    }
}
