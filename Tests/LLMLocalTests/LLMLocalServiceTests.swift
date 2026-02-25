import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocal

@Suite("LLMLocalService")
struct LLMLocalServiceTests {

    // MARK: - Test Helpers

    /// Creates a temporary directory for test isolation.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMLocalServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a temporary directory after test use.
    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a sample ModelSpec for testing.
    private static func sampleSpec(
        id: String = "test-model-2b",
        displayName: String = "Test Model 2B"
    ) -> ModelSpec {
        ModelSpec(
            id: id,
            base: .huggingFace(id: "mlx-community/\(id)"),
            contextLength: 4096,
            displayName: displayName,
            description: "Test model",
            estimatedMemoryBytes: 4_500_000_000
        )
    }

    // MARK: - generate (uncached -> load -> infer)

    @Suite("generate")
    struct GenerateTests {

        @Test("loads model and generates tokens when model is not loaded")
        func loadsModelAndGeneratesWhenNotLoaded() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Act
            var tokens: [String] = []
            let stream = await service.generate(model: spec, prompt: "Hello")
            for try await token in stream {
                tokens.append(token)
            }

            // Assert
            #expect(tokens == ["Hello", " ", "World"])
            let loadCalled = await backend.loadModelCalled
            #expect(loadCalled == true)
            let genCalled = await backend.generateCalled
            #expect(genCalled == true)
        }

        @Test("skips loading when model is already loaded")
        func skipsLoadingWhenModelAlreadyLoaded() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Pre-load the model into the backend
            try await backend.loadModel(spec)
            // Reset the flag after initial load
            await backend.resetLoadModelCalled()

            // Act
            var tokens: [String] = []
            let stream = await service.generate(model: spec, prompt: "Hello")
            for try await token in stream {
                tokens.append(token)
            }

            // Assert
            #expect(tokens == ["Hello", " ", "World"])
            let loadCalled = await backend.loadModelCalled
            #expect(loadCalled == false)
            let genCalled = await backend.generateCalled
            #expect(genCalled == true)
        }

        @Test("tracks generation stats after completion")
        func tracksGenerationStats() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Act
            let stream = await service.generate(model: spec, prompt: "Hello")
            for try await _ in stream {}

            // Assert
            let stats = await service.lastGenerationStats
            #expect(stats != nil)
            #expect(stats?.tokenCount == 3) // "Hello", " ", "World"
        }

        @Test("propagates backend load error")
        func propagatesBackendLoadError() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            await backend.setShouldThrow(.loadFailed(modelId: "test", reason: "test error"))
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Act & Assert
            let stream = await service.generate(model: spec, prompt: "Hello")
            await #expect(throws: LLMLocalError.self) {
                for try await _ in stream {}
            }
        }
    }

    // MARK: - isModelCached

    @Suite("isModelCached")
    struct IsModelCachedTests {

        @Test("returns false when model is not registered")
        func returnsFalseWhenNotRegistered() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Act
            let result = await service.isModelCached(spec)

            // Assert
            #expect(result == false)
        }

        @Test("returns true when model is registered")
        func returnsTrueWhenRegistered() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            try await modelRegistry.registerModel(
                LLMLocalServiceTests.sampleSpec(),
                sizeInBytes: 1_000_000
            )
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Act
            let result = await service.isModelCached(spec)

            // Assert
            #expect(result == true)
        }
    }

    // MARK: - prefetch

    @Suite("prefetch")
    struct PrefetchTests {

        @Test("calls backend loadModel")
        func callsBackendLoadModel() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Act
            try await service.prefetch(spec)

            // Assert
            let loadCalled = await backend.loadModelCalled
            #expect(loadCalled == true)
            let currentModel = await backend.currentModel
            #expect(currentModel == spec)
        }

        @Test("propagates load error from backend")
        func propagatesLoadError() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            await backend.setShouldThrow(.loadFailed(modelId: "test", reason: "test error"))
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Act & Assert
            await #expect(throws: LLMLocalError.self) {
                try await service.prefetch(spec)
            }
        }
    }

    // MARK: - Task cancellation

    @Suite("cancellation")
    struct CancellationTests {

        @Test("finishes cleanly when task is cancelled")
        func finishesCleanlyWhenCancelled() async throws {
            // Arrange
            let dir = try LLMLocalServiceTests.makeTempDir()
            defer { LLMLocalServiceTests.removeTempDir(dir) }
            let backend = MockBackend()
            // Use many tokens to give time for cancellation
            await backend.setMockTokens(Array(repeating: "token", count: 1000))
            let modelRegistry = ModelRegistry(cacheDirectory: dir)
            let service = LLMLocalService(backend: backend, modelRegistry: modelRegistry)
            let spec = LLMLocalServiceTests.sampleSpec()

            // Act
            let task = Task {
                var count = 0
                let stream = await service.generate(model: spec, prompt: "Hello")
                for try await _ in stream {
                    count += 1
                    if count >= 2 {
                        break // Simulate partial consumption
                    }
                }
                return count
            }

            let count = try await task.value

            // Assert - should have received some tokens but not all
            #expect(count >= 2)
            #expect(count < 1000)
        }
    }
}
