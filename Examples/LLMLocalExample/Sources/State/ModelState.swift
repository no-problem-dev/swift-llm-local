import SwiftUI
import LLMLocal

@Observable
@MainActor
final class ModelState {
    private let service: LLMLocalService
    private let modelRegistry: ModelRegistry
    private let memoryMonitor: MemoryMonitor

    var availableModels: [ModelSpec] = ModelCatalog.specs
    var cachedModels: [CachedModelInfo] = []
    var selectedModel: ModelSpec = ModelCatalog.defaultModel {
        didSet {
            UserDefaults.standard.set(selectedModel.id, forKey: "llmlocal.selectedModelId")
        }
    }
    var isDownloading: Bool = false
    var downloadingModelId: String?
    var downloadStatusText: String = ""
    var downloadProgress: DownloadProgress?
    var totalCacheSize: Int64 = 0
    var memoryTier: MemoryMonitor.DeviceMemoryTier?
    var availableMemory: UInt64 = 0
    var recommendedContextLength: Int?
    var error: String?

    init(service: LLMLocalService, modelRegistry: ModelRegistry, memoryMonitor: MemoryMonitor) {
        self.service = service
        self.modelRegistry = modelRegistry
        self.memoryMonitor = memoryMonitor

        if let savedId = UserDefaults.standard.string(forKey: "llmlocal.selectedModelId"),
           let found = availableModels.first(where: { $0.id == savedId }) {
            selectedModel = found
        }
    }

    func refreshCache() async {
        cachedModels = await modelRegistry.cachedModels()
        totalCacheSize = (try? await modelRegistry.totalCacheSize()) ?? 0
    }

    func refreshMemoryInfo() async {
        memoryTier = await memoryMonitor.deviceMemoryTier()
        availableMemory = await memoryMonitor.availableMemory()
        recommendedContextLength = await memoryMonitor.recommendedContextLength()
    }

    /// モデルを事前ダウンロード（prefetch）する。
    /// MLXBackend.loadModel() が HuggingFace Hub から実際にダウンロードし、
    /// GPU メモリにロードする。完了後にキャッシュメタデータも登録する。
    func downloadModel(_ spec: ModelSpec) async {
        isDownloading = true
        downloadingModelId = spec.id
        downloadStatusText = "ダウンロード中..."
        downloadProgress = nil
        error = nil

        do {
            // prefetch は backend.loadModel() を呼び、
            // HuggingFace Hub からの実際のダウンロード + ロードを行う
            downloadStatusText = "モデルをダウンロード・ロード中..."
            try await service.prefetch(spec) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }

            // ダウンロード成功後、メタデータをキャッシュに登録
            try await modelRegistry.registerModel(spec, sizeInBytes: 0)
            await refreshCache()

            // 自動選択
            selectedModel = spec
        } catch {
            self.error = error.localizedDescription
        }

        isDownloading = false
        downloadingModelId = nil
        downloadStatusText = ""
        downloadProgress = nil
    }

    func deleteModel(_ spec: ModelSpec) async {
        do {
            try await modelRegistry.deleteCache(for: spec)
            await refreshCache()
            // 削除したモデルが選択中だったらデフォルトに戻す
            if selectedModel == spec {
                selectedModel = ModelCatalog.defaultModel
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func isModelCached(_ spec: ModelSpec) -> Bool {
        cachedModels.contains { $0.modelId == spec.id }
    }
}
