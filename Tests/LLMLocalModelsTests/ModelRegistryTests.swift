import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocalModels

@Suite("ModelRegistry")
struct ModelRegistryTests {

    // MARK: - Test Helpers

    /// Creates a temporary directory for test isolation.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMLocalModelsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a temporary directory after test use.
    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a sample ModelSpec for testing.
    private static func sampleSpec(
        id: String = "mlx-community/Llama-3.2-1B-Instruct-4bit",
        displayName: String = "Llama 3.2 1B"
    ) -> ModelSpec {
        ModelSpec(
            id: id,
            base: .huggingFace(id: id),
            contextLength: 4096,
            displayName: displayName,
            description: "Test model",
            estimatedMemoryBytes: 4_500_000_000
        )
    }

    // MARK: - cachedModels()

    @Suite("cachedModels")
    struct CachedModelsTests {

        @Test("returns empty list when no models are cached")
        func returnsEmptyListWhenNoModelsCached() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)

            // Act
            let models = await manager.cachedModels()

            // Assert
            #expect(models.isEmpty)
        }

        @Test("returns cached models after registration")
        func returnsCachedModelsAfterRegistration() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()

            // Act
            try await manager.registerModel(spec, sizeInBytes: 500_000)
            let models = await manager.cachedModels()

            // Assert
            #expect(models.count == 1)
            #expect(models[0].modelId == spec.id)
            #expect(models[0].displayName == spec.displayName)
            #expect(models[0].sizeInBytes == 500_000)
        }

        @Test("returns multiple cached models")
        func returnsMultipleCachedModels() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec1 = ModelRegistryTests.sampleSpec(id: "model-a", displayName: "Model A")
            let spec2 = ModelRegistryTests.sampleSpec(id: "model-b", displayName: "Model B")

            // Act
            try await manager.registerModel(spec1, sizeInBytes: 100)
            try await manager.registerModel(spec2, sizeInBytes: 200)
            let models = await manager.cachedModels()

            // Assert
            #expect(models.count == 2)
            let ids = Set(models.map(\.modelId))
            #expect(ids.contains("model-a"))
            #expect(ids.contains("model-b"))
        }
    }

    // MARK: - isCached(_:)

    @Suite("isCached")
    struct IsCachedTests {

        @Test("returns false when model is not cached")
        func returnsFalseWhenModelNotCached() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()

            // Act
            let result = await manager.isCached(spec)

            // Assert
            #expect(result == false)
        }

        @Test("returns true when model is cached")
        func returnsTrueWhenModelIsCached() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()
            try await manager.registerModel(spec, sizeInBytes: 1000)

            // Act
            let result = await manager.isCached(spec)

            // Assert
            #expect(result == true)
        }

        @Test("returns false for different model after registering another")
        func returnsFalseForDifferentModel() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec1 = ModelRegistryTests.sampleSpec(id: "model-a")
            let spec2 = ModelRegistryTests.sampleSpec(id: "model-b")
            try await manager.registerModel(spec1, sizeInBytes: 1000)

            // Act
            let result = await manager.isCached(spec2)

            // Assert
            #expect(result == false)
        }
    }

    // MARK: - totalCacheSize()

    @Suite("totalCacheSize")
    struct TotalCacheSizeTests {

        @Test("returns zero when no models are cached")
        func returnsZeroWhenEmpty() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)

            // Act
            let size = try await manager.totalCacheSize()

            // Assert
            #expect(size == 0)
        }

        @Test("returns sum of all cached model sizes")
        func returnsSumOfCachedSizes() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec1 = ModelRegistryTests.sampleSpec(id: "model-a")
            let spec2 = ModelRegistryTests.sampleSpec(id: "model-b")
            try await manager.registerModel(spec1, sizeInBytes: 1_000_000)
            try await manager.registerModel(spec2, sizeInBytes: 2_500_000)

            // Act
            let size = try await manager.totalCacheSize()

            // Assert
            #expect(size == 3_500_000)
        }

        @Test("returns single model size when only one model cached")
        func returnsSingleModelSize() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()
            try await manager.registerModel(spec, sizeInBytes: 750_000)

            // Act
            let size = try await manager.totalCacheSize()

            // Assert
            #expect(size == 750_000)
        }
    }

    // MARK: - deleteCache(for:)

    @Suite("deleteCache")
    struct DeleteCacheTests {

        @Test("removes a specific model from cache")
        func removesSpecificModel() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()
            try await manager.registerModel(spec, sizeInBytes: 1000)

            // Act
            try await manager.deleteCache(for: spec)

            // Assert
            let isCached = await manager.isCached(spec)
            #expect(isCached == false)
            let models = await manager.cachedModels()
            #expect(models.isEmpty)
        }

        @Test("does not affect other cached models")
        func doesNotAffectOtherModels() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec1 = ModelRegistryTests.sampleSpec(id: "model-a", displayName: "Model A")
            let spec2 = ModelRegistryTests.sampleSpec(id: "model-b", displayName: "Model B")
            try await manager.registerModel(spec1, sizeInBytes: 1000)
            try await manager.registerModel(spec2, sizeInBytes: 2000)

            // Act
            try await manager.deleteCache(for: spec1)

            // Assert
            let isCachedA = await manager.isCached(spec1)
            let isCachedB = await manager.isCached(spec2)
            #expect(isCachedA == false)
            #expect(isCachedB == true)
            let models = await manager.cachedModels()
            #expect(models.count == 1)
            #expect(models[0].modelId == "model-b")
        }

        @Test("updates total cache size after deletion")
        func updatesTotalCacheSizeAfterDeletion() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec1 = ModelRegistryTests.sampleSpec(id: "model-a")
            let spec2 = ModelRegistryTests.sampleSpec(id: "model-b")
            try await manager.registerModel(spec1, sizeInBytes: 1_000_000)
            try await manager.registerModel(spec2, sizeInBytes: 2_000_000)

            // Act
            try await manager.deleteCache(for: spec1)
            let size = try await manager.totalCacheSize()

            // Assert
            #expect(size == 2_000_000)
        }

        @Test("succeeds silently when model is not cached")
        func succeedsSilentlyWhenNotCached() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()

            // Act & Assert - should not throw
            try await manager.deleteCache(for: spec)
        }
    }

    // MARK: - clearAllCache()

    @Suite("clearAllCache")
    struct ClearAllCacheTests {

        @Test("removes all cached models")
        func removesAllCachedModels() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec1 = ModelRegistryTests.sampleSpec(id: "model-a")
            let spec2 = ModelRegistryTests.sampleSpec(id: "model-b")
            try await manager.registerModel(spec1, sizeInBytes: 1000)
            try await manager.registerModel(spec2, sizeInBytes: 2000)

            // Act
            try await manager.clearAllCache()

            // Assert
            let models = await manager.cachedModels()
            #expect(models.isEmpty)
            let size = try await manager.totalCacheSize()
            #expect(size == 0)
        }

        @Test("succeeds when cache is already empty")
        func succeedsWhenCacheAlreadyEmpty() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)

            // Act & Assert - should not throw
            try await manager.clearAllCache()
            let models = await manager.cachedModels()
            #expect(models.isEmpty)
        }
    }

    // MARK: - Registry Persistence

    @Suite("persistence")
    struct PersistenceTests {

        @Test("persists registry to disk after registration")
        func persistsRegistryToDisk() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let spec = ModelRegistryTests.sampleSpec()

            // Act - register with one registry instance
            let registry1 = ModelRegistry(cacheDirectory: dir)
            try await registry1.registerModel(spec, sizeInBytes: 1000)

            // Assert - create new registry instance and verify data persists
            let registry2 = ModelRegistry(cacheDirectory: dir)
            let models = await registry2.cachedModels()
            #expect(models.count == 1)
            #expect(models[0].modelId == spec.id)
        }

        @Test("persists deletion to disk")
        func persistsDeletionToDisk() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let spec = ModelRegistryTests.sampleSpec()
            let registry1 = ModelRegistry(cacheDirectory: dir)
            try await registry1.registerModel(spec, sizeInBytes: 1000)

            // Act
            try await registry1.deleteCache(for: spec)

            // Assert - new instance should see empty registry
            let registry2 = ModelRegistry(cacheDirectory: dir)
            let models = await registry2.cachedModels()
            #expect(models.isEmpty)
        }

        @Test("persists clearAllCache to disk")
        func persistsClearAllToDisk() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let registry1 = ModelRegistry(cacheDirectory: dir)
            let spec1 = ModelRegistryTests.sampleSpec(id: "model-a")
            let spec2 = ModelRegistryTests.sampleSpec(id: "model-b")
            try await registry1.registerModel(spec1, sizeInBytes: 100)
            try await registry1.registerModel(spec2, sizeInBytes: 200)

            // Act
            try await registry1.clearAllCache()

            // Assert - new instance should see empty registry
            let registry2 = ModelRegistry(cacheDirectory: dir)
            let models = await registry2.cachedModels()
            #expect(models.isEmpty)
        }
    }

    // MARK: - registerModel

    @Suite("registerModel")
    struct RegisterModelTests {

        @Test("sets downloadedAt and localPath automatically")
        func setsDownloadedAtAndLocalPath() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()
            let before = Date()

            // Act
            try await manager.registerModel(spec, sizeInBytes: 1000)

            // Assert
            let models = await manager.cachedModels()
            #expect(models.count == 1)
            let info = models[0]
            #expect(info.downloadedAt >= before)
            #expect(info.downloadedAt <= Date())
        }

        @Test("overwrites existing entry for same model id")
        func overwritesExistingEntry() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()

            // Act
            try await manager.registerModel(spec, sizeInBytes: 1000)
            try await manager.registerModel(spec, sizeInBytes: 2000)

            // Assert - should have only one entry with updated size
            let models = await manager.cachedModels()
            #expect(models.count == 1)
            #expect(models[0].sizeInBytes == 2000)
        }
    }

    // MARK: - File Deletion

    @Suite("fileDeletion")
    struct FileDeletionTests {

        @Test("deleteCache removes model files from disk")
        func deleteCacheRemovesFiles() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }

            // Create dummy model files directory
            let modelFilesDir = dir.appendingPathComponent("hf-cache/test-model")
            try FileManager.default.createDirectory(
                at: modelFilesDir, withIntermediateDirectories: true
            )
            // Create a dummy weight file
            let weightFile = modelFilesDir.appendingPathComponent("model.safetensors")
            try Data("fake weights".utf8).write(to: weightFile)

            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()
            try await manager.registerModel(
                spec, sizeInBytes: 1000, modelFilesPath: modelFilesDir
            )

            // Verify file exists
            #expect(FileManager.default.fileExists(atPath: modelFilesDir.path))

            // Act
            try await manager.deleteCache(for: spec)

            // Assert - files should be deleted
            #expect(!FileManager.default.fileExists(atPath: modelFilesDir.path))
            let isCached = await manager.isCached(spec)
            #expect(isCached == false)
        }

        @Test("clearAllCache removes all model files from disk")
        func clearAllCacheRemovesFiles() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }

            let filesDir1 = dir.appendingPathComponent("hf-cache/model-a")
            let filesDir2 = dir.appendingPathComponent("hf-cache/model-b")
            try FileManager.default.createDirectory(
                at: filesDir1, withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: filesDir2, withIntermediateDirectories: true
            )
            try Data("weights1".utf8).write(
                to: filesDir1.appendingPathComponent("model.safetensors")
            )
            try Data("weights2".utf8).write(
                to: filesDir2.appendingPathComponent("model.safetensors")
            )

            let manager = ModelRegistry(cacheDirectory: dir)
            let spec1 = ModelRegistryTests.sampleSpec(id: "model-a")
            let spec2 = ModelRegistryTests.sampleSpec(id: "model-b")
            try await manager.registerModel(
                spec1, sizeInBytes: 100, modelFilesPath: filesDir1
            )
            try await manager.registerModel(
                spec2, sizeInBytes: 200, modelFilesPath: filesDir2
            )

            // Act
            try await manager.clearAllCache()

            // Assert
            #expect(!FileManager.default.fileExists(atPath: filesDir1.path))
            #expect(!FileManager.default.fileExists(atPath: filesDir2.path))
            let models = await manager.cachedModels()
            #expect(models.isEmpty)
        }

        @Test("deleteCache without modelFilesPath only removes metadata")
        func deleteCacheWithoutFilesPath() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }
            let manager = ModelRegistry(cacheDirectory: dir)
            let spec = ModelRegistryTests.sampleSpec()
            try await manager.registerModel(spec, sizeInBytes: 1000)

            // Act & Assert - should not throw
            try await manager.deleteCache(for: spec)
            let isCached = await manager.isCached(spec)
            #expect(isCached == false)
        }
    }

    // MARK: - Default init

    @Suite("init")
    struct InitTests {

        @Test("initializes with custom cache directory")
        func initializesWithCustomDirectory() async throws {
            // Arrange
            let dir = try ModelRegistryTests.makeTempDir()
            defer { ModelRegistryTests.removeTempDir(dir) }

            // Act
            let manager = ModelRegistry(cacheDirectory: dir)
            let models = await manager.cachedModels()

            // Assert
            #expect(models.isEmpty)
        }

        @Test("initializes with default cache directory")
        func initializesWithDefaultDirectory() async {
            // Act - should not crash with nil (uses default)
            let registry = ModelRegistry()
            let models = await registry.cachedModels()

            // Assert
            #expect(models.isEmpty)
        }
    }
}
