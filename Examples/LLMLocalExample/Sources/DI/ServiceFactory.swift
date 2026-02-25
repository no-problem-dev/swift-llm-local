import LLMLocal

enum ServiceFactory {
    struct Services: Sendable {
        let llmService: LLMLocalService
        let modelRegistry: ModelRegistry
        let memoryMonitor: MemoryMonitor
    }

    static func makeServices() -> Services {
        let memoryMonitor = MemoryMonitor()
        let modelRegistry = ModelRegistry()
        let backend = MLXBackend(gpuCacheLimit: 20 * 1024 * 1024)
        let llmService = LLMLocalService(
            backend: backend,
            modelRegistry: modelRegistry,
            memoryMonitor: memoryMonitor
        )
        return Services(
            llmService: llmService,
            modelRegistry: modelRegistry,
            memoryMonitor: memoryMonitor
        )
    }
}
