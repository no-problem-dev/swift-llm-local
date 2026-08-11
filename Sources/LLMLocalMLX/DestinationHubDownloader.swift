import Foundation
import HuggingFace
import LLMLocalClient
import MLXLMCommon

/// Downloads Hugging Face snapshots into an app-owned directory with an explicit destination.
///
/// ## Why not the stock downloader
///
/// The cache path used by mlx-swift-lm's `#hubDownloader()` — swift-huggingface's
/// `downloadSnapshot(returnCachePath: true)` — fails inside the iOS sandbox: resolving the cached
/// path of a large LFS file such as `model.safetensors` under `Caches/huggingface/hub` throws
/// `cachedPathResolutionFailed`, so no model can be loaded on device at all.
///
/// The explicit-destination overload, `downloadSnapshot(to:)`, falls back to moving the files into
/// the destination when cache resolution fails, so it does not throw. The cost is that the Hub's
/// own cache bookkeeping no longer applies, so this type decides for itself whether a model is
/// already downloaded by inspecting the destination directory.
public struct DestinationHubDownloader: Downloader {
    private let hub: HubClient
    private let baseDirectory: URL

    /// - Parameters:
    ///   - hub: Hugging Face Hub client. The default is anonymous access, which is enough for
    ///     public model repositories.
    ///   - baseDirectory: Root to place models under. The default is under Application Support,
    ///     excluded from backup — see `ModelStorageLayout`. A custom root must be passed to
    ///     ``LocalModelInventory`` as well, or downloaded models read as missing.
    /// - Throws: When `baseDirectory` is `nil` and the default root cannot be established — see
    ///   `ModelStorageLayout.defaultBaseDirectory()`.
    public init(hub: HubClient = HubClient(), baseDirectory: URL? = nil) throws {
        self.hub = hub
        self.baseDirectory = try baseDirectory ?? ModelStorageLayout.defaultBaseDirectory()
    }

    /// Fetches the repository files matching the patterns and returns the local directory.
    ///
    /// A complete snapshot already on disk is returned without touching the network, reporting a
    /// single completed progress value; passing `useLatest` forces the download anyway. A transfer
    /// failure is reported as `LLMLocalError.downloadFailed(modelId:reason:)`, as is an identifier
    /// that is not in `namespace/name` form.
    ///
    /// If the destination directory is there but cannot be read, this throws
    /// `LLMLocalError.storageUnreadable(path:reason:)` instead of downloading. Treating that as
    /// "not downloaded" is what pulls the whole model down again over the copy already on disk, and
    /// these are multi-gigabyte transfers on a device the user is paying for bandwidth on.
    ///
    /// - Parameters:
    ///   - id: Hub repository identifier, as `namespace/name`.
    ///   - revision: Branch, tag, or commit. Defaults to `main` when `nil`.
    ///   - patterns: Glob patterns selecting which files to fetch.
    ///   - useLatest: Skip the on-disk check and re-fetch from the Hub.
    ///   - progressHandler: Receives download progress; called on the main actor.
    public func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: id) else {
            throw LLMLocalError.downloadFailed(modelId: id, reason: "Invalid repository id: \(id)")
        }

        let destination = ModelStorageLayout.destination(for: repoID, base: baseDirectory)

        // Skip the download when a complete snapshot is already present, unless useLatest is set.
        if !useLatest, try ModelStorageLayout.snapshotState(at: destination) == .complete {
            let progress = Progress(totalUnitCount: 1)
            progress.completedUnitCount = 1
            progressHandler(progress)
            return destination
        }

        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        do {
            return try await hub.downloadSnapshot(
                of: repoID,
                to: destination,
                revision: revision ?? "main",
                matching: patterns,
                progressHandler: { @MainActor progress in progressHandler(progress) }
            )
        } catch {
            throw LLMLocalError.downloadFailed(modelId: id, reason: "\(error)")
        }
    }

}
