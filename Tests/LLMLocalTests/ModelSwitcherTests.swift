import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocal

// MARK: - Mock Backend for ModelSwitcher Tests

/// A mock backend that tracks load/unload calls for testing ModelSwitcher.
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

    @Test("default maxLoadedModels is 1")
    func defaultMaxLoadedModelsIsOne() async {
        // Arrange
        let backend = MockSwitcherBackend()

        // Act
        let switcher = ModelSwitcher(backend: backend)

        // Assert
        #expect(switcher.maxLoadedModels == 1)
    }

    @Test("custom maxLoadedModels is set correctly")
    func customMaxLoadedModels() async {
        // Arrange
        let backend = MockSwitcherBackend()

        // Act
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 3)

        // Assert
        #expect(switcher.maxLoadedModels == 3)
    }

    @Test("loadedCount starts at 0")
    func loadedCountStartsAtZero() async {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend)

        // Act
        let count = await switcher.loadedCount()

        // Assert
        #expect(count == 0)
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
        let count = await switcher.loadedCount()
        #expect(count == 1)
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
        let count = await switcher.loadedCount()
        #expect(count == 1)
    }

    @Test("loading different model works")
    func loadingDifferentModelWorks() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 2)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")

        // Act
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)

        // Assert
        let count = await switcher.loadedCount()
        #expect(count == 2)
        let loadCount = await backend.loadCallCount
        #expect(loadCount == 2)
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

    @Test("loadedModelSpecs returns loaded models in most-recent-first order")
    func loadedModelSpecsReturnsLoadedModels() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 3)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")
        let specC = makeSpec(id: "model-c")

        // Act
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)
        try await switcher.ensureLoaded(specC)

        // Assert
        let specs = await switcher.loadedModelSpecs()
        #expect(specs.count == 3)
        // Most recently loaded first
        #expect(specs[0] == specC)
        #expect(specs[1] == specB)
        #expect(specs[2] == specA)
    }
}

// MARK: - LRU Eviction Tests

@Suite("ModelSwitcher LRU eviction")
struct ModelSwitcherLRUEvictionTests {

    @Test("at capacity, loading new model evicts LRU")
    func atCapacityEvictsLRU() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 2)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")
        let specC = makeSpec(id: "model-c")

        // Act: Load A, then B (at capacity), then C (should evict A)
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)
        try await switcher.ensureLoaded(specC)

        // Assert
        let isALoaded = await switcher.isLoaded(specA)
        #expect(isALoaded == false) // A was evicted (LRU)
        let isBLoaded = await switcher.isLoaded(specB)
        #expect(isBLoaded == true)
        let isCLoaded = await switcher.isLoaded(specC)
        #expect(isCLoaded == true)
        let count = await switcher.loadedCount()
        #expect(count == 2)
    }

    @Test("most recently accessed model is not evicted")
    func mostRecentlyAccessedNotEvicted() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 2)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")
        let specC = makeSpec(id: "model-c")

        // Act: Load A, B, then access A again (updates access time), then load C
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)
        // Access A again to update its timestamp
        try await switcher.ensureLoaded(specA)
        // Now load C -- B should be evicted (it's LRU), not A
        try await switcher.ensureLoaded(specC)

        // Assert
        let isALoaded = await switcher.isLoaded(specA)
        #expect(isALoaded == true) // A was recently accessed
        let isBLoaded = await switcher.isLoaded(specB)
        #expect(isBLoaded == false) // B was evicted (LRU)
        let isCLoaded = await switcher.isLoaded(specC)
        #expect(isCLoaded == true)
    }

    @Test("loadedCount stays at max after eviction")
    func loadedCountStaysAtMaxAfterEviction() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 2)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")
        let specC = makeSpec(id: "model-c")

        // Act
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)
        try await switcher.ensureLoaded(specC)

        // Assert
        let count = await switcher.loadedCount()
        #expect(count == 2)
    }

    @Test("accessing a loaded model updates its access time")
    func accessingModelUpdatesAccessTime() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 3)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")
        let specC = makeSpec(id: "model-c")

        // Act: Load A, B, C, then access A
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)
        try await switcher.ensureLoaded(specC)
        // Access A to bump its timestamp
        try await switcher.ensureLoaded(specA)

        // Assert: A should now be the most recently accessed
        let specs = await switcher.loadedModelSpecs()
        #expect(specs[0] == specA) // Most recently accessed first
    }

    @Test("with capacity 1, switching models evicts previous")
    func capacity1SwitchingEvictsPrevious() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 1)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")

        // Act
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)

        // Assert
        let isALoaded = await switcher.isLoaded(specA)
        #expect(isALoaded == false) // A was evicted
        let isBLoaded = await switcher.isLoaded(specB)
        #expect(isBLoaded == true)
        let count = await switcher.loadedCount()
        #expect(count == 1)
        // Backend should have been asked to unload before loading new model
        let unloadCount = await backend.unloadCallCount
        #expect(unloadCount == 1)
    }
}

// MARK: - Unload Tests

@Suite("ModelSwitcher unload")
struct ModelSwitcherUnloadTests {

    @Test("unload specific model removes it")
    func unloadSpecificModelRemovesIt() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 2)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)

        // Act
        await switcher.unload(specA)

        // Assert
        let isALoaded = await switcher.isLoaded(specA)
        #expect(isALoaded == false)
        let isBLoaded = await switcher.isLoaded(specB)
        #expect(isBLoaded == true)
        let count = await switcher.loadedCount()
        #expect(count == 1)
    }

    @Test("unloadAll clears everything")
    func unloadAllClearsEverything() async throws {
        // Arrange
        let backend = MockSwitcherBackend()
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 3)
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")
        try await switcher.ensureLoaded(specA)
        try await switcher.ensureLoaded(specB)

        // Act
        await switcher.unloadAll()

        // Assert
        let count = await switcher.loadedCount()
        #expect(count == 0)
        let isALoaded = await switcher.isLoaded(specA)
        #expect(isALoaded == false)
        let isBLoaded = await switcher.isLoaded(specB)
        #expect(isBLoaded == false)
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
        let count = await switcher.loadedCount()
        #expect(count == 0)
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
        let modelManager = ModelManager(cacheDirectory: dir)
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 2)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
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
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager
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

    @Test("loadedModelSpecs reflects generated models")
    func loadedModelSpecsReflectsGeneratedModels() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockSwitcherBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let switcher = ModelSwitcher(backend: backend, maxLoadedModels: 3)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            modelSwitcher: switcher
        )
        let specA = makeSpec(id: "model-a")
        let specB = makeSpec(id: "model-b")

        // Act: Generate with two different models
        let streamA = await service.generate(model: specA, prompt: "Hello")
        for try await _ in streamA {}
        let streamB = await service.generate(model: specB, prompt: "Hello")
        for try await _ in streamB {}

        // Assert
        let specs = await switcher.loadedModelSpecs()
        #expect(specs.count == 2)
        #expect(specs.contains(specA))
        #expect(specs.contains(specB))
    }

    @Test("service backward compatibility with nil modelSwitcher")
    func serviceBackwardCompatibilityNilSwitcher() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let backend = MockSwitcherBackend()
        let modelManager = ModelManager(cacheDirectory: dir)

        // Act: Use original init without modelSwitcher parameter
        let service = LLMLocalService(backend: backend, modelManager: modelManager)
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
        // Model should not be tracked after failed load
        let count = await switcher.loadedCount()
        #expect(count == 0)
    }

    @Test("isLoaded returns false for never-loaded model")
    func isLoadedReturnsFalseForNeverLoaded() async {
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
