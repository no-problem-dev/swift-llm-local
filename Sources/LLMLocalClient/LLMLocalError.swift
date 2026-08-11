import Foundation

/// Failures raised while downloading, loading, or generating with an on-device model.
///
/// The cases divide into three groups by what the caller should do. Retrying the same call can
/// work for ``downloadFailed(modelId:reason:)`` and ``loadInProgress``. Retrying is pointless until
/// something changes for ``loadFailed(modelId:reason:)``, ``adapterMergeFailed(reason:)``,
/// ``unsupportedModelFormat(_:)``, ``insufficientMemory(required:available:)``, and
/// ``insufficientStorage(required:available:)`` — free memory or disk, fix the spec, or offer a
/// smaller model. ``modelNotLoaded`` and ``toolCallsUnsupported(modelId:)`` are caller mistakes to
/// fix in code, and ``cancelled`` is not a failure at all.
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

    /// The device does not have enough memory to hold the model.
    ///
    /// Backends in this package do not raise it — an out-of-memory load surfaces as
    /// ``loadFailed(modelId:reason:)`` — because the check belongs before the load. Ask the memory
    /// monitor whether a spec fits and offer a smaller one instead of starting a load that will die.
    ///
    /// - Parameters:
    ///   - required: Bytes the model needs.
    ///   - available: Bytes the process may still use.
    case insufficientMemory(required: Int, available: Int)

    /// There is not enough free disk space to store the model's weights.
    ///
    /// Reserved for downloaders that check before they start; nothing in this package raises it
    /// today. Recovery is user action — free space or pick a smaller model — not a retry.
    ///
    /// - Parameters:
    ///   - required: Bytes the download needs.
    ///   - available: Bytes free on the volume.
    case insufficientStorage(required: Int64, available: Int64)

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

    /// The weights are in a format the runtime cannot read.
    ///
    /// Reserved for backends that inspect the format before loading; the MLX backend reports the
    /// same situation as ``loadFailed(modelId:reason:)``. Not recoverable — the model has to be
    /// converted or replaced.
    ///
    /// - Parameter format: The format that was found.
    case unsupportedModelFormat(String)

    /// Tools were passed to a model that cannot call them.
    ///
    /// Failing loudly is the point. If the tools were dropped silently the model would answer from
    /// its own knowledge, and an agent loop would read that as "no tool was needed" and end the turn
    /// on an unfounded answer. Recover by retrying without tools or by switching to a tool-capable
    /// model.
    ///
    /// - Parameter modelId: Identifier of the model that has no tool-call support.
    case toolCallsUnsupported(modelId: String)
}

// MARK: - LocalizedError

extension LLMLocalError: LocalizedError {
    /// Sentence describing the failure, including the identifiers and byte counts it carries.
    ///
    /// Without the `LocalizedError` conformance, `localizedDescription` degrades to
    /// "...LLMLocalError error N." and every associated value — the model id, the downloader's
    /// reason string — is lost at exactly the moment someone is trying to read the error. The text
    /// is Japanese and is not localized, so treat it as a message for a Japanese-language UI or for
    /// logs, and build your own copy for anything else.
    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let modelId, let reason):
            "モデル '\(modelId)' のダウンロードに失敗しました: \(reason)"
        case .loadFailed(let modelId, let reason):
            "モデル '\(modelId)' の読み込みに失敗しました: \(reason)"
        case .insufficientMemory(let required, let available):
            "メモリ不足です（必要: \(required) バイト / 利用可能: \(available) バイト）"
        case .insufficientStorage(let required, let available):
            "ストレージ不足です（必要: \(required) バイト / 利用可能: \(available) バイト）"
        case .modelNotLoaded:
            "モデルが読み込まれていません"
        case .loadInProgress:
            "モデルの読み込みが既に進行中です"
        case .cancelled:
            "操作がキャンセルされました"
        case .adapterMergeFailed(let reason):
            "アダプターのマージに失敗しました: \(reason)"
        case .unsupportedModelFormat(let format):
            "サポートされていないモデル形式です: \(format)"
        case .toolCallsUnsupported(let modelId):
            "モデル '\(modelId)' はツールコールに対応していません"
        }
    }
}
