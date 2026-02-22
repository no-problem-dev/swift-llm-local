import Foundation

/// Specifies where a base model's weights are located.
public enum ModelSource: Sendable, Hashable, Codable {
    /// A model hosted on the Hugging Face Hub.
    /// - Parameter id: The Hugging Face model identifier (e.g. "mlx-community/Llama-3.2-1B-Instruct-4bit").
    case huggingFace(id: String)

    /// A model stored on the local filesystem.
    /// - Parameter path: The file URL pointing to the model directory.
    case local(path: URL)
}
