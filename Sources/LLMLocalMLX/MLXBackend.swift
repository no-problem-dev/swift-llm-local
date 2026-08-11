import Foundation
import HuggingFace
import LLMClient
import LLMLocalClient
import LLMTool
import MLX
import MLXHuggingFace
import MLXLLM
@preconcurrency import MLXLMCommon
import Tokenizers

/// On-device LLM inference backend built on Apple MLX.
///
/// Wraps the mlx-swift-lm API and conforms to `LLMLocalBackend`. It owns model loading,
/// streaming generation, the MLX GPU buffer cache limit, and optional LoRA/QLoRA adapters.
///
/// ## Memory is the binding constraint
///
/// Inference runs inside this process. Model weights, the KV cache, and MLX's buffer cache
/// all count against the app's memory footprint, and on iOS jetsam terminates the app when
/// that footprint grows too large — that is a process kill, not an error the caller can catch.
/// Three things keep it bounded, and only the first is automatic:
///
/// - the GPU buffer cache limit applied on every load (see ``init(gpuCacheLimit:adapterResolver:downloader:tokenizerLoader:)``),
/// - `GenerationConfig.maxKVSize` / `kvBits`, which bound and quantize the KV cache,
/// - the caller checking ``MemoryMonitor/isModelCompatible(_:)`` before loading.
///
/// This backend never refuses a model for being too large; it will happily load weights
/// that get the app killed on a smaller device.
///
/// ## Model acquisition
///
/// mlx-swift-lm 3.x expects the caller to inject `Downloader` and `TokenizerLoader`. The
/// default downloads from the Hugging Face Hub into an app-owned directory, but a different
/// strategy (S3, an app bundle, a preloaded directory) can be injected instead.
///
/// ## Adapter support
///
/// When `ModelSpec` carries an `AdapterSource`, the backend resolves it to a local URL
/// through an `AdapterResolving` instance and applies it to the loaded model. The adapter
/// is applied as a layer on the loaded weights, not merged into the files on disk.
///
/// ```swift
/// let backend = MLXBackend(adapterResolver: adapterManager)
/// try await backend.loadModel(specWithAdapter)
/// ```
public actor MLXBackend: LLMLocalBackend {

    // MARK: - Internal State

    private var chatSession: ChatSession?
    private var modelContainer: ModelContainer?
    private var loadedSpec: ModelSpec?
    private let gpuCacheLimit: Int
    private let downloader: any Downloader
    private let tokenizerLoader: any TokenizerLoader

    /// Prompt (KV) cache carried across turns of the stateless message-array path.
    ///
    /// The stateless API receives the whole message array every call, so without this the
    /// backend would re-prefill the entire prompt on every turn — the dominant cost of a long
    /// conversation. Instead the token sequence is compared against the previous turn and the
    /// cache for the shared prefix is kept, so only the suffix is prefilled. This is the same
    /// reuse `ChatSession` gets for free from holding its own cache.
    ///
    /// Only sound for a single conversation generating serially. When one backend is shared by
    /// several concurrent conversations (a host and its workers, for example), a generation that
    /// starts while another is running gets a private throwaway cache instead, so KV context
    /// cannot leak between conversations. See ``cacheBusy``.
    private let promptCacheStore = PromptCacheStore()

    /// Whether some generation currently owns the shared prompt cache.
    ///
    /// A generation that starts while this is set runs on its own disposable cache, which costs
    /// a full prefill but keeps one conversation's KV context out of another's.
    private var cacheBusy = false

    private let adapterResolver: (any AdapterResolving)?

    /// The adapter URL resolved by the most recent load, absent when that model had no adapter.
    ///
    /// Exposed so tests can assert that adapter resolution produced the expected URL and that
    /// the URL reached the model loading pipeline.
    private(set) var lastResolvedAdapterURL: URL?

    /// System prompt applied to the chat session, including one that already exists.
    private var _systemPrompt: String?

    /// Set for the duration of a load.
    ///
    /// A load started while this is set throws `LLMLocalError.loadInProgress` rather than
    /// queueing behind the one in flight.
    private var isLoading: Bool = false

    // MARK: - Test Accessors

    /// The GPU buffer cache limit that will be pushed to MLX on the next load. Test-only.
    var gpuCacheLimitValue: Int { gpuCacheLimit }

    /// Whether a load is in flight. Test-only.
    var isLoadingValue: Bool { isLoading }

    /// Whether adapter-bearing model specs can be loaded at all. Test-only.
    var hasAdapterResolver: Bool { adapterResolver != nil }

    // MARK: - Initialization

    /// Creates a backend with a GPU buffer cache limit and optional adapter resolution.
    ///
    /// - Parameters:
    ///   - gpuCacheLimit: Upper bound in bytes on MLX's reuse pool of freed GPU buffers,
    ///     defaulting to 20 MB. MLX recycles intermediate buffers instead of returning them to
    ///     the allocator, and its own default is derived from Metal's recommended working set —
    ///     large enough that a long generation run keeps growing the process footprint until
    ///     iOS jetsam kills the app. Past the limit, older cached buffers are released on the
    ///     next allocation. This is a process-wide MLX setting written on every load, so the
    ///     most recently loaded backend's value wins for the whole app.
    ///   - adapterResolver: Resolves a LoRA/QLoRA `AdapterSource` to a local file URL. When
    ///     `nil`, loading a spec that carries an adapter throws
    ///     `LLMLocalError.adapterMergeFailed(reason:)`; specs without an adapter are unaffected.
    ///   - downloader: Fetches model repository snapshots. Defaults to
    ///     ``DestinationHubDownloader`` against the Hugging Face Hub.
    ///   - tokenizerLoader: Loads a tokenizer from a local directory. Defaults to the
    ///     swift-transformers `AutoTokenizer`.
    /// - Throws: When `downloader` is `nil` and the default model storage root cannot be
    ///   established — see ``DestinationHubDownloader``.
    public init(
        gpuCacheLimit: Int = 20 * 1024 * 1024,
        adapterResolver: (any AdapterResolving)? = nil,
        downloader: (any Downloader)? = nil,
        tokenizerLoader: (any TokenizerLoader)? = nil
    ) throws {
        self.gpuCacheLimit = gpuCacheLimit
        self.adapterResolver = adapterResolver
        // The swift-huggingface cache path used by #hubDownloader fails to resolve the cached
        // path of large LFS files on iOS, so the explicit-destination downloader is the default.
        self.downloader = try downloader ?? DestinationHubDownloader()
        self.tokenizerLoader = tokenizerLoader ?? #huggingFaceTokenizerLoader()
    }

    // MARK: - LLMLocalBackend

    /// Downloads the model if needed and makes it ready for inference.
    ///
    /// Reloading the model that is already loaded is a no-op. Loading a different model unloads
    /// the current one first, so the device never holds two models at once. Weights are read
    /// from every `*.safetensors` file in the model directory and evaluated eagerly, so the
    /// whole quantized weight set is resident in unified memory when this returns — on a
    /// multi-gigabyte model this read, not the first forward pass, dominates the latency of the
    /// first token after launch.
    ///
    /// - Throws: `LLMLocalError.loadInProgress` if another load is running,
    ///   `LLMLocalError.adapterMergeFailed(reason:)` if the spec's adapter cannot be resolved,
    ///   and `LLMLocalError.loadFailed(modelId:reason:)` for download, configuration, and
    ///   weight-loading failures.
    public func loadModel(_ spec: ModelSpec) async throws {
        try await performLoad(spec, progressHandler: nil)
    }

    /// Loads a model, reporting download progress.
    ///
    /// The handler fires only while files are being fetched from the Hub. A `.local` spec, or a
    /// Hub model whose snapshot is already complete on disk, reports a single completed progress
    /// value or nothing at all, and the caller then waits through the weight load with no further
    /// updates.
    public func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        try await performLoad(spec, progressHandler: progressHandler)
    }

    /// Shared implementation of model loading, with optional progress reporting.
    ///
    /// Adapter resolution happens before any MLX call so that a bad adapter fails fast without
    /// touching the GPU, and the GPU buffer cache limit is written just before the weights are
    /// read, so it is in force for the load itself.
    private func performLoad(
        _ spec: ModelSpec,
        progressHandler: (@Sendable (DownloadProgress) -> Void)?
    ) async throws {
        // If same model already loaded, skip
        if loadedSpec == spec {
            return
        }

        // If another load is in progress, throw
        guard !isLoading else {
            throw LLMLocalError.loadInProgress
        }

        isLoading = true
        defer { isLoading = false }

        await unloadModel()

        // Reset resolved adapter URL
        lastResolvedAdapterURL = nil

        // Resolve adapter before MLX initialization so that adapter
        // errors are reported early, without requiring GPU access.
        let adapterURL = try await resolveAdapter(for: spec)
        lastResolvedAdapterURL = adapterURL

        MLX.Memory.cacheLimit = gpuCacheLimit

        do {
            let modelContainer: ModelContainer
            switch spec.base {
            case .huggingFace(let id):
                modelContainer = try await LLMModelFactory.shared.loadContainer(
                    from: downloader,
                    using: tokenizerLoader,
                    configuration: ModelConfiguration(id: id),
                    progressHandler: { progress in
                        progressHandler?(DownloadProgress(
                            fraction: progress.fractionCompleted,
                            completedBytes: progress.completedUnitCount,
                            totalBytes: progress.totalUnitCount,
                            currentFile: nil
                        ))
                    }
                )
            case .local(let path):
                modelContainer = try await LLMModelFactory.shared.loadContainer(
                    from: path,
                    using: tokenizerLoader
                )
            }

            // Apply adapter if resolved
            if let adapterURL {
                let adapter = try await ModelAdapterFactory.shared.load(
                    from: downloader,
                    configuration: ModelConfiguration(directory: adapterURL)
                )
                try await modelContainer.perform { context in
                    try context.model.load(adapter: adapter)
                }
            }

            self.modelContainer = modelContainer
            chatSession = ChatSession(modelContainer, instructions: _systemPrompt)
            loadedSpec = spec
        } catch let error as LLMLocalError {
            throw error
        } catch {
            throw LLMLocalError.loadFailed(
                modelId: spec.id,
                reason: error.localizedDescription
            )
        }
    }

    /// Streams a response to a prompt, appending to the session's running conversation.
    ///
    /// Stateful: the underlying chat session keeps its own KV cache and history, so successive
    /// calls continue one conversation until ``resetSession()`` or a new load. Tools installed by
    /// an earlier ``generateWithTools(prompt:config:tools:)`` call stay in the session and keep
    /// being rendered into the prompt template; reset the session to drop them.
    ///
    /// Generation on device is a synchronous token loop, not a network stream. The loop runs at
    /// full speed into an unbounded buffer regardless of how fast the consumer reads, so a slow
    /// consumer applies no backpressure and only costs memory. Cancelling the consuming task, or
    /// breaking out of the `for await`, cancels the loop at the next token boundary; the stream
    /// then finishes with `LLMLocalError.cancelled`, and the token in flight is still computed.
    public nonisolated func generate(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, Error> {
        makeCancellableStream { [weak self] continuation in
            Task {
                guard let self else {
                    continuation.finish(throwing: LLMLocalError.modelNotLoaded)
                    return
                }
                await self.performGenerate(
                    prompt: prompt,
                    config: config,
                    continuation: continuation
                )
            }
        }
    }

    /// Streams a response that may contain tool calls, continuing the session's conversation.
    ///
    /// The tools are rendered into the prompt by the model's own chat template, and the model
    /// answers in whatever textual tool-call syntax it was trained on. MLX picks the matching
    /// parser from the `model_type` in the model's `config.json` and falls back to the
    /// `<tool_call>{"name":…,"arguments":{…}}` JSON form when the type is unknown. Text that
    /// starts to look like a tool call is buffered rather than yielded, so partial syntax never
    /// reaches the caller.
    ///
    /// Malformed tool calls do not surface as errors. If the buffered text never parses, it is
    /// flushed to the caller as ordinary text; if the model uses a syntax the selected parser
    /// does not recognize, the call is simply never emitted as `GenerationOutput.toolCall(_:)`.
    /// A caller that sees prose where it expected a tool call should suspect the format, not a
    /// dropped event.
    ///
    /// Like all generation here this is a synchronous token loop; see
    /// ``generate(prompt:config:)`` for the cancellation and backpressure behaviour.
    public nonisolated func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        makeCancellableStream { [weak self] continuation in
            Task {
                guard let self else {
                    continuation.finish(throwing: LLMLocalError.modelNotLoaded)
                    return
                }
                await self.performGenerateWithTools(
                    prompt: prompt,
                    config: config,
                    tools: tools,
                    continuation: continuation
                )
            }
        }
    }

    /// Releases the model, its chat session, and the prompt cache.
    ///
    /// Dropping the last reference is what frees the weights; MLX returns the memory as the
    /// arrays are deallocated. Call this on a memory warning — see ``MemoryMonitor`` — because a
    /// process that ignores the warning is killed rather than throttled.
    public func unloadModel() async {
        chatSession = nil
        modelContainer = nil
        loadedSpec = nil
        promptCacheStore.reset()
    }

    public var isLoaded: Bool { chatSession != nil }

    public var currentModel: ModelSpec? { loadedSpec }

    public var systemPrompt: String? { _systemPrompt }

    /// Sets the system prompt for this and later turns.
    ///
    /// Applies to the live chat session too, so the next turn is rendered with the new prompt.
    /// The KV cache is not invalidated: the prefix that encoded the old system prompt is already
    /// in it, so on the ``generateFromMessages(messages:systemPrompt:config:tools:)`` path the
    /// changed prefix is detected by token comparison and re-prefilled, while the stateful
    /// session keeps its earlier turns as they were generated.
    public func setSystemPrompt(_ prompt: String?) {
        _systemPrompt = prompt
        chatSession?.instructions = prompt
    }

    /// Starts a fresh conversation while keeping the model loaded.
    ///
    /// Both KV caches go: the chat session is rebuilt, which drops its cache and history, and
    /// the prompt cache used by ``generateFromMessages(messages:systemPrompt:config:tools:)`` is
    /// reset so no context survives into the new conversation. The next turn pays a full prefill.
    public func resetSession() {
        guard let container = modelContainer else { return }
        chatSession = ChatSession(container, instructions: _systemPrompt)
        // Reset the generateFromMessages KV cache too, so no context crosses the reset.
        promptCacheStore.reset()
    }

    /// Streams a response from an explicit message array, bypassing the chat session.
    ///
    /// Stateless with respect to history: the caller owns the conversation and passes all of it
    /// every call, so nothing accumulates inside the backend. The chat template is applied
    /// exactly once, directly through the tokenizer, which is what keeps this path free of the
    /// double-templating that pre-formatting plus a chat session produces.
    ///
    /// The KV cache is still reused across calls by comparing token sequences with the previous
    /// turn and prefilling only the changed suffix, so a growing conversation does not re-prefill
    /// from scratch. Non-text content — images, audio, video, documents — is dropped silently,
    /// and past assistant reasoning blocks are dropped by design.
    ///
    /// - Note: The reported prompt token count is the full templated prompt, not the suffix
    ///   actually fed to MLX, so usage stays comparable across turns whether or not the cache hit.
    public nonisolated func generateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        makeCancellableStream { [weak self] continuation in
            Task {
                guard let self else {
                    continuation.finish(throwing: LLMLocalError.modelNotLoaded)
                    return
                }
                await self.performGenerateFromMessages(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    config: config,
                    tools: tools,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Internal Helpers

    /// Resolves the spec's adapter source to a local URL, if it has one.
    ///
    /// Returns `nil` for a spec with no adapter. Throws when the spec has an adapter but no
    /// resolver is configured, or when resolution itself fails; either way the error is
    /// normalized to `LLMLocalError.adapterMergeFailed(reason:)`.
    ///
    /// Split out so it can be exercised without GPU or Metal access.
    func resolveAdapter(for spec: ModelSpec) async throws -> URL? {
        guard let adapterSource = spec.adapter else { return nil }

        guard let resolver = adapterResolver else {
            throw LLMLocalError.adapterMergeFailed(
                reason: "No adapter resolver configured"
            )
        }

        do {
            return try await resolver.resolve(adapterSource)
        } catch let error as LLMLocalError {
            throw error
        } catch {
            throw LLMLocalError.adapterMergeFailed(
                reason: error.localizedDescription
            )
        }
    }

    // MARK: - Private Helpers

    /// Runs generation inside the actor's isolation domain.
    ///
    /// `ChatSession` is not `Sendable`, so the work has to happen here rather than in the
    /// nonisolated stream builder. Cancellation is observed between tokens: the loop checks after
    /// each chunk and reports `LLMLocalError.cancelled`.
    private func performGenerate(
        prompt: String,
        config: GenerationConfig,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        guard let session = chatSession else {
            continuation.finish(throwing: LLMLocalError.modelNotLoaded)
            return
        }

        session.generateParameters = config.mlxParameters
        session.additionalContext = config.chatTemplateContext

        do {
            for try await text in session.streamResponse(to: prompt) {
                try Task.checkCancellation()
                continuation.yield(text)
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: LLMLocalError.cancelled)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Runs tool-enabled generation inside the actor's isolation domain.
    ///
    /// The tool specs are installed on the session, so they stay in effect for later turns on
    /// the same session until it is reset.
    private func performGenerateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition],
        continuation: AsyncThrowingStream<GenerationOutput, Error>.Continuation
    ) async {
        guard let session = chatSession else {
            continuation.finish(throwing: LLMLocalError.modelNotLoaded)
            return
        }

        session.tools = tools.map { $0.toolSpec }
        session.generateParameters = config.mlxParameters
        session.additionalContext = config.chatTemplateContext

        do {
            for try await generation in session.streamDetails(
                to: prompt, images: [], videos: []
            ) {
                try Task.checkCancellation()
                if let output = GenerationOutput(generation) {
                    continuation.yield(output)
                }
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: LLMLocalError.cancelled)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Generates a response from a structured message array.
    ///
    /// Skips `ChatSession` and calls the tokenizer's `applyChatTemplate` directly, so the chat
    /// template is applied exactly once. The template is the model's own Jinja template from
    /// `tokenizer_config.json`; a model that ships none makes this throw, but a template that
    /// merely disagrees with how the checkpoint was trained produces a silently worse model — no
    /// error, just degraded output.
    ///
    /// Work happens inside `ModelContainer.perform`, which serializes access to the
    /// non-`Sendable` model context.
    private func performGenerateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition],
        continuation: AsyncThrowingStream<GenerationOutput, Error>.Continuation
    ) async {
        guard let container = modelContainer else {
            continuation.finish(throwing: LLMLocalError.modelNotLoaded)
            return
        }

        // Build MLX message array (let-binding for Sendable capture)
        let mlxMessages: [[String: any Sendable]] = {
            var msgs: [[String: any Sendable]] = []
            if let systemPrompt, !systemPrompt.isEmpty {
                msgs.append(["role": "system", "content": systemPrompt])
            }
            for msg in messages {
                msgs.append(contentsOf: Self.convertToMLXFormat(msg))
            }
            return msgs
        }()

        let toolSpecs: [[String: any Sendable]]? = tools.isEmpty
            ? nil : tools.map { $0.toolSpec }
        let parameters = config.mlxParameters

        // Skip the shared cache while another generation holds it, so KV context cannot leak
        // between concurrent conversations. Prefill reuse applies to serial single-conversation
        // generation only.
        let useSharedCache = !cacheBusy
        if useSharedCache { cacheBusy = true }
        defer { if useSharedCache { cacheBusy = false } }

        do {
            let additionalContext = config.chatTemplateContext
            let cacheStore = promptCacheStore
            try await container.perform { context in
                let tokens = try context.tokenizer.applyChatTemplate(
                    messages: mlxMessages,
                    tools: toolSpecs,
                    additionalContext: additionalContext
                )
                guard !tokens.isEmpty else { return }

                let cache: [KVCache]
                let suffixStart: Int
                if useSharedCache {
                    // Reuse the prefix shared with the previous turn; prefill only the suffix.
                    (cache, suffixStart) = cacheStore.prepare(for: tokens) {
                        context.model.newCache(parameters: parameters)
                    }
                } else {
                    // Concurrent generation: prefill everything into a private cache rather than
                    // contaminating the shared one.
                    cache = context.model.newCache(parameters: parameters)
                    suffixStart = 0
                }
                let suffix = Array(tokens[suffixStart...])
                let input = LMInput(tokens: MLXArray(suffix))

                let stream = try MLXLMCommon.generate(
                    input: input,
                    cache: cache,
                    parameters: parameters,
                    context: context
                )

                for await generation in stream {
                    guard !Task.isCancelled else { break }
                    if let output = Self.mapGeneration(
                        generation, fullPromptTokenCount: tokens.count
                    ) {
                        continuation.yield(output)
                    }
                }

                // Record the state for the next turn's prefix reuse, shared cache only. This runs
                // after a cancelled loop as well: the cache then holds the prompt plus the tokens
                // generated before the break, which the next turn trims back to the shared prefix.
                if useSharedCache {
                    cacheStore.commit(tokens: tokens, cache: cache)
                }
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: LLMLocalError.cancelled)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Converts an MLX generation event into an output value, correcting the prompt token count.
    ///
    /// When the prompt cache hits, MLX only ever sees the suffix, so the count it reports is the
    /// number of tokens prefilled on this turn rather than the size of the input. The `.info`
    /// event's prompt token count is overwritten with the length of the fully templated prompt so
    /// that usage keeps meaning "input tokens" regardless of cache state.
    ///
    /// Tokens per second is computed from the generation phase only and excludes prefill.
    private static func mapGeneration(
        _ generation: Generation,
        fullPromptTokenCount: Int
    ) -> GenerationOutput? {
        switch generation {
        case .chunk(let text):
            return .text(text)
        case .toolCall(let toolCall):
            return .toolCall(LLMTool.ToolCall(from: toolCall))
        case .info(let info):
            return .info(GenerationInfo(
                promptTokenCount: fullPromptTokenCount,
                generationTokenCount: info.generationTokenCount,
                tokensPerSecond: info.generateTime > 0
                    ? Double(info.generationTokenCount) / info.generateTime : 0
            ))
        @unknown default:
            return nil
        }
    }

    // MARK: - LLMMessage → MLX Format Conversion

    /// Converts a canonical message into the message dictionaries the chat template expects.
    ///
    /// One message can expand into several: tool results each become their own `"tool"` role
    /// message, emitted before the user's text so the model reads results in order. Assistant
    /// tool calls are rendered in the OpenAI `tool_calls` shape, with arguments as a JSON string.
    ///
    /// Image, audio, video, and document content is dropped — this backend runs text-only models,
    /// and the caller gets no signal that the attachment went missing.
    private static func convertToMLXFormat(_ message: LLMMessage) -> [[String: any Sendable]] {
        var result: [[String: any Sendable]] = []

        var textContent = ""
        var toolUses: [[String: any Sendable]] = []
        var toolResults: [(callId: String, content: String)] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                textContent += text
            case .toolUse(let id, let name, let input):
                let argsString = String(data: input, encoding: .utf8) ?? "{}"
                toolUses.append([
                    "id": id,
                    "type": "function",
                    "function": [
                        "name": name,
                        "arguments": argsString,
                    ] as [String: any Sendable],
                ])
            case .toolResult(let callId, _, let content):
                toolResults.append((callId: callId, content: content.contentValue))
            case .image, .audio, .video, .document:
                break
            case .thinking:
                // Reasoning from earlier turns is not replayed into the history. The published
                // guidance for thinking models, Qwen3 among them, is to keep only the final
                // output in multi-turn history. Re-injecting the reasoning burns context and
                // collides with the template's own handling of thinking spans, degrading output.
                break
            }
        }

        if message.role == .assistant {
            if !toolUses.isEmpty {
                var msg: [String: any Sendable] = [
                    "role": "assistant",
                    "tool_calls": toolUses,
                ]
                if !textContent.isEmpty {
                    msg["content"] = textContent
                }
                result.append(msg)
            } else if !textContent.isEmpty {
                result.append(["role": "assistant", "content": textContent])
            }
        } else {
            // User role
            for tr in toolResults {
                result.append([
                    "role": "tool",
                    "content": tr.content,
                    "tool_call_id": tr.callId,
                ])
            }
            if !textContent.isEmpty {
                result.append(["role": "user", "content": textContent])
            }
        }

        return result
    }
}

// MARK: - Prompt (KV) Cache Reuse

/// Holds a KV cache between turns so a stateless caller can skip re-prefilling the prompt.
///
/// Compares the token sequence produced by `applyChatTemplate` against the previous turn, keeps
/// the cache covering the shared prefix, and lets the caller prefill only the difference. The KV
/// cache grows with context length — every token in the conversation keeps its keys and values
/// resident — so on device this store trades memory that would otherwise be recomputed against
/// prefill time. Bounding that growth is the caller's job, through `GenerationConfig.maxKVSize`
/// (which switches MLX to a rotating cache that evicts oldest-first) and `kvBits`.
///
/// ## Thread safety
///
/// Marked `@unchecked Sendable` because ``MLXBackend`` only ever touches it from inside
/// `ModelContainer.perform`, which serializes on an actor. `MLXLMCommon.KVCache` is not
/// `Sendable`, so the compiler cannot verify this; the safety argument is the serial-execution
/// invariant. Concurrent generation against one store is not supported.
final class PromptCacheStore: @unchecked Sendable {
    /// The full prompt the retained cache currently represents.
    private var tokens: [Int] = []
    private var cache: [KVCache]?

    /// Discards the cache, for model switches, conversation resets, and unloads.
    func reset() {
        tokens = []
        cache = nil
    }

    /// Returns the cache to generate with and the token index where prefill should start.
    ///
    /// Falls back to a fresh cache starting at index 0 on the first turn, when the prefixes
    /// diverge, or when the retained cache cannot be trimmed — a rotating cache that has already
    /// wrapped past its size limit has lost the evicted entries and is no longer trimmable, so a
    /// long conversation under `maxKVSize` eventually pays full prefills again.
    ///
    /// Otherwise it trims the cache back to the shared prefix of length `p` and starts prefill
    /// there. At least one token is always prefilled, since the model needs an input to produce
    /// logits from.
    func prepare(
        for newTokens: [Int],
        makeCache: () -> [KVCache]
    ) -> (cache: [KVCache], suffixStart: Int) {
        guard let existing = cache, !tokens.isEmpty else {
            return (freshCache(makeCache), 0)
        }

        var prefix = Self.commonPrefixLength(tokens, newTokens)
        // At least one token has to be prefilled.
        if prefix >= newTokens.count { prefix = newTokens.count - 1 }
        guard prefix > 0 else {
            return (freshCache(makeCache), 0)
        }

        // The retained cache holds the previous prompt plus what was generated from it, so trim
        // from the end until only the first `prefix` tokens remain.
        let offset = existing.first?.offset ?? 0
        let trimCount = offset - prefix
        if trimCount > 0 {
            guard canTrimPromptCache(existing),
                  trimPromptCache(existing, numTokens: trimCount) == trimCount
            else {
                return (freshCache(makeCache), 0)
            }
        }
        return (existing, prefix)
    }

    /// Records the prompt and cache a finished generation leaves behind, for the next turn.
    func commit(tokens: [Int], cache: [KVCache]) {
        self.tokens = tokens
        self.cache = cache
    }

    private func freshCache(_ makeCache: () -> [KVCache]) -> [KVCache] {
        let fresh = makeCache()
        cache = fresh
        tokens = []
        return fresh
    }

    /// Returns how many leading tokens two sequences share.
    static func commonPrefixLength(_ a: [Int], _ b: [Int]) -> Int {
        let limit = min(a.count, b.count)
        var i = 0
        while i < limit, a[i] == b[i] { i += 1 }
        return i
    }
}

// MARK: - MLX Generation → GenerationOutput

extension GenerationOutput {
    /// Converts an MLX generation event into an output value.
    ///
    /// Returns `nil` for event kinds this package does not know about, which are then dropped
    /// from the stream rather than surfaced as errors.
    ///
    /// The prompt token count is taken from MLX as-is, which is correct for the chat session
    /// paths because they always feed the full prompt.
    init?(_ generation: Generation) {
        switch generation {
        case .chunk(let text):
            self = .text(text)
        case .toolCall(let toolCall):
            self = .toolCall(LLMTool.ToolCall(from: toolCall))
        case .info(let info):
            self = .info(GenerationInfo(
                promptTokenCount: info.promptTokenCount,
                generationTokenCount: info.generationTokenCount,
                tokensPerSecond: info.generateTime > 0
                    ? Double(info.generationTokenCount) / info.generateTime : 0
            ))
        @unknown default:
            return nil
        }
    }
}
