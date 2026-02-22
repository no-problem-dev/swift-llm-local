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

    /// Creates a new model manager.
    ///
    /// - Parameter cacheDirectory: The directory for storing registry and adapter files.
    ///   Defaults to `~/Library/Application Support/LLMLocal/models`.
    public init(cacheDirectory: URL? = nil) {
        let dir = cacheDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("LLMLocal/models")
        self.cacheDirectory = dir
        self.cache = ModelCache(directory: dir)
        self.cachedMetadata = cache.load()
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
}
