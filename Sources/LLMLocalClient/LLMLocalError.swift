import Foundation

/// Failures raised while downloading, loading, or generating with an on-device model.
///
/// The cases divide into four groups by what the caller should do. Retrying the same call can
/// work for ``downloadFailed(modelId:reason:)`` and ``loadInProgress``. Retrying is pointless until
/// something changes for ``loadFailed(modelId:reason:)`` and ``adapterMergeFailed(reason:)`` — fix
/// the spec, free memory, or offer a smaller model. ``modelNotLoaded`` and
/// ``toolCallsUnsupported(modelId:)`` are caller mistakes to fix in code, and ``cancelled`` is not
/// a failure at all. ``registryUnreadable(reason:)`` stands alone: nothing about the request is
/// wrong, the record of what is already on the device cannot be read.
///
/// Every case here is raised by this package. A device that is out of memory or disk shows up as
/// ``loadFailed(modelId:reason:)`` or ``downloadFailed(modelId:reason:)`` rather than as a case of
/// its own, so ask ``MemoryMonitor`` whether a spec fits *before* starting a load you cannot
/// finish.
public enum LLMLocalError: Error, Sendable, Equatable {
    /// Fetching the model's weights failed.
    ///
    /// Usually transient — connectivity, or the model host being unavailable — so a retry is
    /// reasonable. A partial download is not a usable model: the inventory only counts a directory
    /// as downloaded once config and weights are both present, so an interrupted fetch simply
    /// starts over.
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model being fetched.
    ///   - reason: Message from the downloader, meant for logs rather than the user.
    case downloadFailed(modelId: String, reason: String)

    /// Preparing the model for inference failed after its files were available.
    ///
    /// This is the catch-all for the load path: unreadable or truncated weights, an architecture the
    /// runtime does not implement, a missing tokenizer, or an allocation failure. Retrying the same
    /// spec generally reproduces it. The model is left unloaded, so ``LLMLocalBackend/currentModel``
    /// is `nil` afterwards even if a different model was loaded before the attempt.
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model that failed to load.
    ///   - reason: Underlying error text, meant for logs rather than the user.
    case loadFailed(modelId: String, reason: String)

    /// Generation was requested before any model was loaded.
    ///
    /// A programming error rather than a runtime condition: load first, or route calls through a
    /// service that loads on demand. It arrives as the stream's failure, not as a thrown error.
    case modelNotLoaded

    /// Another load is already running on this backend.
    ///
    /// Loads are not queued, so this is the answer to a second concurrent load, not to a slow one.
    /// Wait for the first to finish rather than retrying in a tight loop — and note that asking for
    /// the model that is already resident returns successfully instead of raising this.
    case loadInProgress

    /// The work was cancelled, either by the caller or by the consumer abandoning the stream.
    ///
    /// Expected control flow, not a failure: do not show it as an error and do not retry
    /// automatically. The model stays loaded, so the next generation starts immediately.
    case cancelled

    /// A LoRA/QLoRA adapter could not be resolved or applied to the base model.
    ///
    /// Raised when the spec names an adapter but no resolver was injected, when the adapter cannot
    /// be found or downloaded, or when the runtime rejects it. All of these need a configuration
    /// change; the base model can still be loaded by using a spec without the adapter.
    ///
    /// - Parameter reason: What went wrong, meant for logs rather than the user.
    case adapterMergeFailed(reason: String)

    /// Tools were passed to a model that cannot call them.
    ///
    /// Failing loudly is the point. If the tools were dropped silently the model would answer from
    /// its own knowledge, and an agent loop would read that as "no tool was needed" and end the turn
    /// on an unfounded answer. Recover by retrying without tools or by switching to a tool-capable
    /// model.
    ///
    /// - Parameter modelId: Identifier of the model that has no tool-call support.
    case toolCallsUnsupported(modelId: String)

    /// The record of what has been downloaded is there but could not be read.
    ///
    /// Raised by `ModelRegistry` and `AdapterRegistry` when the registry file exists and will not
    /// read or decode — a truncated write, a permissions change, or entries that no longer match
    /// the current shape of `CachedModelInfo` or `AdapterInfo`. **A registry that was never written
    /// is not this case**: that one reads as an empty registry and no error is raised.
    ///
    /// Keeping the two apart is the whole point, because they call for opposite responses. Nothing
    /// registered means offer the download. Unreadable means the models may well be on disk
    /// already, and re-downloading would pull gigabytes the device is still holding. Ask
    /// `LocalModelInventory` in the MLX module what is actually on disk instead — it reads the file
    /// system rather than this record.
    ///
    /// The registry refuses every operation, not just the read, while it is in this state. That is
    /// deliberate: each mutating call is a load-mutate-save over the whole file, so one that
    /// treated an unreadable registry as empty would write that emptiness over a file still
    /// recoverable by hand, and orphan the model directories the lost entries pointed at. Nothing
    /// is cached from the failure, so the next call reads again and succeeds once the file is
    /// repaired or removed.
    ///
    /// - Parameter reason: Message from the persistence layer, meant for logs rather than the user.
    case registryUnreadable(reason: String)
}

// MARK: - LocalizedError

extension LLMLocalError: LocalizedError {
    /// Sentence describing the failure, including the identifiers and byte counts it carries.
    ///
    /// Without the `LocalizedError` conformance, `localizedDescription` degrades to
    /// "...LLMLocalError error N." and every associated value — the model id, the downloader's
    /// reason string — is lost at exactly the moment someone is trying to read the error. The text
    /// is English and is not localized, so treat it as developer-facing copy for logs and build
    /// your own strings for anything a user reads.
    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let modelId, let reason):
            "Failed to download model '\(modelId)': \(reason)"
        case .loadFailed(let modelId, let reason):
            "Failed to load model '\(modelId)': \(reason)"
        case .modelNotLoaded:
            "No model is loaded."
        case .loadInProgress:
            "A model load is already in progress."
        case .cancelled:
            "The operation was cancelled."
        case .adapterMergeFailed(let reason):
            "Failed to merge the adapter: \(reason)"
        case .toolCallsUnsupported(let modelId):
            "Model '\(modelId)' does not support tool calls."
        case .registryUnreadable(let reason):
            "The registry of downloaded items could not be read: \(reason)"
        }
    }
}
