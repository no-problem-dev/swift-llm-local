import LLMClient
import LLMTool

/// Contract an on-device inference engine implements so callers can stay engine-agnostic.
///
/// A conforming type owns the weights, the KV cache, and any conversation state that outlives a
/// single call, which is why the protocol requires `Sendable` — the shipping implementation
/// (`MLXBackend` in `LLMLocalMLX`) is an actor. Everything below is the guarantee an implementer
/// owes its callers, not merely what one backend happens to do.
///
/// ## Load and unload ordering
///
/// A load must complete before any generation starts. Generating with nothing loaded does not trap:
/// the returned stream finishes with ``LLMLocalError/modelNotLoaded``. Loading a spec that is
/// already resident returns immediately without touching the weights, and loading a different spec
/// replaces the current one — the old model is unloaded before the new one is fetched, so a failed
/// load leaves the backend with no model rather than the previous one. Loads are not queued: a
/// second load started while one is in flight fails with ``LLMLocalError/loadInProgress``.
/// Unloading is safe at any time, including when nothing is loaded.
///
/// ## Concurrency
///
/// The protocol does not serialize generation, and the two families of entry points differ in how
/// they behave when calls overlap. `generate` and `generateWithTools` run against one conversation
/// held by the backend, so overlapping calls interleave their turns into that single history — run
/// them one at a time per instance. `generateFromMessages` takes the whole conversation as an
/// argument and holds no history, which makes it the path to use when two conversations share one
/// backend; the MLX backend additionally detects the overlap and gives the second generation a
/// private KV cache so prompt-cache contents cannot leak between conversations.
///
/// ## Cancellation
///
/// Every generation method returns a stream whose producer task is cancelled when the consumer
/// stops iterating or when the surrounding task is cancelled. Implementers surface that as
/// ``LLMLocalError/cancelled`` on the stream rather than letting `CancellationError` escape, so
/// callers only match one error type. Cancelling generation leaves the model loaded.
public protocol LLMLocalBackend: Sendable {
    /// Makes a model resident in memory so that generation can start.
    ///
    /// On first use this may download several gigabytes of weights, so treat it as a long
    /// operation. It returns without work when the same spec is already loaded.
    ///
    /// - Parameter spec: Model to make resident.
    /// - Throws: ``LLMLocalError/loadInProgress`` when another load is running,
    ///   ``LLMLocalError/adapterMergeFailed(reason:)`` when the spec names an adapter that cannot
    ///   be resolved or applied, and ``LLMLocalError/loadFailed(modelId:reason:)`` otherwise.
    func loadModel(_ spec: ModelSpec) async throws

    /// Makes a model resident in memory, reporting progress while its weights are downloaded.
    ///
    /// The handler fires only while bytes are being fetched, so a model already on disk loads
    /// without a single callback. It can run on any task, so hop to the main actor before touching
    /// UI. Backends that do not implement download reporting inherit a default that never calls it.
    ///
    /// - Parameters:
    ///   - spec: Model to make resident.
    ///   - progressHandler: Called on each download progress update.
    /// - Throws: The same errors as ``loadModel(_:)``.
    func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws

    /// Streams the model's answer to a single prompt as text fragments.
    ///
    /// A fragment is whatever the detokenizer could emit at that moment — not necessarily a whole
    /// token, word, or line — so append fragments rather than treating each as a unit. Reasoning
    /// models emit their `<think>…</think>` span inline here; run the fragments through
    /// ``ThinkTagParser`` before showing them to a user. This path carries no token counts, so a
    /// caller that needs measured usage should use `generateWithTools` or `generateFromMessages`.
    ///
    /// Implementations may keep a chat session across calls, in which case successive prompts
    /// accumulate into one conversation until ``resetSession()`` is called.
    ///
    /// - Parameters:
    ///   - prompt: Text sent to the model for this turn.
    ///   - config: Sampling, KV cache, and thinking-mode settings applied to this call.
    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error>

    /// Streams an answer that may also contain tool-call requests.
    ///
    /// Elements are text fragments, tool calls the backend already parsed out of the model's output,
    /// and at most one trailing ``GenerationInfo`` after the last text. Absence of that record means
    /// the backend does not measure tokens, not that generation failed. Like `generate`, this runs
    /// against the backend's conversation state.
    ///
    /// - Parameters:
    ///   - prompt: Text sent to the model for this turn.
    ///   - config: Sampling, KV cache, and thinking-mode settings applied to this call.
    ///   - tools: Tools the model is allowed to call this turn.
    func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error>

    /// Releases the resident model and the memory it holds.
    ///
    /// Conversation state and any prompt (KV) cache go with it, so the next generation prefills from
    /// scratch. Calling it with nothing loaded does nothing.
    func unloadModel() async

    /// Whether a model is resident and ready to generate.
    ///
    /// It is false while a load is still running, so it cannot be used to detect a load in flight.
    var isLoaded: Bool { get async }

    /// Spec of the resident model, or `nil` when none is loaded.
    ///
    /// It only becomes non-`nil` once a load succeeds; because the previous model is unloaded before
    /// a new one is fetched, a failed load leaves this `nil` rather than at the previous spec.
    var currentModel: ModelSpec? { get async }

    /// System prompt applied to generation, or `nil` when none is set.
    ///
    /// Backends that do not implement it inherit a default that always reports `nil`, even after
    /// ``setSystemPrompt(_:)`` was called.
    var systemPrompt: String? { get async }

    /// Sets the system prompt used from now on, including for the conversation already in progress.
    ///
    /// The prompt outlives model swaps and session resets; pass `nil` to clear it. The default
    /// implementation does nothing, so on a backend that does not implement it the prompt is
    /// silently dropped rather than rejected.
    func setSystemPrompt(_ prompt: String?) async

    /// Clears the conversation history while keeping the model loaded.
    ///
    /// The prompt (KV) cache is dropped along with the history, so the next generation pays full
    /// prefill again. The system prompt survives.
    func resetSession() async

    /// Streams an answer from an explicit conversation, applying the chat template exactly once.
    ///
    /// Nothing is remembered between calls — the caller passes the full conversation every time —
    /// which is what makes this the correct path for agent loops and for two conversations sharing
    /// one backend. It also avoids the double templating that happens when a transcript rendered by
    /// a message formatter is handed to `generate(prompt:config:)` and the backend's own chat
    /// template is applied on top.
    ///
    /// Statelessness does not mean the prompt is reprocessed in full: the MLX backend keeps the KV
    /// cache for the prefix this conversation shares with the previous turn and prefills only the
    /// new suffix. The trailing ``GenerationInfo`` still reports the full templated prompt length
    /// rather than the number of tokens actually prefilled, so usage stays comparable across turns.
    ///
    /// - Parameters:
    ///   - messages: Full conversation to send, oldest first.
    ///   - systemPrompt: System prompt prepended as a system message, or `nil` for none.
    ///   - config: Sampling, KV cache, and thinking-mode settings applied to this call.
    ///   - tools: Tools the model is allowed to call this turn.
    func generateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error>
}

// MARK: - System Prompt

extension LLMLocalBackend {
    /// Always `nil`, because a backend without session support stores no system prompt.
    public var systemPrompt: String? { nil }

    /// Discards the prompt on backends that have no session to apply it to.
    ///
    /// The call succeeds, so a caller relying on a system prompt gets a model that never saw it.
    /// Override this wherever the model has a chat template with a system role.
    public func setSystemPrompt(_ prompt: String?) async {}

    /// Does nothing, because a backend without session state has no history to clear.
    public func resetSession() async {}
}

// MARK: - Default Implementation

extension LLMLocalBackend {
    /// Loads without reporting progress, ignoring the handler entirely.
    ///
    /// The handler is never called — not even once at completion — so UI driven by it shows no
    /// movement for the whole download. Override this on any backend that can observe byte counts.
    public func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        try await loadModel(spec)
    }

    /// Wraps plain text generation for backends that cannot call tools.
    ///
    /// A non-empty tool list fails the stream with ``LLMLocalError/toolCallsUnsupported(modelId:)``
    /// instead of being dropped: a tool-free reply looks to an agent loop like the model decided no
    /// tool was needed, and the loop ends its turn on an answer the model could not have produced.
    /// With no tools, each fragment from `generate(prompt:config:)` is forwarded as
    /// ``GenerationOutput/text(_:)`` and no usage record is emitted.
    public func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        guard tools.isEmpty else {
            return makeCancellableStream { continuation in
                Task {
                    let modelId = await currentModel?.id ?? "unknown"
                    continuation.finish(throwing: LLMLocalError.toolCallsUnsupported(modelId: modelId))
                }
            }
        }
        let stream = generate(prompt: prompt, config: config)
        return makeCancellableStream { continuation in
            Task {
                do {
                    for try await token in stream {
                        try Task.checkCancellation()
                        continuation.yield(.text(token))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Flattens the conversation into one newline-joined prompt and delegates to tool generation.
    ///
    /// Only the text parts of each message survive the join: roles, tool calls, tool results, and
    /// attachments are dropped, and the backend then applies its own chat template to the flattened
    /// string. That is acceptable for a single-turn completion backend and wrong for an agent loop,
    /// so any backend whose model has a chat template should override this.
    public func generateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        let prompt = messages.map { $0.content }.joined(separator: "\n")
        return generateWithTools(prompt: prompt, config: config, tools: tools)
    }
}
