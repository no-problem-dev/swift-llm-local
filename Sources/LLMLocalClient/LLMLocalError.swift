/// Errors that can occur during local LLM operations.
public enum LLMLocalError: Error, Sendable, Equatable {
    /// Model download failed.
    /// - Parameters:
    ///   - modelId: Identifier of the model that failed to download.
    ///   - reason: Human-readable description of the failure.
    case downloadFailed(modelId: String, reason: String)

    /// Model loading failed.
    /// - Parameters:
    ///   - modelId: Identifier of the model that failed to load.
    ///   - reason: Human-readable description of the failure.
    case loadFailed(modelId: String, reason: String)

    /// Insufficient device memory to load the model.
    /// - Parameters:
    ///   - required: Number of bytes required.
    ///   - available: Number of bytes available.
    case insufficientMemory(required: Int, available: Int)

    /// Insufficient storage to download the model.
    /// - Parameters:
    ///   - required: Number of bytes required.
    ///   - available: Number of bytes available.
    case insufficientStorage(required: Int64, available: Int64)

    /// No model is currently loaded.
    case modelNotLoaded

    /// A model load operation is already in progress.
    case loadInProgress

    /// The operation was cancelled.
    case cancelled

    /// LoRA/QLoRA adapter merge failed.
    /// - Parameter reason: Human-readable description of the failure.
    case adapterMergeFailed(reason: String)

    /// The model format is not supported.
    /// - Parameter format: Description of the unsupported format.
    case unsupportedModelFormat(String)
}
