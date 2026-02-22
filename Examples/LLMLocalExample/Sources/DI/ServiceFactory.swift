import LLMLocal

enum ServiceFactory {
    struct Services: Sendable {
        let llmService: LLMLocalService
        let modelManager: ModelManager
        let memoryMonitor: MemoryMonitor
    }

    static func makeServices() -> Services {
        let memoryMonitor = MemoryMonitor()
        let modelManager = ModelManager()
        let backend = MLXBackend(gpuCacheLimit: 20 * 1024 * 1024)
        let llmService = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: memoryMonitor
        )
        return Services(
            llmService: llmService,
            modelManager: modelManager,
            memoryMonitor: memoryMonitor
        )
    }
}
