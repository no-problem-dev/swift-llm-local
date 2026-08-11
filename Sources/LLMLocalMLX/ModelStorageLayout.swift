import Foundation
import HuggingFace
import LLMLocalClient

/// The one definition of where models live on disk and what counts as a complete download.
///
/// Path derivation and completeness checking live here so the writer
/// (``DestinationHubDownloader``) and the reader (``LocalModelInventory``) cannot drift apart. If
/// they did, a model that downloaded successfully would read as missing and be downloaded again.
enum ModelStorageLayout {

    /// The root models are stored under, creating it if needed.
    ///
    /// Application Support, not caches. The caches directory is the obvious home for
    /// re-downloadable data, but iOS purges it under storage pressure at times of its choosing,
    /// which would delete multi-gigabyte weights out from under a loaded model. Application
    /// Support is never purged, and the directory is instead flagged as excluded from iCloud and
    /// iTunes backup, which is what the App Store guidelines require of large re-downloadable
    /// files.
    ///
    /// If Application Support cannot be located, the temporary directory is used, and that one
    /// the system can reclaim — downloads may then not survive between launches.
    static func defaultBaseDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var base = support.appendingPathComponent("swift-llm-local/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Multi-gigabyte models can be fetched again, so keep them out of iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        return base
    }

    /// Storage directory for a Hugging Face repository, nested by namespace then repository name.
    static func destination(for repoID: Repo.ID, base: URL) -> URL {
        base
            .appendingPathComponent(repoID.namespace, isDirectory: true)
            .appendingPathComponent(repoID.name, isDirectory: true)
    }

    /// Local directory for a model spec.
    ///
    /// A `.huggingFace` spec maps under `base`; a `.local` spec is its own path. Returns `nil`
    /// when the Hub identifier is not in `namespace/name` form, which the caller reads as
    /// "not downloaded".
    static func directory(for spec: ModelSpec, base: URL) -> URL? {
        switch spec.base {
        case .huggingFace(let id):
            guard let repoID = Repo.ID(rawValue: id) else { return nil }
            return destination(for: repoID, base: base)
        case .local(let path):
            return path
        }
    }

    /// Whether the directory holds both a configuration and weights.
    ///
    /// Accepts single-file weights (`*.safetensors`) and sharded weights
    /// (`*.safetensors.index.json`). The check is presence-only: it does not verify that every
    /// shard listed in the index actually arrived, so a download interrupted between shards can
    /// still pass and fail later at load time.
    static func hasCompleteSnapshot(at directory: URL) -> Bool {
        let fileManager = FileManager.default
        let config = directory.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: config.path) else { return false }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return contents.contains { name in
            name.hasSuffix(".safetensors") || name.hasSuffix(".safetensors.index.json")
        }
    }

    /// Total bytes under the directory, walked recursively, or nothing if it does not exist.
    ///
    /// Prefers allocated size over file size, so the number matches what the device reports as
    /// storage used.
    static func directorySize(at directory: URL) -> Int64? {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [],
            errorHandler: nil
        ) else { return nil }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            if let allocated = values?.totalFileAllocatedSize {
                total += Int64(allocated)
            } else if let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// The directory's modification date, used as an approximation of when the download finished.
    static func modificationDate(at directory: URL) -> Date? {
        let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}
