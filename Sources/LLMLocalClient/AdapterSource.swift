import Foundation

/// Where a LoRA/QLoRA adapter is fetched from.
///
/// An adapter is fine-tuned weights layered on a base model, small enough to ship separately from
/// it. A source becomes a local file through ``AdapterResolving``, which downloads and caches remote
/// ones; a backend given a spec with an adapter but no resolver fails the load.
public enum AdapterSource: Sendable, Hashable, Codable {
    /// Adapter published as an asset on a GitHub release.
    ///
    /// The release tag doubles as the cache version: a cached copy is reused while the tag matches
    /// and re-downloaded when it changes, so moving a tag to new bytes does not invalidate anything
    /// already on disk.
    ///
    /// - Parameters:
    ///   - repo: Repository in `owner/name` form.
    ///   - tag: Release tag, such as "v1.0".
    ///   - asset: File name of the asset within that release.
    case gitHubRelease(repo: String, tag: String, asset: String)

    /// Adapter hosted on the Hugging Face Hub, downloaded and cached on first use.
    ///
    /// - Parameter id: Repository id of the adapter.
    case huggingFace(id: String)

    /// Adapter already on disk, used from that directory without copying.
    ///
    /// Resolution only checks that the path exists, so a missing file is reported as
    /// ``LLMLocalError/adapterMergeFailed(reason:)`` at load time.
    ///
    /// - Parameter path: Directory holding the adapter weights.
    case local(path: URL)
}
