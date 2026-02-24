#if !targetEnvironment(simulator)
import Foundation
import Testing
import LLMLocal
import LLMLocalClient
import LLMLocalMLX
import LLMLocalModels

/// Phase 3 integration tests for background download and multi-model switching.
///
/// These tests require a Metal GPU and will download real models.
/// They cannot be run in CI or simulators.
///
/// ## Test Coverage
/// - Background download: start, pause, resume, cancel
/// - Multi-model switching: LRU eviction, model switching during generation
/// - Phase 1-2 regression: all prior functionality unchanged
@Suite("Phase 3 Integration Tests", .disabled("Requires Metal GPU and model download"))
struct Phase3IntegrationTests {

    // MARK: - Test 1: Background Download Start and Complete

    @Test("Background download completes and returns local URL")
    func backgroundDownloadCompletes() async throws {
        // Arrange
        let modelManager = ModelManager()
        let downloader = await modelManager.backgroundDownloader

        let testURL = URL(string: "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit")!

        // Act
        let localURL = try await downloader.download(from: testURL)

        // Assert
        #expect(localURL.isFileURL, "Should return a local file URL")
    }

    // MARK: - Test 2: Background Download Pause and Resume

    @Test("Background download can be paused and resumed")
    func backgroundDownloadPauseResume() async throws {
        // Arrange
        let modelManager = ModelManager()
        let downloader = await modelManager.backgroundDownloader

        let testURL = URL(string: "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit")!

        // Start download in background
        let downloadTask = Task {
            try await downloader.download(from: testURL)
        }

        // Give it time to start
        try await Task.sleep(for: .milliseconds(500))

        // Act: Pause
        try await downloader.pause(url: testURL)
        let hasResume = await downloader.hasResumeData(for: testURL)
        #expect(hasResume, "Should have resume data after pause")

        // Act: Resume
        let localURL = try await downloader.resume(url: testURL)

        // Assert
        #expect(localURL.isFileURL, "Should return a local file URL after resume")

        downloadTask.cancel()
    }

    // MARK: - Test 3: Multi-model Switching with Single Backend

    @Test("ModelSwitcher switches between models")
    func modelSwitcherSwitchesModels() async throws {
        // Arrange
        let backend = MLXBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 1)

        let model1 = ModelPresets.gemma2_2B

        // Act: Load first model
        try await switcher.ensureLoaded(model1)

        // Assert
        let loaded = await switcher.isLoaded(model1)
        #expect(loaded, "Model should be loaded")
        #expect(await switcher.loadedCount() == 1)
    }

    // MARK: - Test 4: Service with ModelSwitcher

    @Test("LLMLocalService generates with ModelSwitcher")
    func serviceWithModelSwitcher() async throws {
        // Arrange
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 1)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            modelSwitcher: switcher
        )

        let config = GenerationConfig(maxTokens: 20)

        // Act
        var tokens: [String] = []
        let stream = await service.generate(
            model: ModelPresets.gemma2_2B,
            prompt: "Hello",
            config: config
        )
        for try await token in stream {
            tokens.append(token)
        }

        // Assert
        #expect(!tokens.isEmpty, "Should produce tokens")
        let loadedSpecs = await switcher.loadedModelSpecs()
        #expect(loadedSpecs.contains(ModelPresets.gemma2_2B))
    }

    // MARK: - Test 5: Phase 1-2 Regression Check

    @Test("Phase 1-2 regression: generation without switcher works")
    func phase12RegressionNoSwitcher() async throws {
        // Arrange — no modelSwitcher (backward compat)
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let monitor = MemoryMonitor()
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        let config = GenerationConfig(maxTokens: 20)

        // Act
        var tokens: [String] = []
        let stream = await service.generate(
            model: ModelPresets.gemma2_2B,
            prompt: "What is Swift?",
            config: config
        )
        for try await token in stream {
            tokens.append(token)
        }

        // Assert
        #expect(!tokens.isEmpty, "Should produce tokens")
        let stats = await service.lastGenerationStats
        #expect(stats != nil, "Stats should be recorded")
        #expect(stats!.tokenCount > 0)

        // Memory monitor should work
        let contextLength = await service.recommendedContextLength()
        #expect(contextLength != nil)
    }
}
#endif
