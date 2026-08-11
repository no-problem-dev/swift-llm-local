import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocal

// MARK: - Mock Backend for ModelSwitcher Tests

/// A mock backend that tracks load/unload calls for testing ModelSwitcher.
///
/// It honours the `LLMLocalBackend` residency contract: exactly one model is held, and loading a
/// different spec replaces the previous one.
actor MockSwitcherBackend: LLMLocalBackend {
    private var _loadedModel: ModelSpec?
    private(set) var loadCallCount = 0
    private(set) var unloadCallCount = 0
    private(set) var loadedModelHistory: [ModelSpec] = []
    var shouldThrow: LLMLocalError?

    func loadModel(_ spec: ModelSpec) async throws {
        if let error = shouldThrow { throw error }
        loadCallCount += 1
        _loadedModel = spec
        loadedModelHistory.append(spec)
    }

    nonisolated func generate(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("mock")
            continuation.finish()
        }
    }

    func unloadModel() async {
        unloadCallCount += 1
        _loadedModel = nil
    }

    var isLoaded: Bool { _loadedModel != nil }
    var currentModel: ModelSpec? { _loadedModel }

    // MARK: - Test Helpers

    func resetCounts() {
        loadCallCount = 0
        unloadCallCount = 0
        loadedModelHistory = []
    }

    func setShouldThrow(_ error: LLMLocalError?) {
        shouldThrow = error
    }
}

// MARK: - Test Helpers

/// Creates a sample ModelSpec for testing.
private func makeSpec(
    id: String = "test-model",
    displayName: String = "Test Model"
) -> ModelSpec {
    ModelSpec(
        id: id,
        base: .huggingFace(id: "mlx-community/\(id)"),
        contextLength: 4096,
        displayName: displayName,
        description: "Test model for ModelSwitcher",
        estimatedMemoryBytes: 4_500_000_000
    )
}

// MARK: - Initialization Tests

@Suite("ModelSwitcher initialization")
struct ModelSwitcherInitTests {

    @Test("no model is loaded before the first ensureLoaded")
    func noModelLoadedInitially() async throws {
        // Arrange
        let backend = MockSwitcherBackend()

        // Act
        let switcher = ModelSwitcher(backend: backend)

        // Assert
        let loaded = await switcher.loadedModel()
        #expect(loaded == nil)
    }
}

// MARK: - ensureLoaded Tests

@Suite("ModelSwitcher ensureLoaded")
struct ModelSwitcherEnsureLoadedTests {

    @Test("loading first model succeeds")
    func loadingFirstModelSucceeds() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")

        // Act
        try await switcher.ensureLoaded(spec)

        // Assert
        let loaded = await switcher.loadedModel()
        #expect(loaded == spec)
        let loadCount = await backend.loadCallCount
        #expect(loadCount == 1)
    }

    @Test("loading same model again is no-op")
    func loadingSameModelAgainIsNoOp() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")

        // Act
        try await switcher.ensureLoaded(spec)
        try await switcher.ensureLoaded(spec)

        // Assert
        let loadCount = await backend.loadCallCount
        #expect(loadCount == 1) // Should only load once
        let loaded = await switcher.loadedModel()
        #expect(loaded == spec)
    }

    @Test("isLoaded returns true after loading")
    func isLoadedReturnsTrueAfterLoading() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")

        // Act
        try await switcher.ensureLoaded(spec)

        // Assert
        let loaded = await switcher.isLoaded(spec)
        #expect(loaded == true)
    }
}

// MARK: - Single-Residency Tests

@Suite("ModelSwitcher single residency")
struct ModelSwitcherSingleResidencyTests {

    @Test("loading a second model reports only the second as loaded")
    func secondModelDisplacesFirst() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")

        // Act
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)

        // Assert: the backend holds exactly one model, and the switcher says so.
        let isALoaded = await switcher.isLoaded(specA)
        #expect(isALoaded == false)
        let isBLoaded = await switcher.isLoaded(specB)
        #expect(isBLoaded == true)
        let loaded = await switcher.loadedModel()
        #expect(loaded == specB)
    }

    /// The invariant the tracker used to break: a model the backend has released must never be
    /// reported as loaded. A memory warning, `LLMLocalService.prefetch(_:)`, or any direct
    /// `unloadModel()` moves the backend without telling the switcher.
    @Test("a model the backend released behind the switcher's back is not reported as loaded")
    func externalUnloadIsReflected() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")
        try await switcher.ensureLoaded(spec)
        #expect(await switcher.isLoaded(spec) == true)

        // Act: something other than the switcher frees the weights.
        await backend.unloadModel()

        // Assert
        let isLoaded = await switcher.isLoaded(spec)
        #expect(isLoaded == false)
        let loaded = await switcher.loadedModel()
        #expect(loaded == nil)
    }

    /// The mirror image: the switcher must not deny a model the backend really is holding, or
    /// `ensureLoaded` would pay for a redundant multi-gigabyte load.
    @Test("a model loaded on the backend directly is reported as loaded")
    func externalLoadIsReflected() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")

        // Act: something other than the switcher loads the weights.
        try await backend.loadModel(spec)

        // Assert
        let isLoaded = await switcher.isLoaded(spec)
        #expect(isLoaded == true)
        try await switcher.ensureLoaded(spec)
        let loadCount = await backend.loadCallCount
        #expect(loadCount == 1) // No redundant reload.
    }

    @Test("switching models asks the backend to load the replacement")
    func switchingModelsLoadsReplacement() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")

        // Act
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)

        // Assert
        let history = await backend.loadedModelHistory
        #expect(history == [specA, specB])
    }
}

// MARK: - Unload Tests

@Suite("ModelSwitcher unload")
struct ModelSwitcherUnloadTests {

    @Test("unloading the resident model frees it")
    func unloadResidentModelFreesIt() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")
        try await switcher.ensureLoaded(spec)

        // Act
        await switcher.unload(spec)

        // Assert
        let isLoaded = await switcher.isLoaded(spec)
        #expect(isLoaded == false)
        let unloadCount = await backend.unloadCallCount
        #expect(unloadCount == 1)
    }

    /// Unloading a displaced model must not free the model that took its place.
    @Test("unloading a model the backend no longer holds leaves the resident one alone")
    func unloadDisplacedModelLeavesResidentAlone() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)

        // Act
        await switcher.unload(specA)

        // Assert
        let isBLoaded = await switcher.isLoaded(specB)
        #expect(isBLoaded == true)
        let unloadCount = await backend.unloadCallCount
        #expect(unloadCount == 0)
    }

    @Test("unloadAll clears everything")
    func unloadAllClearsEverything() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")
        try await switcher.ensureLoaded(spec)

        // Act
        await switcher.unloadAll()

        // Assert
        let loaded = await switcher.loadedModel()
        #expect(loaded == nil)
        let isLoaded = await switcher.isLoaded(spec)
        #expect(isLoaded == false)
    }

    @Test("unloading non-loaded model is no-op")
    func unloadNonLoadedModelIsNoOp() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")

        // Act
        await switcher.unload(spec)

        // Assert
        let loaded = await switcher.loadedModel()
        #expect(loaded == nil)
        let unloadCount = await backend.unloadCallCount
        #expect(unloadCount == 0) // Backend should not be called
    }
}

// MARK: - LLMLocalService Integration Tests

@Suite("LLMLocalService with ModelSwitcher")
struct LLMLocalServiceModelSwitcherTests {

    /// Creates a temporary directory for test isolation.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMLocalServiceSwitcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a temporary directory after test use.
    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("service with modelSwitcher uses it for model loading")
    func serviceWithSwitcherUsesItForLoading() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockSwitcherBackend()
        let modelRegistry = try ModelRegistry(cacheDirectory: dir)
        let switcher = ModelSwitcher(backend: backend)
        let service = try LLMLocalService(
            backend: backend,
            modelRegistry: modelRegistry,
            modelSwitcher: switcher
        )
        let spec = makeSpec(id: "model-a")

        // Act
        let stream = await service.generate(model: spec, prompt: "Hello")
        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        // Assert
        #expect(!tokens.isEmpty)
        let isLoaded = await switcher.isLoaded(spec)
        #expect(isLoaded == true)
    }

    @Test("service without modelSwitcher works as before")
    func serviceWithoutSwitcherWorksAsBefore() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockSwitcherBackend()
        let modelRegistry = try ModelRegistry(cacheDirectory: dir)
        let service = try LLMLocalService(
            backend: backend,
            modelRegistry: modelRegistry
        )
        let spec = makeSpec(id: "model-a")

        // Act
        let stream = await service.generate(model: spec, prompt: "Hello")
        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        // Assert
        #expect(!tokens.isEmpty)
        let loadCount = await backend.loadCallCount
        #expect(loadCount == 1)
    }

    @Test("loadedModel reflects the most recently generated-with model")
    func loadedModelReflectsGeneratedModel() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockSwitcherBackend()
        let modelRegistry = try ModelRegistry(cacheDirectory: dir)
        let switcher = ModelSwitcher(backend: backend)
        let service = try LLMLocalService(
            backend: backend,
            modelRegistry: modelRegistry,
            modelSwitcher: switcher
        )
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")

        // Act: Generate with two different models
        let streamA = await service.generate(model: specA, prompt: "Hello")
        for try await _ in streamA {}
        let streamB = await service.generate(model: specB, prompt: "Hello")
        for try await _ in streamB {}

        // Assert: only the second is resident.
        let loaded = await switcher.loadedModel()
        #expect(loaded == specB)
    }

    @Test("service backward compatibility with nil modelSwitcher")
    func serviceBackwardCompatibilityNilSwitcher() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockSwitcherBackend()
        let modelRegistry = try ModelRegistry(cacheDirectory: dir)

        // Act: Use original init without modelSwitcher parameter
        let service = try LLMLocalService(backend: backend, modelRegistry: modelRegistry)
        let spec = makeSpec(id: "model-a")
        let stream = await service.generate(model: spec, prompt: "Hello")
        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        // Assert
        #expect(tokens == ["mock"])
        let loadCount = await backend.loadCallCount
        #expect(loadCount == 1)
    }
}

// MARK: - Error Handling Tests

@Suite("ModelSwitcher error handling")
struct ModelSwitcherErrorTests {

    @Test("ensureLoaded propagates backend load error")
    func ensureLoadedPropagatesBackendError() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        await backend.setShouldThrow(.loadFailed(modelId: "model-a", reason: "test error"))
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")

        // Act & Assert
        await #expect(throws: LLMLocalError.self) {
            try await switcher.ensureLoaded(spec)
        }
        // Model should not be reported loaded after a failed load
        let loaded = await switcher.loadedModel()
        #expect(loaded == nil)
    }

    @Test("isLoaded returns false for never-loaded model")
    func isLoadedReturnsFalseForNeverLoaded() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)
        let spec = makeSpec(id: "model-a")

        // Act
        let loaded = await switcher.isLoaded(spec)

        // Assert
        #expect(loaded == false)
    }
}
