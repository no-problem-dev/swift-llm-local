import Foundation
import LLMLocalClient

/// Manages model cache metadata and provides cache query/cleanup operations.
///
/// `ModelManager` tracks which models have been downloaded and cached locally,
/// storing metadata in a `registry.json` file within the cache directory.
/// The actual model weights are managed by the MLX backend via the Hugging Face
/// Hub cache; this actor only manages the metadata registry.
///
/// ## Phase 1 Scope
///
/// - List cached models
/// - Check if a model is cached
/// - Calculate total cache size
/// - Delete specific model cache metadata
/// - Clear all cache metadata
/// - Register a model (stub for download; actual HF download is MLXBackend's responsibility)
public actor ModelManager {

    /// The directory where the registry file and adapter files are stored.
    private let cacheDirectory: URL

    /// In-memory cache of model metadata, keyed by model ID.
    private var cachedMetadata: [String: CachedModelInfo] = [:]

    /// Internal helper for persisting the registry to disk.
    private let cache: ModelCache

    /// Delegate that performs the actual download work.
    private let downloadDelegate: any DownloadProgressDelegate

    /// The background downloader instance for resumable downloads.
    private let _backgroundDownloader: BackgroundDownloader

    /// The background downloader for managing resumable background downloads.
    ///
    /// Use this to start, pause, resume, or cancel background model downloads
    /// with resume capability.
    public var backgroundDownloader: BackgroundDownloader {
        _backgroundDownloader
    }

    /// Creates a new model manager.
    ///
    /// - Parameters:
    ///   - cacheDirectory: The directory for storing registry and adapter files.
    ///     Defaults to `~/Library/Application Support/LLMLocal/models`.
    ///   - downloadDelegate: An optional delegate for performing downloads.
    ///     When `nil`, a stub delegate is used that simulates an instant download.
    ///   - backgroundDownloader: An optional background downloader instance.
    ///     When `nil`, a default ``BackgroundDownloader`` is created using the cache directory.
    public init(
        cacheDirectory: URL? = nil,
        downloadDelegate: (any DownloadProgressDelegate)? = nil,
        backgroundDownloader: BackgroundDownloader? = nil
    ) {
        let dir = cacheDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("LLMLocal/models")
        self.cacheDirectory = dir
        self.cache = ModelCache(directory: dir)
        self.cachedMetadata = cache.load()
        self.downloadDelegate = downloadDelegate ?? StubDownloadDelegate()
        self._backgroundDownloader = backgroundDownloader
            ?? BackgroundDownloader(
                storageDirectory: dir.appendingPathComponent("bg-downloads")
            )
    }

    // MARK: - Public API

    /// Returns a list of all cached models.
    ///
    /// - Returns: An array of ``CachedModelInfo`` for every registered model.
    public func cachedModels() -> [CachedModelInfo] {
        Array(cachedMetadata.values)
    }

    /// Checks whether the given model specification has a cached entry.
    ///
    /// - Parameter spec: The model specification to check.
    /// - Returns: `true` if the model is registered in the cache.
    public func isCached(_ spec: ModelSpec) -> Bool {
        cachedMetadata[spec.id] != nil
    }

    /// Returns the total size of all cached models in bytes.
    ///
    /// - Returns: The sum of `sizeInBytes` for all registered models.
    /// - Throws: Currently does not throw, but the signature allows for future
    ///   filesystem-based size calculation.
    public func totalCacheSize() throws -> Int64 {
        cachedMetadata.values.reduce(0) { $0 + $1.sizeInBytes }
    }

    /// Removes the cache metadata entry for a specific model.
    ///
    /// If the model is not cached, this method does nothing.
    ///
    /// - Parameter spec: The model specification to remove.
    /// - Throws: An error if the registry cannot be persisted.
    public func deleteCache(for spec: ModelSpec) throws {
        cachedMetadata.removeValue(forKey: spec.id)
        try cache.save(cachedMetadata)
    }

    /// Removes all cached model metadata.
    ///
    /// - Throws: An error if the registry cannot be persisted.
    public func clearAllCache() throws {
        cachedMetadata.removeAll()
        try cache.save(cachedMetadata)
    }

    /// Registers a model in the cache metadata.
    ///
    /// This is a Phase 1 stub. In Phase 2, the actual download will be handled
    /// by the MLX backend. For now, this method creates a metadata entry with
    /// the given size and the current timestamp.
    ///
    /// If a model with the same ID is already registered, it will be overwritten.
    ///
    /// - Parameters:
    ///   - spec: The model specification to register.
    ///   - sizeInBytes: The size of the model in bytes.
    /// - Throws: An error if the registry cannot be persisted.
    public func registerModel(_ spec: ModelSpec, sizeInBytes: Int64) throws {
        let info = CachedModelInfo(
            modelId: spec.id,
            displayName: spec.displayName,
            sizeInBytes: sizeInBytes,
            downloadedAt: Date(),
            localPath: cacheDirectory.appendingPathComponent(spec.id)
        )
        cachedMetadata[spec.id] = info
        try cache.save(cachedMetadata)
    }

    // MARK: - Download with Progress

    /// Downloads a model with progress reporting.
    ///
    /// Returns an `AsyncThrowingStream` that yields ``DownloadProgress`` updates
    /// as the download progresses. The stream completes when the download
    /// finishes and the model is registered in the cache.
    ///
    /// In Phase 2, this wraps the HuggingFace Hub download with progress tracking.
    /// For now, it simulates progress by yielding start (0.0) and completion (1.0)
    /// after registering the model.
    ///
    /// - Parameter spec: The model specification to download.
    /// - Returns: An ``AsyncThrowingStream`` of ``DownloadProgress`` values.
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
