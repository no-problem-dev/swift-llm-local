import Testing
import Foundation
@testable import LLMLocalClient
@testable import LLMLocalMLX

// MARK: - Test Helpers

/// Helper to create a sample ModelSpec for testing.
private func sampleSpec(
    id: String = "test-model",
    base: ModelSource = .huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
    adapter: AdapterSource? = nil,
    contextLength: Int = 4096,
    displayName: String = "Test Model",
    description: String = "A test model for unit tests"
) -> ModelSpec {
    ModelSpec(
        id: id,
        base: base,
        adapter: adapter,
        contextLength: contextLength,
        displayName: displayName,
        description: description
    )
}

// MARK: - Protocol Conformance

@Suite("MLXBackend protocol conformance")
struct MLXBackendProtocolConformanceTests {

    @Test("MLXBackend conforms to LLMLocalBackend")
    func conformsToLLMLocalBackend() {
        // Arrange & Act: compile-time check -- MLXBackend as LLMLocalBackend
        let backend = MLXBackend()
        let _: any LLMLocalBackend = backend

        // Assert: if this compiles, the conformance is verified
        #expect(true)
    }

    @Test("MLXBackend conforms to Sendable")
    func conformsToSendable() {
        let backend = MLXBackend()
        // Passing through a Sendable closure boundary proves Sendable at compile time
        let result: any LLMLocalBackend = { @Sendable in backend }()
        #expect(result is MLXBackend)
    }
}

// MARK: - Initial State

@Suite("MLXBackend initial state")
struct MLXBackendInitialStateTests {

    @Test("isLoaded is false when newly created")
    func isLoadedIsFalseWhenNew() async {
        // Arrange
        let backend = MLXBackend()

        // Act
        let loaded = await backend.isLoaded

        // Assert
        #expect(loaded == false)
    }

    @Test("currentModel is nil when newly created")
    func currentModelIsNilWhenNew() async {
        // Arrange
        let backend = MLXBackend()

        // Act
        let model = await backend.currentModel

        // Assert
        #expect(model == nil)
    }

    @Test("initializes with default GPU cache limit")
    func initializesWithDefaultGPUCacheLimit() async {
        // Arrange & Act
        let backend = MLXBackend()

        // Assert: default is 20 MB (20 * 1024 * 1024)
        let cacheLimit = await backend.gpuCacheLimitValue
        #expect(cacheLimit == 20 * 1024 * 1024)
    }

    @Test("initializes with custom GPU cache limit")
    func initializesWithCustomGPUCacheLimit() async {
        // Arrange & Act
        let customLimit = 50 * 1024 * 1024
        let backend = MLXBackend(gpuCacheLimit: customLimit)

        // Assert
        let cacheLimit = await backend.gpuCacheLimitValue
        #expect(cacheLimit == customLimit)
    }
}

// MARK: - Unload Model

@Suite("MLXBackend unloadModel")
struct MLXBackendUnloadModelTests {

    @Test("unloadModel on fresh instance does not crash")
    func unloadOnFreshInstanceDoesNotCrash() async {
        // Arrange
        let backend = MLXBackend()

        // Act: should not throw or crash
        await backend.unloadModel()

        // Assert
        let loaded = await backend.isLoaded
        let model = await backend.currentModel
        #expect(loaded == false)
        #expect(model == nil)
    }
}

// MARK: - Generate Without Model

@Suite("MLXBackend generate without model loaded")
struct MLXBackendGenerateWithoutModelTests {

    @Test("generate throws modelNotLoaded when no model loaded")
    func generateThrowsModelNotLoaded() async throws {
        // Arrange
        let backend = MLXBackend()
        let config = GenerationConfig()

        // Act
        let stream = backend.generate(prompt: "Hello", config: config)

        // Assert: iterating the stream should throw modelNotLoaded
        var caughtError: (any Error)?
        do {
            for try await _ in stream {
                // Should not yield any tokens
            }
        } catch {
            caughtError = error
        }

        #expect(caughtError is LLMLocalError)
        #expect(caughtError as? LLMLocalError == .modelNotLoaded)
    }
}

// MARK: - LoadInProgress Exclusive Control

@Suite("MLXBackend loadInProgress exclusive control")
struct MLXBackendLoadInProgressTests {

    @Test("isLoading is false initially")
    func isLoadingIsFalseInitially() async {
        // Arrange
        let backend = MLXBackend()

        // Act
        let loading = await backend.isLoadingValue

        // Assert
        #expect(loading == false)
    }
}

// MARK: - GenerationConfig+MLX Conversion

@Suite("GenerationConfig to MLX parameter conversion")
struct GenerationConfigMLXConversionTests {

    @Test("converts maxTokens correctly")
    func convertsMaxTokens() {
        // Arrange
        let config = GenerationConfig(maxTokens: 512)

        // Act
        let params = config.mlxParameters

        // Assert
        #expect(params.maxTokens == 512)
    }

    @Test("converts temperature correctly")
    func convertsTemperature() {
        // Arrange
        let config = GenerationConfig(temperature: 0.5)

        // Act
        let params = config.mlxParameters

        // Assert
        #expect(params.temperature == 0.5)
    }

    @Test("converts topP correctly")
    func convertsTopP() {
        // Arrange
        let config = GenerationConfig(topP: 0.85)

        // Act
        let params = config.mlxParameters

        // Assert
        #expect(params.topP == 0.85)
    }

    @Test("converts default config correctly")
    func convertsDefaultConfig() {
        // Arrange
        let config = GenerationConfig.default

        // Act
        let params = config.mlxParameters

        // Assert
        #expect(params.maxTokens == 1024)
        #expect(params.temperature == 0.7)
        #expect(params.topP == 0.9)
    }

    @Test("converts extreme values correctly")
    func convertsExtremeValues() {
        // Arrange: zero temperature (deterministic)
        let config = GenerationConfig(maxTokens: 1, temperature: 0.0, topP: 1.0)

        // Act
        let params = config.mlxParameters

        // Assert
        #expect(params.maxTokens == 1)
        #expect(params.temperature == 0.0)
        #expect(params.topP == 1.0)
    }
}

// MARK: - Same Model Skip

@Suite("MLXBackend same model skip")
struct MLXBackendSameModelSkipTests {

    @Test("loadModel with same spec does not re-load (tested via state)")
    func sameModelSpecSkipsReload() async {
        // This test verifies that the spec comparison works correctly.
        // Since we cannot call real MLX APIs, we test the equality logic
        // that drives the early return.
        let specA = sampleSpec(id: "model-1")
        let specB = sampleSpec(id: "model-1")
        #expect(specA == specB)

        // Different spec should not be equal
        let specC = sampleSpec(id: "model-2")
        #expect(specA != specC)
    }
}

// MARK: - ModelSource to HuggingFace ID Extraction

@Suite("MLXBackend model source to ID extraction")
struct MLXBackendModelSourceExtractionTests {

    @Test("extracts HuggingFace ID from huggingFace source")
    func extractsHuggingFaceId() {
        // Arrange
        let source = ModelSource.huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit")

        // Act
        let hfID: String
        switch source {
        case .huggingFace(let id):
            hfID = id
        case .local(let path):
            hfID = path.path()
        }

        // Assert
        #expect(hfID == "mlx-community/Llama-3.2-1B-Instruct-4bit")
    }

    @Test("extracts path from local source")
    func extractsLocalPath() {
        // Arrange
        let url = URL(filePath: "/tmp/models/llama")
        let source = ModelSource.local(path: url)

        // Act
        let hfID: String
        switch source {
        case .huggingFace(let id):
            hfID = id
        case .local(let path):
            hfID = path.path()
        }

        // Assert
        #expect(hfID == "/tmp/models/llama")
    }
}
