import Foundation
import LLMLocalClient

struct LoadedModelEntry: Sendable {
    let spec: ModelSpec
    var lastAccessed: Date
}

/// Tracks which models are loaded and evicts the least recently used one when the limit is reached.
///
/// Model weights are resident RAM measured in gigabytes, so loading a second model without
/// releasing the first is what gets an app killed. This actor owns that decision: it records what
/// has been loaded and when it was last used, and drops the oldest entry — asking the backend to
/// release memory — before a new model is read from disk. The backend performs the actual load and
/// unload; this type only decides when.
///
/// ## Example
///
/// ```swift
/// let switcher = ModelSwitcher(backend: mlxBackend, maxLoadedModels: 2)
/// try await switcher.ensureLoaded(ModelPresets.qwen3_0_6B)
/// ```
///
/// With the default limit of one, the bookkeeping matches what the machine does: the MLX backend
/// holds exactly one model, and loading another releases the first. Raising the limit widens the
/// bookkeeping without widening the backend — a second model still displaces the first in memory,
/// while this actor keeps reporting both as loaded and ``ensureLoaded(_:)`` returns immediately for
/// a model whose weights are already gone.
public actor ModelSwitcher {

    /// Number of models tracked before eviction starts; values above one exceed what the backend holds.
    public nonisolated let maxLoadedModels: Int

    private var loadedModels: [String: LoadedModelEntry] = [:]

    private let backend: any LLMLocalBackend

    /// Creates a switcher over the given backend.
    ///
    /// - Parameters:
    ///   - backend: Inference backend that performs the loads and unloads.
    ///   - maxLoadedModels: How many models to track as loaded before evicting the least recently
    ///     used one. The MLX backend can only hold one at a time, so this is the default.
    public init(backend: any LLMLocalBackend, maxLoadedModels: Int = 1) {
        self.backend = backend
        self.maxLoadedModels = maxLoadedModels
    }

    /// Makes sure the model is loaded, evicting the least recently used one if the limit is reached.
    ///
    /// A model that is already tracked is not reloaded; only its access time moves. Otherwise, when
    /// the tracker is at capacity, the least recently used entry is dropped and the backend
    /// releases memory before the new weights are read from disk. Evicting first is the point: it
    /// keeps two sets of weights from being resident at the same moment, which is what the OS kills
    /// an app for.
    ///
    /// - Parameter spec: Model to load.
    /// - Throws: Whatever the backend reports, including a failed download for a model that is not
    ///   on disk yet.
    public func ensureLoaded(_ spec: ModelSpec) async throws {
        try await ensureLoaded(spec, progressHandler: { _ in })
    }

    /// Makes sure the model is loaded, reporting download progress while it is fetched.
    ///
    /// Eviction works exactly as in ``ensureLoaded(_:)``. Progress covers the Hugging Face download
    /// only: a model already on disk completes immediately, and the remaining wait is the load into
    /// memory, which is not reported. An interrupted download keeps what it already fetched and
    /// resumes from there rather than restarting the gigabytes.
    ///
    /// - Parameters:
    ///   - spec: Model to load.
    ///   - progressHandler: Called as the download advances.
    /// - Throws: Whatever the backend reports while downloading or loading.
    public func ensureLoaded(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
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
        try await backend.loadModel(spec, progressHandler: progressHandler)

        // Track the newly loaded model
        loadedModels[spec.id] = LoadedModelEntry(
            spec: spec,
            lastAccessed: Date()
        )
    }

    /// Returns the tracked models, most recently used first.
    public func loadedModelSpecs() -> [ModelSpec] {
        loadedModels.values
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .map(\.spec)
    }

    public func loadedCount() -> Int {
        loadedModels.count
    }

    /// Stops tracking a model and frees its weights if the backend still holds them.
    ///
    /// The backend is only asked to unload when this model is the one it currently has resident, so
    /// forgetting a model that was already displaced does not disturb the live one. Does nothing
    /// for a model that is not tracked.
    ///
    /// - Parameter spec: Model to unload.
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

    /// Clears all tracking and releases the weights the backend is holding.
    ///
    /// Use it to hand the memory back — to another feature, or to survive a memory warning. The
    /// next generation pays a full load again.
    public func unloadAll() async {
        loadedModels.removeAll()
        await backend.unloadModel()
    }

    /// Reports whether the model is tracked as loaded.
    ///
    /// This is the tracker's view, not the backend's. With a limit above one it can answer `true`
    /// for a model whose weights the backend has already displaced.
    ///
    /// - Parameter spec: Model to check.
    public func isLoaded(_ spec: ModelSpec) -> Bool {
        loadedModels[spec.id] != nil
    }

    // MARK: - Private

    /// Drops the least recently used entry and asks the backend to release its resident model.
    ///
    /// The backend has no per-model unload — it releases whatever it is currently holding. With the
    /// default limit of one tracked model these are the same model; with a larger limit, the entry
    /// that is forgotten and the weights that are freed can be different models.
    private func evictLRU() async {
        guard let lruEntry = loadedModels.values.min(by: { $0.lastAccessed < $1.lastAccessed }) else {
            return
        }
        loadedModels.removeValue(forKey: lruEntry.spec.id)
        await backend.unloadModel()
    }
}
