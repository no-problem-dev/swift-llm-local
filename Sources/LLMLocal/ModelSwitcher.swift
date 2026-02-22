import Foundation
import LLMLocalClient

/// Internal entry tracking a loaded model.
struct LoadedModelEntry: Sendable {
    let spec: ModelSpec
    var lastAccessed: Date
}

/// Manages loaded models with LRU eviction strategy.
///
/// Tracks which models are loaded and their last access time.
/// When the maximum capacity is reached, the least recently used
/// model is evicted before loading a new one.
///
/// ## Usage
///
/// ```swift
/// let switcher = ModelSwitcher(backend: mlxBackend, maxLoadedModels: 2)
/// try await switcher.ensureLoaded(ModelPresets.gemma2B)
/// ```
///
/// With `maxLoadedModels: 1` (the default), the behavior is identical
/// to the current system where only one model can be loaded at a time.
/// The backend's `loadModel` handles the actual model loading, while
/// the switcher manages LRU tracking and eviction decisions.
public actor ModelSwitcher {

    /// Maximum number of models that can be loaded simultaneously.
    public nonisolated let maxLoadedModels: Int

    /// Internal tracking of loaded models with access timestamps.
    private var loadedModels: [String: LoadedModelEntry] = [:]

    /// The backend used for loading/unloading models.
    private let backend: any LLMLocalBackend

    /// Creates a new model switcher.
    ///
    /// - Parameters:
    ///   - backend: The inference backend to use for model loading and unloading.
    ///   - maxLoadedModels: Maximum number of models that can be loaded simultaneously.
    ///     Defaults to `1`.
    public init(backend: any LLMLocalBackend, maxLoadedModels: Int = 1) {
        self.backend = backend
        self.maxLoadedModels = maxLoadedModels
    }

    /// Ensures the specified model is loaded, evicting LRU if at capacity.
    ///
    /// If the model is already loaded, its access time is updated without
    /// reloading. If the cache is at capacity, the least recently used model
    /// is evicted before loading the new one.
    ///
    /// - Parameter spec: The model specification to load.
    /// - Throws: An error if the backend cannot load the model.
    public func ensureLoaded(_ spec: ModelSpec) async throws {
        // If model is already tracked, just update its access time
        if loadedModels[spec.id] != nil {
            loadedModels[spec.id]?.lastAccessed = Date()
            return
        }

        // If at capacity, evict the least recently used model
        if loadedModels.count >= maxLoadedModels {
            await evictLRU()
        }

        // Load the model via backend
        try await backend.loadModel(spec)

        // Track the newly loaded model
        loadedModels[spec.id] = LoadedModelEntry(
            spec: spec,
            lastAccessed: Date()
        )
    }

    /// Returns the currently loaded model specs, sorted by most recently accessed first.
    ///
    /// - Returns: An array of model specs ordered by access time (most recent first).
    public func loadedModelSpecs() -> [ModelSpec] {
        loadedModels.values
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .map(\.spec)
    }

    /// Returns how many models are currently loaded.
    ///
    /// - Returns: The count of currently tracked models.
    public func loadedCount() -> Int {
        loadedModels.count
    }

    /// Unloads a specific model.
    ///
    /// If the model is currently the active model in the backend,
    /// the backend is also asked to unload. If the model is not loaded,
    /// this method does nothing.
    ///
    /// - Parameter spec: The model specification to unload.
    public func unload(_ spec: ModelSpec) async {
        guard loadedModels.removeValue(forKey: spec.id) != nil else {
            return
        }
        // If this is the currently loaded backend model, unload it
        let currentModel = await backend.currentModel
        if currentModel == spec {
            await backend.unloadModel()
        }
    }

    /// Unloads all models.
    ///
    /// Clears all tracked models and asks the backend to unload
    /// any currently loaded model.
    public func unloadAll() async {
        loadedModels.removeAll()
        await backend.unloadModel()
    }

    /// Whether the specified model is currently loaded.
    ///
    /// - Parameter spec: The model specification to check.
    /// - Returns: `true` if the model is currently tracked as loaded.
    public func isLoaded(_ spec: ModelSpec) -> Bool {
        loadedModels[spec.id] != nil
    }

    // MARK: - Private

    /// Evicts the least recently used model from the cache.
    ///
    /// Removes the LRU entry from tracking and asks the backend to unload
    /// the currently loaded model so the next model can be loaded cleanly.
    private func evictLRU() async {
        guard let lruEntry = loadedModels.values.min(by: { $0.lastAccessed < $1.lastAccessed }) else {
            return
        }
        loadedModels.removeValue(forKey: lruEntry.spec.id)
        await backend.unloadModel()
    }
}
