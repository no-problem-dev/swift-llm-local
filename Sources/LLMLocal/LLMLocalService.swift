import LLMTool
import LLMClient
import LLMLocalClient
import LLMLocalMLX
import LLMLocalModels

/// High-level facade for on-device text generation, binding an inference backend to a model catalogue.
///
/// Everything here runs locally through Apple MLX. There is no network round trip at generation
/// time, nothing is billed per token, and no server-side rate limit exists, so the retry, backoff,
/// and quota machinery a hosted provider client needs has nothing to act on. The costs are physical
/// instead: model weights are resident RAM measured in gigabytes, and the first use of a model has
/// to pull that many gigabytes down from Hugging Face.
///
/// Loading is implicit. Every generation entry point loads the requested model if the backend is
/// not already holding it, so time to first token on a cold model includes the download (once) and
/// the load into memory (on every model change). Pass a ``ModelSwitcher`` to route loading through
/// eviction bookkeeping, or a `MemoryMonitor` to have the resident model dropped automatically
/// when the system raises a memory warning — on iOS the app is killed by jetsam before physical RAM
/// runs out, so releasing the weights is the only useful response to that warning.
///
/// ## Example
///
/// ```swift
/// let monitor = MemoryMonitor()
/// let service = LLMLocalService(
///     backend: mlxBackend,
///     modelRegistry: modelRegistry,
///     memoryMonitor: monitor
/// )
/// await service.startMemoryMonitoring()
///
/// let stream = await service.generate(
///     model: ModelPresets.qwen3_0_6B,
///     prompt: "What is Swift?"
/// )
/// for try await token in stream {
///     print(token, terminator: "")
/// }
/// ```
public actor LLMLocalService {

    private let backend: any LLMLocalBackend
    private let modelRegistry: ModelRegistry
    private let memoryMonitor: MemoryMonitor?
    private let modelSwitcher: ModelSwitcher?
    /// Inventory that answers download questions by reading the disk.
    ///
    /// Unlike an in-memory registry, it stays correct across app restarts and for models that are
    /// downloaded but not loaded.
    private let inventory: LocalModelInventory

    /// Statistics for the most recently finished generation, or `nil` until one finishes.
    ///
    /// The duration is wall clock measured from the moment the generation call was made, so on a
    /// cold model it includes the download and the load; the throughput figure, when the backend
    /// measures it, covers the generation phase only. The two are meant to disagree.
    private(set) public var lastGenerationStats: GenerationStats?

    /// Creates a service over the given backend, with optional memory monitoring and model switching.
    ///
    /// - Parameters:
    ///   - backend: Inference backend that loads weights and produces tokens.
    ///   - modelRegistry: Metadata registry. It is retained but not consulted by this type; download
    ///     state is read from disk through the inventory instead.
    ///   - memoryMonitor: Monitor used to unload the resident model on a system memory warning.
    ///     Without one, the memory queries on this type return `nil` and no automatic unload happens.
    ///   - modelSwitcher: Switcher that owns load and eviction bookkeeping. When supplied, the
    ///     generation entry points ask it to load rather than calling the backend directly.
    ///     Preloading through this type always bypasses it.
    ///   - inventory: Reader for the on-disk model store. Point it at a different root only if the
    ///     backend's downloader was pointed there too, or downloaded models will look missing.
    ///     When `nil`, one is built over the default root.
    /// - Throws: When `inventory` is `nil` and the default model storage root cannot be
    ///   established — see `LocalModelInventory`.
    public init(
        backend: any LLMLocalBackend,
        modelRegistry: ModelRegistry,
        memoryMonitor: MemoryMonitor? = nil,
        modelSwitcher: ModelSwitcher? = nil,
        inventory: LocalModelInventory? = nil
    ) throws {
        self.backend = backend
        self.modelRegistry = modelRegistry
        self.memoryMonitor = memoryMonitor
        self.modelSwitcher = modelSwitcher
        self.inventory = try inventory ?? LocalModelInventory()
    }

    /// Generates text from a prompt, streaming each chunk as the model produces it.
    ///
    /// If the backend is not already holding this model, it is loaded first: downloaded from
    /// Hugging Face on first use, and mapped into RAM on every model change. The first chunk of a
    /// cold model can therefore be many seconds behind the call. Once the model is warm the whole
    /// run is local — nothing is sent anywhere, nothing is billed, and there is no rate limit to
    /// back off from. Statistics land in ``lastGenerationStats`` when the stream finishes.
    ///
    /// > Important: This is the stateful entry point. It reuses one internal chat session, so
    /// > consecutive calls accumulate earlier prompts and replies as conversation history, which is
    /// > what chat wants. To treat each call as independent, clear the history first with
    /// > ``resetChatSession()``, or use
    /// > ``generateFromMessages(model:messages:systemPrompt:config:tools:)``, which takes the whole
    /// > conversation as an argument and accumulates nothing.
    ///
    /// > Note: `GenerationStats.tokensPerSecond` recorded here is approximated from the number of
    /// > text chunks, because this path of the backend emits no measured token counters. For
    /// > measured throughput use ``generateWithTools(model:prompt:tools:config:)`` or
    /// > ``generateFromMessages(model:messages:systemPrompt:config:tools:)``.
    ///
    /// - Parameters:
    ///   - model: Model to generate with.
    ///   - prompt: Input prompt.
    ///   - config: Sampling, KV cache, and thinking-mode settings.
    /// - Returns: A stream of text chunks. Cancelling the consuming task stops generation and
    ///   finishes the stream with `LLMLocalError.cancelled`.
    public func generate(
        model: ModelSpec,
        prompt: String,
        config: GenerationConfig = .default
    ) -> AsyncThrowingStream<String, Error> {
        let backend = self.backend
        let modelSwitcher = self.modelSwitcher
        let startTime = ContinuousClock.now

        return makeCancellableStream { [weak self] continuation in
            Task {
                do {
                    // Load model: use switcher if available, otherwise direct backend
                    if let switcher = modelSwitcher {
                        try await switcher.ensureLoaded(model)
                    } else {
                        let currentModel = await backend.currentModel
                        if currentModel != model {
                            try await backend.loadModel(model)
                        }
                    }

                    // Generate tokens and track stats
                    var tokenCount = 0
                    let innerStream = backend.generate(prompt: prompt, config: config)
                    for try await token in innerStream {
                        try Task.checkCancellation()
                        tokenCount += 1
                        continuation.yield(token)
                    }

                    // Record stats
                    let duration = ContinuousClock.now - startTime
                    let seconds = Double(duration.components.seconds)
                        + Double(duration.components.attoseconds) / 1e18
                    let tokensPerSecond = seconds > 0
                        ? Double(tokenCount) / seconds : 0

                    let stats = GenerationStats(
                        tokenCount: tokenCount,
                        tokensPerSecond: tokensPerSecond,
                        duration: duration
                    )
                    await self?.updateStats(stats)

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMLocalError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Generates a response that may contain tool calls, streaming text and calls as they arrive.
    ///
    /// Tool calling on-device is driven by the model's own chat template and output format, not by
    /// a provider-side function-calling API. It is markedly less dependable than a hosted provider:
    /// small quantized models skip calls, emit arguments that do not match the schema, or answer in
    /// a format the backend has no parser for. A model whose profile declares tool calls
    /// unsupported is rejected up front — the stream finishes with
    /// `LLMLocalError.toolCallsUnsupported(modelId:)` — rather than quietly dropping the tools,
    /// because an agent loop reads a tool-free reply as "no tool needed" and ends the turn.
    ///
    /// The model is loaded first if the backend is not already holding it. Unlike the plain text
    /// path, this one records measured token counts and throughput in ``lastGenerationStats`` when
    /// the backend reports them.
    ///
    /// > Important: Stateful like ``generate(model:prompt:config:)``. It reuses the same chat
    /// > session, so history accumulates across calls; call ``resetChatSession()`` first, or use
    /// > ``generateFromMessages(model:messages:systemPrompt:config:tools:)``.
    ///
    /// - Parameters:
    ///   - model: Model to generate with.
    ///   - prompt: Input prompt.
    ///   - tools: Tool definitions offered to the model.
    ///   - config: Sampling, KV cache, and thinking-mode settings.
    /// - Returns: A stream of text chunks, parsed tool calls, and a final statistics event.
    public func generateWithTools(
        model: ModelSpec,
        prompt: String,
        tools: [ToolDefinition],
        config: GenerationConfig = .default
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        let backend = self.backend
        let modelSwitcher = self.modelSwitcher
        let startTime = ContinuousClock.now

        return makeCancellableStream { [weak self] continuation in
            Task {
                do {
                    try Self.validateToolCallSupport(model: model, tools: tools)

                    // Load model: use switcher if available, otherwise direct backend
                    if let switcher = modelSwitcher {
                        try await switcher.ensureLoaded(model)
                    } else {
                        let currentModel = await backend.currentModel
                        if currentModel != model {
                            try await backend.loadModel(model)
                        }
                    }

                    // Generate and track stats
                    var counter = TokenCounter()
                    let innerStream = backend.generateWithTools(
                        prompt: prompt, config: config, tools: tools
                    )
                    for try await output in innerStream {
                        try Task.checkCancellation()
                        counter.observe(output)
                        continuation.yield(output)
                    }

                    await self?.updateStats(counter.stats(since: startTime))

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMLocalError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Generates a response from an explicit message array, applying the chat template exactly once.
    ///
    /// This entry point is stateless: the full conversation arrives on every call and nothing
    /// accumulates inside the service. Handing a pre-rendered prompt string to
    /// ``generate(model:prompt:config:)`` instead would apply the chat template a second time on
    /// top of the first.
    ///
    /// Statelessness does not mean the prompt is reprocessed from scratch. The MLX backend keeps
    /// the KV cache from the previous turn and compares token prefixes, so a growing agent
    /// conversation only prefills the tokens that changed; prompt processing stays proportional to
    /// the new suffix rather than to the whole history. That cache is dropped on model switch,
    /// session reset, and unload. If a second generation starts while one is still running, it uses
    /// a throwaway cache and prefills everything, so two conversations sharing a backend cannot
    /// leak context into each other.
    ///
    /// A model whose profile declares tool calls unsupported is rejected before generation starts,
    /// and the stream finishes with `LLMLocalError.toolCallsUnsupported(modelId:)`.
    ///
    /// - Parameters:
    ///   - model: Model to generate with.
    ///   - messages: Full conversation, oldest first.
    ///   - systemPrompt: System prompt, or `nil` to send none.
    ///   - config: Sampling, KV cache, and thinking-mode settings.
    ///   - tools: Tool definitions offered to the model.
    /// - Returns: A stream of text chunks, parsed tool calls, and a final statistics event carrying
    ///   measured prompt and generation token counts.
    public func generateFromMessages(
        model: ModelSpec,
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig = .default,
        tools: [ToolDefinition] = []
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        let backend = self.backend
        let modelSwitcher = self.modelSwitcher
        let startTime = ContinuousClock.now

        return makeCancellableStream { [weak self] continuation in
            Task {
                do {
                    try Self.validateToolCallSupport(model: model, tools: tools)

                    // Load model: use switcher if available, otherwise direct backend
                    if let switcher = modelSwitcher {
                        try await switcher.ensureLoaded(model)
                    } else {
                        let currentModel = await backend.currentModel
                        if currentModel != model {
                            try await backend.loadModel(model)
                        }
                    }

                    // Generate and track stats
                    var counter = TokenCounter()
                    let innerStream = backend.generateFromMessages(
                        messages: messages,
                        systemPrompt: systemPrompt,
                        config: config,
                        tools: tools
                    )
                    for try await output in innerStream {
                        try Task.checkCancellation()
                        counter.observe(output)
                        continuation.yield(output)
                    }

                    await self?.updateStats(counter.stats(since: startTime))

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMLocalError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Tool Call Capability

    /// Rejects tool-bearing requests aimed at models that cannot produce tool calls.
    ///
    /// On-device, tool-call capability belongs to the model — its chat template has to render the
    /// tools and its output format has to be parseable — not to the backend, so the check reads the
    /// model profile rather than a type-level capability. A model with no profile is allowed
    /// through: its support is unknown, not known to be absent.
    private static func validateToolCallSupport(
        model: ModelSpec,
        tools: [ToolDefinition]
    ) throws {
        guard !tools.isEmpty,
              model.profile?.toolCallSupport == ToolCallSupport.unsupported
        else { return }
        throw LLMLocalError.toolCallsUnsupported(modelId: model.id)
    }

    // MARK: - System Prompt

    public var systemPrompt: String? {
        get async { await backend.systemPrompt }
    }

    /// Sets the system prompt used by subsequent generations.
    ///
    /// The prompt is forwarded to the backend, applied to the live chat session immediately, and
    /// retained across model loads, so the session created for the next model starts with it
    /// already in place.
    ///
    /// - Parameter prompt: New system prompt, or `nil` to clear it.
    public func setSystemPrompt(_ prompt: String?) async {
        await backend.setSystemPrompt(prompt)
    }

    // MARK: - Downloaded Models (disk truth)

    /// Reports whether the model is present on disk as a complete snapshot.
    ///
    /// Disk is the only truth about download state: the check looks for the config file plus
    /// weights in the model's directory, so it stays correct after an app restart and for models
    /// that are downloaded but not loaded. A download interrupted partway leaves its finished files
    /// behind and still answers `false`, because the weights are incomplete. Use this to gate a
    /// model picker to what can start without a multi-gigabyte wait, and to badge a list.
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when the model's directory is
    ///   there but cannot be read. `false` means absent or incomplete, never "could not tell".
    public func isDownloaded(_ spec: ModelSpec) throws -> Bool {
        try inventory.isDownloaded(spec)
    }

    /// Returns the downloaded members of a candidate list with their on-disk size and download time.
    ///
    /// Snapshots are stored under their Hugging Face repository path, independent of the app's
    /// model ids, so candidates have to be supplied rather than discovered — usually
    /// ``ModelPresets/all``. Most recently downloaded first.
    ///
    /// - Parameter specs: Models to look for on disk.
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when a candidate's directory is
    ///   there but cannot be read or measured.
    public func downloadedModels(among specs: [ModelSpec]) throws -> [DownloadedModel] {
        try inventory.downloadedModels(among: specs)
    }

    /// Bytes the model's files occupy on disk, or `nil` when it is not fully downloaded.
    ///
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when the directory is there but
    ///   cannot be measured.
    public func downloadSize(of spec: ModelSpec) throws -> Int64? {
        try inventory.diskSize(of: spec)
    }

    /// Total bytes occupied on disk by the downloaded members of a candidate list.
    ///
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when a candidate cannot be
    ///   measured. Zero means nothing is downloaded, never a partial sum.
    public func totalDownloadedSize(among specs: [ModelSpec]) throws -> Int64 {
        try inventory.totalDiskSize(among: specs)
    }

    /// Deletes a model's downloaded files to reclaim disk space.
    ///
    /// Weights run to gigabytes each, so this is the counterpart of keeping several models
    /// available offline. If the model is the one the backend currently holds, it is unloaded first
    /// so the files are not removed while they are open. Models sourced from a local path belong to
    /// the caller and are left untouched, and deleting a model that was never downloaded does
    /// nothing.
    ///
    /// - Parameter spec: Model whose files should be removed.
    /// - Throws: If the directory cannot be removed.
    public func deleteDownload(_ spec: ModelSpec) async throws {
        // Unload first when the target is resident, so the files are not held open while removed.
        if await backend.currentModel == spec {
            await backend.unloadModel()
        }
        try inventory.delete(spec)
    }

    /// Loads a model into the backend ahead of the first generation request.
    ///
    /// This moves the cold-start cost — the Hugging Face download on first use, and the load into
    /// RAM on every model change — off the user's first prompt. The weights then stay resident
    /// until another model is loaded, the backend is unloaded, or a memory warning evicts them.
    /// This calls the backend directly and does not go through ``ModelSwitcher``, so switcher
    /// bookkeeping does not learn about the model loaded this way.
    ///
    /// - Parameter spec: Model to load.
    /// - Throws: `LLMLocalError.downloadFailed(modelId:reason:)` if the weights cannot be
    ///   fetched, `LLMLocalError.loadInProgress` if another load is already running, or
    ///   `LLMLocalError.loadFailed(modelId:reason:)` for anything else.
    public func prefetch(_ spec: ModelSpec) async throws {
        try await backend.loadModel(spec)
    }

    /// Loads a model ahead of time and reports download progress while it runs.
    ///
    /// Progress covers the download only. A model already on disk jumps straight to complete, and
    /// the remaining wait is the load into memory, which is not reported. An interrupted download
    /// keeps the files it finished and the partial bytes of the file it was on, and resumes from
    /// there on the next attempt instead of starting the gigabytes again.
    ///
    /// - Parameters:
    ///   - spec: Model to load.
    ///   - onProgress: Called as the download advances.
    /// - Throws: The same failures as ``prefetch(_:)``.
    public func prefetch(
        _ spec: ModelSpec,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        try await backend.loadModel(spec, progressHandler: onProgress)
    }

    // MARK: - Session Management

    /// Clears the conversation history while keeping the model in memory.
    ///
    /// Only chat state is discarded; the weights stay resident, so the next generation does not pay
    /// the load cost again. The prompt cache used by the message-array path is dropped too, so the
    /// first turn after a reset prefills its whole prompt.
    public func resetChatSession() async {
        await backend.resetSession()
    }

    // MARK: - Memory Monitoring

    /// Starts watching for system memory warnings and unloads the resident model when one arrives.
    ///
    /// A loaded model is gigabytes of resident RAM, and on iOS the app is killed by jetsam well
    /// before physical memory is exhausted, so releasing the weights is the only useful response to
    /// a warning. The next generation reloads them from disk. Does nothing when no memory monitor
    /// was supplied at initialization.
    public func startMemoryMonitoring() async {
        guard let monitor = memoryMonitor else { return }
        let backend = self.backend
        await monitor.startMonitoring {
            await backend.unloadModel()
        }
    }

    /// Stops watching for memory warnings, leaving any loaded model resident.
    ///
    /// Does nothing when no memory monitor was supplied at initialization.
    public func stopMemoryMonitoring() async {
        await memoryMonitor?.stopMonitoring()
    }

    /// Suggests a context length the device's memory can carry.
    ///
    /// The KV cache grows with context length and competes with the weights for the same RAM, so
    /// the ceiling is a property of the device rather than of the model. Devices with less than
    /// 12 GB of physical memory get 2048 tokens; 12 GB or more gets 4096.
    ///
    /// - Returns: Suggested context length in tokens, or `nil` when no memory monitor was supplied.
    public func recommendedContextLength() async -> Int? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.recommendedContextLength()
    }

    /// Physical memory installed in the device, in bytes, or `nil` without a memory monitor.
    public func totalMemory() async -> UInt64? {
        guard let monitor = memoryMonitor else { return nil }
        return await monitor.totalMemory()
    }

    /// Memory currently available in bytes, or `nil` when no memory monitor was supplied.
    ///
    /// On iOS this is what this process may still allocate before jetsam intervenes, not free
    /// system RAM, and it moves while the app runs. On macOS it is an estimate from free and
    /// inactive pages.
    ///
    /// - Throws: ``LLMLocalError/memoryUnreadable(reason:)`` when the kernel query fails. `nil`
    ///   means no monitor was supplied, never that the number could not be read.
    public func availableMemory() async throws -> UInt64? {
        guard let monitor = memoryMonitor else { return nil }
        return try await monitor.availableMemory()
    }

    /// Reports whether this device can be expected to hold the model's weights.
    ///
    /// The test compares the model's estimated memory against ``maxAllowedModelMemory()``. Since
    /// the iOS budget is derived from memory available right now, the same model can be judged
    /// compatible at launch and incompatible later in the session.
    ///
    /// - Parameter spec: Model to check.
    /// - Returns: `true` when it fits, or `nil` when no memory monitor was supplied.
    /// - Throws: ``LLMLocalError/memoryUnreadable(reason:)`` when the kernel query fails. `false`
    ///   means the model is too big, never that the budget could not be measured.
    public func isModelCompatible(_ spec: ModelSpec) async throws -> Bool? {
        guard let monitor = memoryMonitor else { return nil }
        return try await monitor.isModelCompatible(spec)
    }

    /// Largest model, in bytes, this device is expected to hold.
    ///
    /// On iOS, tvOS, and watchOS the budget is 80% of the memory the process may still allocate,
    /// because an app is killed by jetsam before physical RAM is exhausted and a total-memory
    /// budget would call a 5 GB model safe on an 8 GB phone. On macOS it is 80% of physical
    /// memory. The margin covers the KV cache, activations, and the rest of the app.
    ///
    /// - Returns: Budget in bytes, or `nil` when no memory monitor was supplied.
    /// - Throws: ``LLMLocalError/memoryUnreadable(reason:)`` when the kernel query fails.
    public func maxAllowedModelMemory() async throws -> UInt64? {
        guard let monitor = memoryMonitor else { return nil }
        return try await monitor.maxAllowedModelMemory()
    }

    // MARK: - Private

    private func updateStats(_ stats: GenerationStats) {
        lastGenerationStats = stats
    }
}

/// Aggregates token statistics while a generation stream is consumed.
///
/// When the backend emits a measured info event, its token count and throughput win; the throughput
/// it reports covers the generation phase only, excluding prompt processing. When no info event
/// arrives — the plain text path never sends one — the count falls back to the number of text
/// chunks, which is an approximation of token count, not a measurement of it. Duration is wall
/// clock either way, and includes model download and load when the model started cold.
private struct TokenCounter {
    private var chunkCount = 0
    private var info: GenerationInfo?

    mutating func observe(_ output: GenerationOutput) {
        switch output {
        case .text:
            chunkCount += 1
        case .info(let generationInfo):
            info = generationInfo
        case .toolCall:
            break
        }
    }

    func stats(since startTime: ContinuousClock.Instant) -> GenerationStats {
        let duration = ContinuousClock.now - startTime
        if let info {
            return GenerationStats(
                tokenCount: info.generationTokenCount,
                tokensPerSecond: info.tokensPerSecond,
                duration: duration
            )
        }
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return GenerationStats(
            tokenCount: chunkCount,
            tokensPerSecond: seconds > 0 ? Double(chunkCount) / seconds : 0,
            duration: duration
        )
    }
}
