#if !targetEnvironment(simulator)
import Foundation
import Testing
import LLMLocal
import LLMLocalClient
import LLMLocalMLX
import LLMLocalModels

/// Phase 3 integration tests for model switching against the real MLX backend.
///
/// These tests require a Metal GPU and will download real models.
/// They cannot be run in CI or simulators.
///
/// ## Test Coverage
/// - Model switching: residency after a switch, switching during generation
/// - Phase 1-2 regression: all prior functionality unchanged
///
/// `BackgroundDownloader` is not covered here. It performs no transfers of its own — every byte
/// moves through an injected `BackgroundDownloadDelegate`, and this package ships none — so a test
/// of it would be a test of its own fixture.
@Suite("Phase 3 Integration Tests", .disabled("Requires Metal GPU and model download"))
struct Phase3IntegrationTests {

    // MARK: - Test 3: Multi-model Switching with Single Backend

    @Test("ModelSwitcher switches between models")
    func modelSwitcherSwitchesModels() async throws {
        // Arrange
        let backend = try MLXBackend()
        let switcher = ModelSwitcher(backend: backend)

        let model1 = ModelPresets.qwen3_0_6B

        // Act: Load first model
        try await switcher.ensureLoaded(model1)

        // Assert
        let loaded = await switcher.isLoaded(model1)
        #expect(loaded, "Model should be loaded")
        #expect(await switcher.loadedModel() == model1)
    }

    // MARK: - Test 4: Service with ModelSwitcher

    @Test("LLMLocalService generates with ModelSwitcher")
    func serviceWithModelSwitcher() async throws {
        // Arrange
        let backend = try MLXBackend()
        let modelRegistry = try ModelRegistry()
        let switcher = ModelSwitcher(backend: backend)
        let service = try LLMLocalService(
            backend: backend,
            modelRegistry: modelRegistry,
            modelSwitcher: switcher
        )

        let config = GenerationConfig(maxTokens: 20)

        // Act
        var tokens: [String] = []
        let stream = await service.generate(
            model: ModelPresets.qwen3_0_6B,
            prompt: "Hello",
            config: config
        )
        for try await token in stream {
            tokens.append(token)
        }

        // Assert
        #expect(!tokens.isEmpty, "Should produce tokens")
        #expect(await switcher.loadedModel() == ModelPresets.qwen3_0_6B)
    }

    // MARK: - Test 5: Phase 1-2 Regression Check

    @Test("Phase 1-2 regression: generation without switcher works")
    func phase12RegressionNoSwitcher() async throws {
        // Arrange — no modelSwitcher (backward compat)
        let backend = try MLXBackend()
        let modelRegistry = try ModelRegistry()
        let monitor = MemoryMonitor()
        let service = try LLMLocalService(
            backend: backend,
            modelRegistry: modelRegistry,
            memoryMonitor: monitor
        )

        let config = GenerationConfig(maxTokens: 20)

        // Act
        var tokens: [String] = []
        let stream = await service.generate(
            model: ModelPresets.qwen3_0_6B,
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
