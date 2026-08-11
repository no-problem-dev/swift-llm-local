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
    /// Every step throws rather than handing back a URL that does not do what the caller was
    /// promised. A directory that could not be created is not a place downloads will land, and a
    /// directory whose backup-exclusion flag was refused is one that quietly uploads gigabytes of
    /// re-downloadable weights to iCloud — the exact outcome the flag exists to prevent, and one
    /// nothing else in the system will ever mention.
    ///
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when Application Support cannot
    ///   be located, and the file system's own error when the directory cannot be created or
    ///   excluded from backup.
    static func defaultBaseDirectory() throws -> URL {
        try baseDirectory(under: ApplicationSupportDirectory.url())
    }

    /// The models root under an explicit parent, created and flagged the same way.
    ///
    /// Split out from ``defaultBaseDirectory()`` so the failures — a parent that will not take the
    /// directory, a directory that will not take the flag — can be reached without writing to the
    /// real Application Support.
    ///
    /// - Parameter support: Directory to place the models root under.
    static func baseDirectory(under support: URL) throws -> URL {
        var base = support.appendingPathComponent("swift-llm-local/models", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Multi-gigabyte models can be fetched again, so keep them out of iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try base.setResourceValues(values)
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

    /// What is sitting at a model's directory.
    ///
    /// Three answers, none of which is "I could not tell": a directory that will not read is a
    /// thrown error, not a fourth state dressed up as one of these.
    enum SnapshotState: Sendable, Equatable {
        /// Configuration and weights are both present, so the model can be loaded.
        case complete

        /// Something is there but it is not a loadable model — a download interrupted partway, or
        /// a file where a directory should be.
        case incomplete

        /// Nothing is at the path. The model has not been downloaded.
        case absent
    }

    /// Classifies what is at the directory.
    ///
    /// Accepts single-file weights (`*.safetensors`) and sharded weights
    /// (`*.safetensors.index.json`). The check is presence-only: it does not verify that every
    /// shard listed in the index actually arrived, so a download interrupted between shards can
    /// still read as ``SnapshotState/complete`` and fail later at load time.
    ///
    /// The listing is the only file system read, deliberately: a `fileExists` check on
    /// `config.json` cannot report an error at all, so a directory that denies reads would answer
    /// the same as one that never existed. Distinguishing the two is the whole point here — this
    /// answer gates a multi-gigabyte download in ``DestinationHubDownloader`` and the entire
    /// downloaded-model list in ``LocalModelInventory``.
    ///
    /// - Parameter directory: Directory to classify.
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when the directory is there but
    ///   its contents cannot be listed.
    static func snapshotState(at directory: URL) throws -> SnapshotState {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir) else {
            return .absent
        }
        guard isDir.boolValue else { return .incomplete }

        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw LLMLocalError.storageUnreadable(
                path: directory.path, reason: error.localizedDescription
            )
        }

        let hasConfig = contents.contains("config.json")
        let hasWeights = contents.contains { name in
            name.hasSuffix(".safetensors") || name.hasSuffix(".safetensors.index.json")
        }
        return hasConfig && hasWeights ? .complete : .incomplete
    }

    /// Total bytes under the directory, walked recursively, or nothing if it does not exist.
    ///
    /// Prefers allocated size over file size, so the number matches what the device reports as
    /// storage used.
    ///
    /// A file that will not stat and a subtree that will not enumerate both stop the walk and
    /// throw. Neither may contribute zero and let the walk finish: the result is a number a user
    /// reads as "storage used" and acts on when deciding what to delete, and an understated one is
    /// indistinguishable from an honest one.
    ///
    /// - Parameter directory: Directory to measure.
    /// - Returns: Total bytes, or `nil` when the directory does not exist.
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when any part of the walk fails.
    static func directorySize(at directory: URL) throws -> Int64? {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey
        ]
        let walkFailure = FirstError()
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { url, error in
                walkFailure.record(path: url.path, reason: error.localizedDescription)
                return false
            }
        ) else {
            throw LLMLocalError.storageUnreadable(
                path: directory.path, reason: "The directory could not be enumerated."
            )
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                throw LLMLocalError.storageUnreadable(
                    path: url.path, reason: error.localizedDescription
                )
            }
            // Directories carry no file size of their own; only their contents count.
            guard values.isRegularFile == true else { continue }
            if let allocated = values.totalFileAllocatedSize {
                total += Int64(allocated)
            } else if let size = values.fileSize {
                total += Int64(size)
            } else {
                throw LLMLocalError.storageUnreadable(
                    path: url.path, reason: "The file reported no size."
                )
            }
        }
        if let failure = walkFailure.value { throw failure }
        return total
    }

    /// The directory's modification date, used as an approximation of when the download finished.
    ///
    /// - Parameter directory: Directory to read.
    /// - Returns: The modification date, or `nil` when the file system supplies none for it.
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when the directory cannot be
    ///   read at all, which is not the same as having no date.
    static func modificationDate(at directory: URL) throws -> Date? {
        do {
            return try directory
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        } catch {
            throw LLMLocalError.storageUnreadable(
                path: directory.path, reason: error.localizedDescription
            )
        }
    }
}

// MARK: - FirstError

/// Carries the first error out of an enumerator's error handler.
///
/// `FileManager`'s handler is a closure the enumerator keeps, so the failure it reports cannot be
/// thrown from where it happens or assigned to a local. Passing `nil` for the handler is what the
/// walk used to do, and that is exactly the swallow: unreadable subtrees are skipped and the total
/// comes back short with nothing to say so.
private final class FirstError: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LLMLocalError?

    var value: LLMLocalError? {
        lock.withLock { stored }
    }

    func record(path: String, reason: String) {
        lock.withLock {
            guard stored == nil else { return }
            stored = .storageUnreadable(path: path, reason: reason)
        }
    }
}
