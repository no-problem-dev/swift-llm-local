import Foundation
import LLMLocalClient
import PersistenceCore
import PersistenceFileSystem

/// Metadata registry for the models an app has downloaded to the device.
///
/// One ``CachedModelInfo`` per model is kept in a JSON file through a ``RegistryStore``. The
/// registry never reads or writes model weights: the MLX backend fetches those and copies the
/// Hugging Face snapshot into `Application Support/swift-llm-local/models/{namespace}/{name}`,
/// which is a different tree from this registry's own directory.
///
/// A model is identified by ``ModelSpec/id``, a string the app picks. It is not the Hugging Face
/// repository id and carries no revision: the backend resolves `main` unless a revision is passed
/// to it, so the same entry can describe different weights once the upstream repository moves.
///
/// "Registered" therefore means an entry exists, not that complete bytes are on disk.
/// ``isCached(_:)`` answers from the JSON file alone. To ask the file system instead, use
/// `LocalModelInventory` in the MLX module, which requires `config.json` plus a `*.safetensors`
/// (or `*.safetensors.index.json`) file before calling a model downloaded.
///
/// ## An unreadable registry is not an empty one
///
/// Every method here reads the registry file on first use, and a file that is there but will not
/// read or decode throws ``LLMLocalError/registryUnreadable(reason:)`` rather than answering with
/// an empty registry. Only a registry that was never written reads as empty.
///
/// The distinction is load-bearing in both directions. Downwards, every mutating method is a
/// load-mutate-save over the whole file: one that treated a corrupt registry as empty would write
/// that emptiness back, destroy a file that was still recoverable by hand, and orphan the model
/// directories the lost entries pointed at — ``deleteCache(for:)`` could never free them again.
/// Upwards, a caller that heard "empty" would offer to download models the device is already
/// holding gigabytes of. Nothing is cached from a failed read, so the next call tries again and
/// succeeds once the file is repaired or removed.
///
/// A download is staged through the Hugging Face cache and then copied into place, so it needs
/// roughly twice the model's size on disk while it runs, and the staged copy is left behind in
/// `Caches`, where the system may purge it.
public actor ModelRegistry {

    /// Directory holding the registry JSON. Neither model weights nor adapter files are written
    /// here.
    private let cacheDirectory: URL

    /// Loaded entries, keyed by ``ModelSpec/id``.
    private var cachedMetadata: [String: CachedModelInfo] = [:]

    /// Whether the store has already been read into memory.
    private var isLoaded: Bool = false

    /// Backing store for the registry JSON. A missing file reads as an empty registry; one that is
    /// there but will not read or decode throws.
    private let cache: any RegistryStore<CachedModelInfo>

    /// Performs the transfer for ``downloadWithProgress(_:)``.
    private let downloadDelegate: any DownloadProgressDelegate

    /// Backing storage for ``backgroundDownloader``.
    private let _backgroundDownloader: BackgroundDownloader?

    /// Pause and resume bookkeeping for downloads the app drives itself, when one was injected.
    ///
    /// `nil` unless the app supplied a downloader: a ``BackgroundDownloader`` needs a delegate that
    /// actually moves bytes, and the registry has none to give it. Not involved in
    /// ``downloadWithProgress(_:)``, which goes through the download delegate instead.
    public var backgroundDownloader: BackgroundDownloader? {
        _backgroundDownloader
    }

    /// Creates a registry backed by a JSON file.
    ///
    /// - Parameters:
    ///   - cacheDirectory: Directory for the registry JSON. Defaults to
    ///     `~/Library/Application Support/LLMLocal/models`. Model files are not written here.
    ///   - registryStore: Persistence for the entries. When `nil`, `registry.json` inside the
    ///     cache directory is used.
    ///   - downloadDelegate: Performs the transfer in ``downloadWithProgress(_:)``. When `nil`, a
    ///     stub reports a fixed 1 MB size and moves no bytes.
    ///   - backgroundDownloader: Pause and resume bookkeeping, exposed as-is through
    ///     ``backgroundDownloader``. When `nil` that property stays `nil`; nothing is created on
    ///     the caller's behalf.
    public init(
        cacheDirectory: URL? = nil,
        registryStore: (any RegistryStore<CachedModelInfo>)? = nil,
        downloadDelegate: (any DownloadProgressDelegate)? = nil,
        backgroundDownloader: BackgroundDownloader? = nil
    ) {
        let dir = cacheDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("LLMLocal/models")
        self.cacheDirectory = dir
        self.cache = registryStore
            ?? FileSystemRegistryStore<CachedModelInfo>(directory: dir)
        self.downloadDelegate = downloadDelegate ?? StubDownloadDelegate()
        self._backgroundDownloader = backgroundDownloader
    }

    // MARK: - Private Helpers

    /// Reads the store into memory on first use; later calls return immediately.
    ///
    /// A read that fails leaves the registry unloaded rather than empty, so the caller's operation
    /// stops here — before any save could overwrite the file it could not read — and a later call
    /// reads again.
    ///
    /// - Throws: ``LLMLocalError/registryUnreadable(reason:)`` when the registry file exists but
    ///   will not read or decode.
    private func ensureLoaded() async throws {
        guard !isLoaded else { return }
        do {
            cachedMetadata = try await cache.load()
        } catch {
            throw LLMLocalError.registryUnreadable(reason: error.localizedDescription)
        }
        isLoaded = true
    }

    // MARK: - Public API

    /// Every registered model, in no particular order.
    ///
    /// Reads the registry file on the first call. An empty array means nothing is registered, and
    /// is never how an unreadable registry is reported.
    ///
    /// - Throws: ``LLMLocalError/registryUnreadable(reason:)`` when the registry file exists but
    ///   will not read or decode.
    public func cachedModels() async throws -> [CachedModelInfo] {
        try await ensureLoaded()
        return Array(cachedMetadata.values)
    }

    /// Reports whether a model has a registry entry.
    ///
    /// This is answered from the registry alone, so an entry outlives its files when they are
    /// deleted from underneath it. Ask `LocalModelInventory` in the MLX module when the question
    /// is whether usable weights are on disk.
    ///
    /// - Parameter spec: Model to look up by ``ModelSpec/id``.
    /// - Returns: `true` when an entry exists. `false` means the registry was read and holds no
    ///   entry for this model, not that the registry could not be consulted.
    /// - Throws: ``LLMLocalError/registryUnreadable(reason:)`` when the registry file exists but
    ///   will not read or decode.
    public func isCached(_ spec: ModelSpec) async throws -> Bool {
        try await ensureLoaded()
        return cachedMetadata[spec.id] != nil
    }

    /// Sum of the sizes recorded for the registered models, in bytes.
    ///
    /// The numbers are whatever was passed to
    /// ``registerModel(_:sizeInBytes:modelFilesPath:)``; nothing is measured on disk, so entries
    /// whose files are gone still count, and files not covered by an entry never do.
    ///
    /// - Throws: ``LLMLocalError/registryUnreadable(reason:)`` when the registry file exists but
    ///   will not read or decode. Zero therefore means nothing is registered, not that the sizes
    ///   could not be found.
    public func totalCacheSize() async throws -> Int64 {
        try await ensureLoaded()
        return cachedMetadata.values.reduce(0) { $0 + $1.sizeInBytes }
    }

    /// Removes a model's registry entry, and its files when the entry recorded a path.
    ///
    /// Files are deleted only when the entry carries a `modelFilesPath`. Entries created by
    /// ``downloadWithProgress(_:)`` never do, so for those this frees no disk space and the bytes
    /// are left orphaned. A failure to remove the directory is ignored; only saving the registry
    /// can throw.
    ///
    /// Evicting a model that a backend currently has loaded does not disturb generation in the
    /// running process — the next load simply has to download the model again.
    ///
    /// - Parameter spec: Model to remove. An unregistered model still triggers a registry save.
    /// - Throws: ``LLMLocalError/registryUnreadable(reason:)`` when the registry cannot be read, in
    ///   which case nothing is deleted and nothing is written; otherwise when the registry file
    ///   cannot be written.
    public func deleteCache(for spec: ModelSpec) async throws {
        try await ensureLoaded()
        if let info = cachedMetadata[spec.id], let filesPath = info.modelFilesPath {
            try? FileManager.default.removeItem(at: filesPath)
        }
        cachedMetadata.removeValue(forKey: spec.id)
        try await cache.save(cachedMetadata)
    }

    /// Removes every registry entry, and the files of the entries that recorded a path.
    ///
    /// Same caveat as ``deleteCache(for:)``: entries without a `modelFilesPath` leave their bytes
    /// on disk with nothing left to point at them.
    ///
    /// - Throws: ``LLMLocalError/registryUnreadable(reason:)`` when the registry cannot be read, in
    ///   which case no files are deleted and nothing is written; otherwise when the registry file
    ///   cannot be written.
    public func clearAllCache() async throws {
        try await ensureLoaded()
        for info in cachedMetadata.values {
            if let filesPath = info.modelFilesPath {
                try? FileManager.default.removeItem(at: filesPath)
            }
        }
        cachedMetadata.removeAll()
        try await cache.save(cachedMetadata)
    }

    /// Records a model as downloaded.
    ///
    /// The entry for ``ModelSpec/id`` is inserted or overwritten with the given size and the
    /// current time. Nothing is verified: no file is opened and the size is taken on trust. Pass
    /// `modelFilesPath` if the entry should ever be able to free disk space, because
    /// ``deleteCache(for:)`` deletes nothing without it.
    ///
    /// The entry's `localPath` is derived as `cacheDirectory/{id}`. That directory is not created
    /// and is not where the weights live.
    ///
    /// - Parameters:
    ///   - spec: Model to record.
    ///   - sizeInBytes: Size to record, in bytes.
    ///   - modelFilesPath: Directory holding the downloaded files, deleted on eviction.
    /// - Throws: ``LLMLocalError/registryUnreadable(reason:)`` when the registry cannot be read, in
    ///   which case nothing is recorded and the unreadable file is left as it was rather than
    ///   replaced by a registry holding this entry alone; otherwise when the registry file cannot
    ///   be written.
    public func registerModel(
        _ spec: ModelSpec,
        sizeInBytes: Int64,
        modelFilesPath: URL? = nil
    ) async throws {
        try await ensureLoaded()
        let info = CachedModelInfo(
            modelId: spec.id,
            displayName: spec.displayName,
            sizeInBytes: sizeInBytes,
            downloadedAt: Date(),
            localPath: cacheDirectory.appendingPathComponent(spec.id),
            modelFilesPath: modelFilesPath
        )
        cachedMetadata[spec.id] = info
        try await cache.save(cachedMetadata)
    }

    // MARK: - Download with Progress

    /// Downloads a model through the download delegate and reports progress as a stream.
    ///
    /// The stream yields a zero value immediately, then whatever the delegate reports, then a full
    /// value once the model has been registered. Delegate progress is forwarded verbatim, produced
    /// on whatever context the delegate calls back from rather than on this actor — the Hugging
    /// Face downloader used by the MLX backend reports on the main actor, for instance — and
    /// arrives on the task that iterates the stream.
    ///
    /// The transfer runs in an unstructured task the stream does not own, and no termination
    /// handler is installed. Abandoning the stream, or cancelling the task iterating it, therefore
    /// does not stop the transfer, and the model may still be registered afterwards. Registration
    /// is skipped silently if the registry is deallocated mid-download, in which case the stream
    /// still finishes with a full-progress value.
    ///
    /// The entry it registers has no `modelFilesPath`, so ``deleteCache(for:)`` will not free the
    /// downloaded bytes afterwards. Byte counts come from the delegate; the default stub reports a
    /// fixed 1 MB and transfers nothing.
    ///
    /// Registration is the last step, so an unreadable registry fails the stream with
    /// ``LLMLocalError/registryUnreadable(reason:)`` *after* the bytes have already been fetched.
    /// The download is not wasted — the files are where the delegate put them — but nothing records
    /// them, so read the registry before starting a download the caller cannot afford to repeat.
    ///
    /// - Parameter spec: Model to download.
    /// - Returns: A stream that finishes once the model is registered, or fails with the
    ///   delegate's error and registers nothing.
    public func downloadWithProgress(
        _ spec: ModelSpec
    ) -> AsyncThrowingStream<DownloadProgress, Error> {
        let delegate = self.downloadDelegate

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                do {
                    try Task.checkCancellation()

                    // Yield initial progress
                    continuation.yield(DownloadProgress(
                        fraction: 0.0,
                        completedBytes: 0,
                        totalBytes: 0,
                        currentFile: nil
                    ))

                    try Task.checkCancellation()

                    // Perform download via delegate
                    let sizeInBytes = try await delegate.download(spec) { progress in
                        continuation.yield(progress)
                    }

                    try Task.checkCancellation()

                    // Register model in cache
                    if let self = self {
                        try await self.registerModel(spec, sizeInBytes: sizeInBytes)
                    }

                    // Yield completion
                    continuation.yield(DownloadProgress(
                        fraction: 1.0,
                        completedBytes: sizeInBytes,
                        totalBytes: sizeInBytes,
                        currentFile: nil
                    ))

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
