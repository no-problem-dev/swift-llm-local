import Foundation
import LLMLocalClient

/// Lists, measures, and deletes the models already on disk.
///
/// Every answer comes from reading the filesystem locations ``DestinationHubDownloader`` writes
/// to, never from an in-memory registry, so "is this downloaded" stays correct when nothing is
/// loaded and across app launches. That matters because these are multi-gigabyte files the user
/// may also have removed through iOS storage management.
///
/// ## Usage
///
/// ## A directory that will not read is not an absent model
///
/// Every answer here is a file system read, and a read can fail for reasons that have nothing to do
/// with whether the model is there — a permissions change, a volume that went away. Those throw
/// ``LLMLocalError/storageUnreadable(path:reason:)`` rather than answering "not downloaded" or
/// "zero bytes". Answering would send the caller off to re-fetch gigabytes the device is still
/// holding, or show a storage figure that understates what deleting the model would actually
/// reclaim. Only a directory that genuinely is not there reads as not downloaded.
///
/// ## Usage
///
/// ```swift
/// let inventory = try LocalModelInventory()
/// let downloaded = try inventory.downloadedModels(among: ModelPresets.all)
/// if try inventory.isDownloaded(ModelPresets.qwen3_5_2B) { /* offer it for selection */ }
/// try inventory.delete(ModelPresets.qwen3_5_2B)  // reclaim the storage
/// ```
public struct LocalModelInventory: Sendable {

    private let baseDirectory: URL

    /// - Parameter baseDirectory: Root the models were downloaded into. Pass `nil` for the
    ///   default, which is where ``DestinationHubDownloader`` writes; pass the same custom root
    ///   here if the downloader was given one, or every model reads as missing.
    /// - Throws: When `baseDirectory` is `nil` and the default root cannot be established — see
    ///   `ModelStorageLayout.defaultBaseDirectory()`.
    public init(baseDirectory: URL? = nil) throws {
        self.baseDirectory = try baseDirectory ?? ModelStorageLayout.defaultBaseDirectory()
    }

    /// Whether the model is on disk complete enough to load.
    ///
    /// True only when both the configuration and the weights are present, so a download
    /// interrupted partway reads as not downloaded rather than loading and failing.
    ///
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when the model's directory is
    ///   there but cannot be read. `false` therefore means the model is absent or incomplete, never
    ///   that the question could not be answered.
    public func isDownloaded(_ spec: ModelSpec) throws -> Bool {
        guard let dir = ModelStorageLayout.directory(for: spec, base: baseDirectory) else {
            return false
        }
        return try ModelStorageLayout.snapshotState(at: dir) == .complete
    }

    /// Returns the candidates that are on disk, newest download first.
    ///
    /// Each result carries its real size on disk and an approximate download time taken from the
    /// directory's modification date. Candidates have to be supplied because snapshots are stored
    /// under their Hub repository path, which cannot be mapped back to the app's model IDs — the
    /// directory tree alone cannot be enumerated into `ModelSpec` values.
    ///
    /// - Parameter specs: The model specs to look for, typically the app's presets.
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when any candidate's directory
    ///   is there but cannot be read or measured. A short list is never how that is reported.
    public func downloadedModels(among specs: [ModelSpec]) throws -> [DownloadedModel] {
        try specs.compactMap { spec -> DownloadedModel? in
            guard let dir = ModelStorageLayout.directory(for: spec, base: baseDirectory),
                  try ModelStorageLayout.snapshotState(at: dir) == .complete,
                  let size = try ModelStorageLayout.directorySize(at: dir)
            else { return nil }
            return DownloadedModel(
                modelId: spec.id,
                directory: dir,
                sizeInBytes: size,
                downloadedAt: try ModelStorageLayout.modificationDate(at: dir)
            )
        }
        .sorted { ($0.downloadedAt ?? .distantPast) > ($1.downloadedAt ?? .distantPast) }
    }

    /// Size of the model on disk in bytes, absent when it is not fully downloaded.
    ///
    /// Measured by walking the directory, so it reflects allocated size rather than the sum the
    /// Hub advertises.
    ///
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when the directory is there but
    ///   cannot be read or measured. `nil` means the model is not fully downloaded, never that its
    ///   size could not be determined.
    public func diskSize(of spec: ModelSpec) throws -> Int64? {
        guard let dir = ModelStorageLayout.directory(for: spec, base: baseDirectory),
              try ModelStorageLayout.snapshotState(at: dir) == .complete
        else { return nil }
        return try ModelStorageLayout.directorySize(at: dir)
    }

    /// Total bytes the downloaded candidates occupy on disk.
    ///
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when any candidate cannot be
    ///   measured. Zero means nothing is downloaded; it is never a partial sum.
    public func totalDiskSize(among specs: [ModelSpec]) throws -> Int64 {
        try downloadedModels(among: specs).reduce(0) { $0 + $1.sizeInBytes }
    }

    /// Deletes the model's downloaded files to reclaim storage.
    ///
    /// Does nothing for a model that is not downloaded, and nothing for a `.local` spec: those
    /// files belong to whoever supplied the path. Deleting a model that is currently loaded is
    /// allowed and does not unload it — the weights are already in memory.
    ///
    /// - Throws: If removing the directory fails.
    public func delete(_ spec: ModelSpec) throws {
        // Never delete an externally owned `.local` model; those files are not ours to remove.
        guard case .huggingFace = spec.base,
              let dir = ModelStorageLayout.directory(for: spec, base: baseDirectory),
              FileManager.default.fileExists(atPath: dir.path)
        else { return }
        try FileManager.default.removeItem(at: dir)
    }
}
