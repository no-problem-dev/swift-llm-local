import Foundation

/// Specifies where a LoRA/QLoRA adapter is located.
public enum AdapterSource: Sendable, Hashable, Codable {
    /// An adapter distributed as a GitHub release asset.
    /// - Parameters:
    ///   - repo: The GitHub repository (e.g. "owner/repo").
    ///   - tag: The release tag (e.g. "v1.0").
    ///   - asset: The asset filename (e.g. "adapter.safetensors").
    case gitHubRelease(repo: String, tag: String, asset: String)

    /// An adapter hosted on the Hugging Face Hub.
    /// - Parameter id: The Hugging Face model/adapter identifier.
    case huggingFace(id: String)

    /// An adapter stored on the local filesystem.
    /// - Parameter path: The file URL pointing to the adapter directory.
    case local(path: URL)
}
