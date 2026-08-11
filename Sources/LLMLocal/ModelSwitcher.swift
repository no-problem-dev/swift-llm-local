import Foundation
import LLMLocalClient

/// Loads models on demand and reports which one the backend is holding.
///
/// Model weights are resident RAM measured in gigabytes, so a backend holds exactly one model at a
/// time: `LLMLocalBackend` releases the current weights before it reads the next ones, which is
/// what keeps two sets from being resident at the same moment. This actor is the load entry point
/// on top of that contract — it skips a load when the requested model is already resident, and
/// answers every question about residency by asking the backend rather than from a table of its
/// own.
///
/// That last part is the whole design. A tracker that remembers what it loaded goes stale the
/// moment anything else touches the backend — a memory warning, `LLMLocalService.prefetch(_:)`, a
/// direct `unloadModel()` — and then reports weights as loaded that are already gone. Deriving
/// every answer from ``LLMLocalBackend/currentModel`` makes that state impossible to represent.
///
/// ## Example
///
/// ```swift
/// let switcher = ModelSwitcher(backend: mlxBackend)
/// try await switcher.ensureLoaded(ModelPresets.qwen3_0_6B)
/// ```
public actor ModelSwitcher {

    private let backend: any LLMLocalBackend

    /// Creates a switcher over the given backend.
    ///
    /// - Parameter backend: Inference backend that performs the loads and unloads.
    public init(backend: any LLMLocalBackend) {
        self.backend = backend
    }

    /// Makes sure the model is resident, loading it when the backend is holding something else.
    ///
    /// A model that is already resident is not reloaded. Otherwise the backend releases whatever it
    /// holds and reads the new weights — the release happens first, so two sets of weights are
    /// never resident at once.
    ///
    /// - Parameter spec: Model to load.
    /// - Throws: Whatever the backend reports, including a failed download for a model that is not
    ///   on disk yet.
    public func ensureLoaded(_ spec: ModelSpec) async throws {
        try await ensureLoaded(spec, progressHandler: { _ in })
    }

    /// Makes sure the model is resident, reporting download progress while it is fetched.
    ///
    /// Residency works exactly as in ``ensureLoaded(_:)``. Progress covers the Hugging Face download
    /// only: a model already on disk completes immediately, and the remaining wait is the load into
    /// memory, which is not reported.
    ///
    /// - Parameters:
    ///   - spec: Model to load.
    ///   - progressHandler: Called as the download advances.
    /// - Throws: Whatever the backend reports while downloading or loading.
    public func ensureLoaded(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        if await backend.currentModel == spec {
            return
        }
        try await backend.loadModel(spec, progressHandler: progressHandler)
    }

    /// The model the backend is holding, or `nil` when it holds none.
    ///
    /// Read straight from the backend, so it cannot name a model whose weights have been released.
    public func loadedModel() async -> ModelSpec? {
        await backend.currentModel
    }

    /// Releases the model's weights when the backend is the one holding it.
    ///
    /// Asking to unload a model the backend is not holding does nothing, so it cannot release
    /// someone else's resident model by mistake.
    ///
    /// - Parameter spec: Model to unload.
    public func unload(_ spec: ModelSpec) async {
        guard await backend.currentModel == spec else {
            return
        }
        await backend.unloadModel()
    }

    /// Releases whatever weights the backend is holding.
    ///
    /// Use it to hand the memory back — to another feature, or to survive a memory warning. The
    /// next generation pays a full load again.
    public func unloadAll() async {
        await backend.unloadModel()
    }

    /// Reports whether the backend is holding this model's weights right now.
    ///
    /// - Parameter spec: Model to check.
    public func isLoaded(_ spec: ModelSpec) async -> Bool {
        await backend.currentModel == spec
    }
}
