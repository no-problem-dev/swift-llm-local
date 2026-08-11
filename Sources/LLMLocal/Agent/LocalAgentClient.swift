import Foundation
import LLMClient
import LLMTool
import LLMAgentStep
import LLMLocalClient

/// Adapter that lets on-device inference drive the same agent session as a hosted provider.
///
/// Requests go through the message-array API of the service, so the chat template is applied
/// exactly once — rendering a prompt first and handing the string to the conversational API would
/// apply it a second time. Reasoning from a local model arrives inline as `<think>` text rather
/// than in a separate field, so it is detected here and routed into the existing thinking pipeline
/// (`thinkingDelta` → `AgentStep` → `SessionPhaseEvent`).
///
/// ## What is different from a cloud client
///
/// Nothing leaves the device, nothing is billed per token, and no rate limit exists, so there is no
/// retry budget to manage, no `Retry-After` to honour, and no prompt caching to negotiate with a
/// server. The limits are the device's: weights occupy RAM while loaded, throughput is whatever the
/// chip sustains, and time to first token includes loading the model when it is cold.
///
/// Prompt cache policy, reasoning effort, and thinking mode are accepted and ignored — they have no
/// on-device counterpart. Whether the model thinks is decided by its own recommended generation
/// settings, not by the thinking mode argument, and any thinking it does emit reaches the pipeline
/// regardless.
///
/// Tool calling depends entirely on the model: the tools are rendered into the prompt by its chat
/// template and the calls are recovered by parsing its text output, so a small quantized model is
/// considerably less dependable at it than a hosted provider's function calling. A model whose
/// profile declares no tool-call support fails the request instead of silently dropping the tools.
public final class LocalAgentClient: Sendable {
    private let service: LLMLocalService

    public init(service: LLMLocalService) {
        self.service = service
    }
}

// MARK: - StructuredLLMClient

extension LocalAgentClient: StructuredLLMClient {
    public typealias Model = ModelSpec

    /// Generates a typed structured response from a single prompt.
    ///
    /// The prompt becomes one user message and is handed to the chat-history overload, so
    /// everything documented there applies, including the code-fence stripping local models make
    /// necessary.
    ///
    /// - Parameters:
    ///   - input: Input carrying the prompt to render.
    ///   - model: Model to generate with.
    ///   - systemPrompt: System prompt, or `nil` to send none.
    ///   - temperature: Sampling temperature; `nil` keeps the model's recommended value.
    ///   - maxTokens: Generation limit; `nil` means generate until the model stops or the context
    ///     runs out.
    /// - Returns: The decoded value with the token counts measured on this device.
    /// - Throws: A model load or download failure, or a decoding failure when the output is not
    ///   valid JSON for `T`.
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

    /// Generates a typed structured response from a chat history.
    ///
    /// There is no server-side JSON mode here and no constrained decoding: the model is asked in
    /// the prompt and its raw text is decoded, so malformed output surfaces as a decoding error
    /// rather than being repaired. Local models routinely wrap JSON in a Markdown code fence, which
    /// is stripped before decoding, and keys are decoded from snake case.
    ///
    /// The stop reason is reported as end-of-turn whatever actually happened, so a response
    /// truncated at the token limit is indistinguishable from a complete one here.
    ///
    /// - Parameters:
    ///   - messages: Chat history, oldest first.
    ///   - model: Model to generate with.
    ///   - systemPrompt: System prompt, or `nil` to send none.
    ///   - temperature: Sampling temperature; `nil` keeps the model's recommended value.
    ///   - maxTokens: Generation limit; `nil` means generate until the model stops or the context
    ///     runs out.
    /// - Returns: The decoded value with the token counts measured on this device.
    /// - Throws: A model load or download failure, or a decoding failure when the output is not
    ///   valid JSON for `T`.
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

    /// Extracts the JSON payload from model output, unwrapping a Markdown code fence when present.
    ///
    /// Only the outer fence is removed: the first line goes unconditionally, and the last line goes
    /// when it is a closing fence. Text that does not start with a fence is returned trimmed and
    /// otherwise untouched.
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
    /// Offers the model a set of tools and returns the calls it planned, or text if it chose none.
    ///
    /// Tool calling here is template-and-parser driven: the definitions are rendered into the
    /// prompt by the model's chat template, and calls are recovered by parsing the generated text.
    /// Small quantized models skip calls and produce arguments that do not match the schema far
    /// more often than a hosted provider does, and a model family whose output format has no parser
    /// in this stack cannot report calls at all, however willingly it emits them.
    ///
    /// The tool choice hint has no on-device equivalent and is ignored, so a tool cannot be forced;
    /// the cache policy is ignored because there is no server-side cache to address.
    ///
    /// - Parameters:
    ///   - messages: Chat history, oldest first.
    ///   - model: Model to generate with.
    ///   - tools: Tool definitions offered to the model.
    ///   - toolChoice: Ignored on-device.
    ///   - systemPrompt: System prompt, or `nil` to send none.
    ///   - temperature: Sampling temperature; `nil` keeps the model's recommended value.
    ///   - maxTokens: Generation limit; `nil` means generate until the model stops or the context
    ///     runs out.
    ///   - cachePolicy: Ignored on-device.
    /// - Returns: Planned tool calls plus any text. The stop reason is inferred locally — tool-use
    ///   when calls were parsed, end-of-turn otherwise — not reported by the model.
    /// - Throws: `LLMLocalError.toolCallsUnsupported(modelId:)` when the model's profile declares
    ///   no tool-call support.
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
    /// Runs one agent step to completion and returns the whole response.
    ///
    /// Reasoning arrives inline as `<think>` text and is split into a thinking block. Token counts
    /// are the backend's measured counters and describe work this device did; nothing here is
    /// billed or metered against a quota. If the model is not resident, the step also pays for
    /// loading it, and downloading it when it has never been used.
    ///
    /// The response schema, thinking mode, reasoning effort, and cache policy arguments have no
    /// on-device counterpart and are ignored — the model's own recommended settings decide whether
    /// it thinks, and structured output is a matter of prompting rather than a decoding constraint.
    ///
    /// - Parameters:
    ///   - messages: Chat history, oldest first.
    ///   - model: Model to generate with.
    ///   - systemPrompt: System prompt, or `nil` to send none.
    ///   - tools: Tool definitions offered to the model.
    ///   - toolChoice: Ignored on-device.
    ///   - responseSchema: Ignored on-device.
    ///   - thinkingMode: Ignored on-device.
    ///   - reasoningEffort: Ignored on-device.
    ///   - maxTokens: Generation limit; `nil` means generate until the model stops or the context
    ///     runs out.
    ///   - cachePolicy: Ignored on-device.
    /// - Returns: A response carrying thinking, text, and tool-use blocks in that order.
    /// - Throws: A model load or download failure, or
    ///   `LLMLocalError.toolCallsUnsupported(modelId:)` when tools are offered to a model that
    ///   cannot call them.
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

    /// Runs one agent step and delivers text and reasoning as the model produces them.
    ///
    /// Text arrives as text deltas and reasoning as thinking deltas, separated from the model's
    /// inline `<think>` tags across chunk boundaries; a final completed event carries the assembled
    /// response and closes the stream. There is no server-sent event transport to lose events on —
    /// the deltas come straight from the generation loop on this device.
    ///
    /// Tool calls are not streamed piecewise: the backend surfaces each one only after it has
    /// parsed it whole, so there is no partial-argument accumulation to handle as there is with
    /// hosted providers. Time to the first delta includes loading the model, and downloading it,
    /// when it is not already resident.
    ///
    /// The response schema, thinking mode, reasoning effort, and cache policy arguments are ignored.
    ///
    /// - Parameters:
    ///   - messages: Chat history, oldest first.
    ///   - model: Model to generate with.
    ///   - systemPrompt: System prompt, or `nil` to send none.
    ///   - tools: Tool definitions offered to the model.
    ///   - toolChoice: Ignored on-device.
    ///   - responseSchema: Ignored on-device.
    ///   - thinkingMode: Ignored on-device.
    ///   - reasoningEffort: Ignored on-device.
    ///   - maxTokens: Generation limit; `nil` means generate until the model stops or the context
    ///     runs out.
    ///   - cachePolicy: Ignored on-device.
    /// - Returns: A stream of deltas ending in a completed event. Failures during loading or
    ///   generation finish the stream with the error.
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
    /// Everything collected while one generation stream was consumed.
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

    /// Generation core shared by every conformance on this type.
    ///
    /// Settings start from the model's own recommendation — sampling, KV cache, and thinking mode
    /// tuned per family — and the caller overrides at most two of them. The token limit is taken
    /// from the argument in every case, so passing `nil` means generate until the model stops or
    /// the context runs out; temperature is left at the model's recommended value unless one is
    /// supplied.
    ///
    /// The stream is consumed as it arrives: `<think>` spans are separated into thinking, text is
    /// accumulated, tool calls are collected whole, and the backend's measured prompt and
    /// generation token counts become the usage figures. Supplying a delta handler reports text and
    /// thinking while they are produced rather than only at the end.
    private func runGeneration(
        messages: [LLMMessage],
        model: ModelSpec,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        temperature: Double?,
        maxTokens: Int?,
        onDelta: (@Sendable (StreamDelta) -> Void)? = nil
    ) async throws -> GenerationOutcome {
        // Start from the model's recommended settings (sampling, KV cache, thinking mode) and let
        // the caller override only the token limit and the temperature.
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
