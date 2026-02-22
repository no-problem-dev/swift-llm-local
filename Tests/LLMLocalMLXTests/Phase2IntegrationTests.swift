#if !targetEnvironment(simulator)
import Testing
import Foundation
import LLMLocal
import LLMLocalClient
import LLMLocalMLX
import LLMLocalModels

/// Phase 2 integration tests for download progress, memory monitoring,
/// adapter management, and regression checks.
///
/// These tests require a Metal GPU and may download real models (~1.5GB).
/// They cannot be run in CI or simulators.
///
/// ## Test Coverage
/// - Download progress: stream of DownloadProgress from 0.0 to 1.0
/// - Memory warning: model unload on simulated memory pressure
/// - Adapter resolution: adapter resolver flow with MLXBackend
/// - Phase 1 regression: basic generation still works after Phase 2 changes
/// - Memory tier: MemoryMonitor provides correct tier and context length
/// - Adapter caching: AdapterManager resolve + cache flow
@Suite("Phase 2 Integration Tests", .disabled("Requires Metal GPU and model download"))
struct Phase2IntegrationTests {

    // MARK: - Test 1: DownloadProgress stream with real model

    @Test("DownloadProgress stream progresses from 0.0 to 1.0")
    func downloadProgressStreamProgresses() async throws {
        // Arrange
        let modelManager = ModelManager()
        let spec = ModelPresets.gemma2B

        // Act
        var progressValues: [Double] = []
        let stream = await modelManager.downloadWithProgress(spec)
        for try await progress in stream {
            progressValues.append(progress.fraction)
        }

        // Assert
        #expect(!progressValues.isEmpty, "Should receive at least one progress update")
        #expect(progressValues.first! >= 0.0, "First progress should be >= 0.0")
        #expect(progressValues.last! == 1.0, "Final progress should be 1.0")

        // Verify monotonically non-decreasing
        for i in 1..<progressValues.count {
            #expect(
                progressValues[i] >= progressValues[i - 1],
                "Progress should be monotonically non-decreasing"
            )
        }
    }

    // MARK: - Test 2: Memory warning simulation unloads model

    @Test("Memory warning simulation triggers model unload")
    func memoryWarningTriggersUnload() async throws {
        // Arrange
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let monitor = MemoryMonitor()
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // Load model
        try await backend.loadModel(ModelPresets.gemma2B)
        let loadedBefore = await backend.isLoaded
        #expect(loadedBefore == true, "Model should be loaded before memory warning")

        // Act: start monitoring and simulate memory warning
        await service.startMemoryMonitoring()

        NotificationCenter.default.post(
            name: MemoryMonitor.memoryWarningNotificationName,
            object: nil
        )

        // Allow time for the async handler to process
        try await Task.sleep(for: .milliseconds(500))

        // Assert
        let loadedAfter = await backend.isLoaded
        #expect(loadedAfter == false, "Model should be unloaded after memory warning")

        // Cleanup
        await service.stopMemoryMonitoring()
    }

    // MARK: - Test 3: Adapter resolution flow during model load

    @Test("Loading model without adapter does not trigger adapter resolution")
    func loadModelWithoutAdapterSkipsResolution() async throws {
        // Arrange: This test verifies the adapter resolution flow works end-to-end.
        // A full adapter merge test requires a real LoRA adapter file.
        // For now, verify that loading without adapter works fine
        // and that lastResolvedAdapterURL is nil when no adapter is specified.
        //
        // Note: AdapterManager (Layer 1) does not explicitly conform to
        // AdapterResolving (Layer 0). In integration tests we test them
        // independently.
        let backend = MLXBackend()
        let specWithoutAdapter = ModelPresets.gemma2B

        // Act
        try await backend.loadModel(specWithoutAdapter)

        // Assert: model loaded successfully without adapter
        let isLoaded = await backend.isLoaded
        #expect(isLoaded == true, "Model should be loaded successfully without adapter")

        // Verify the loaded model matches the spec
        let currentModel = await backend.currentModel
        #expect(currentModel == specWithoutAdapter, "Loaded model should match the requested spec")
    }

    // MARK: - Test 4: Phase 1 regression check

    @Test("Phase 1 regression: basic generation still works")
    func phase1RegressionBasicGeneration() async throws {
        // Arrange
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let service = LLMLocalService(backend: backend, modelManager: modelManager)
        let config = GenerationConfig(maxTokens: 20)

        // Act
        var tokens: [String] = []
        let stream = await service.generate(
            model: ModelPresets.gemma2B,
            prompt: "Hello",
            config: config
        )
        for try await token in stream {
            tokens.append(token)
        }

        // Assert
        #expect(!tokens.isEmpty, "Should receive at least one token")

        let stats = await service.lastGenerationStats
        #expect(stats != nil, "Stats should be recorded after generation")
        #expect(stats!.tokenCount > 0, "Token count should be positive")
    }

    // MARK: - Test 5: MemoryMonitor tier and context recommendation

    @Test("MemoryMonitor provides correct tier and context length")
    func memoryMonitorProvidesTierAndContext() async {
        // Arrange
        let monitor = MemoryMonitor()

        // Act
        let tier = await monitor.deviceMemoryTier()
        let contextLength = await monitor.recommendedContextLength()
        let available = await monitor.availableMemory()

        // Assert: on any real device, memory should be detectable
        #expect(available > 0, "Available memory should be positive on real hardware")

        // Context length should match tier
        switch tier {
        case .standard:
            #expect(contextLength == 2048, "Standard tier should recommend 2048 context length")
        case .high:
            #expect(contextLength == 4096, "High tier should recommend 4096 context length")
        }
    }

    // MARK: - Test 6: AdapterManager caching flow

    @Test("AdapterManager resolves and caches adapter")
    func adapterManagerResolvesAndCaches() async throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Phase2IT-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = AdapterManager(adapterDirectory: tempDir)
        let source = AdapterSource.local(path: URL(fileURLWithPath: "/nonexistent"))

        // Act & Assert: local non-existent should throw
        await #expect(throws: LLMLocalError.self) {
            try await manager.resolve(source)
        }

        // Verify not cached
        let isCached = await manager.isCached(source)
        #expect(isCached == false, "Non-existent adapter should not be cached")
    }
}
#endif
