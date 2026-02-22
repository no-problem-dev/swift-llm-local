import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocalModels

// MARK: - Test Helpers

/// Mock network delegate for testing adapter downloads.
struct MockAdapterNetworkDelegate: AdapterNetworkDelegate, Sendable {
    let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func downloadGitHubRelease(
        repo: String, tag: String, asset: String, destination: URL
    ) async throws {
        if shouldThrow {
            throw LLMLocalError.downloadFailed(modelId: repo, reason: "mock error")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("mock-adapter-\(tag)".utf8).write(to: destination)
    }

    func downloadHuggingFace(id: String, destination: URL) async throws {
        if shouldThrow {
            throw LLMLocalError.downloadFailed(modelId: id, reason: "mock error")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("mock-hf-adapter".utf8).write(to: destination)
    }
}

@Suite("AdapterManager")
struct AdapterManagerTests {

    // MARK: - Test Helpers

    /// Creates a temporary directory for test isolation.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdapterManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a temporary directory after test use.
    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - cacheKey

    @Suite("cacheKey")
    struct CacheKeyTests {

        @Test("generates correct key for GitHub Release source")
        func generatesKeyForGitHubRelease() {
            // Arrange
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )

            // Act
            let key = AdapterManager.cacheKey(for: source)

            // Assert
            #expect(key == "gh--owner--repo--v1.0--adapter.safetensors")
        }

        @Test("generates correct key for HuggingFace source")
        func generatesKeyForHuggingFace() {
            // Arrange
            let source = AdapterSource.huggingFace(id: "user/adapter-model")

            // Act
            let key = AdapterManager.cacheKey(for: source)

            // Assert
            #expect(key == "hf--user--adapter-model")
        }

        @Test("generates correct key for local source")
        func generatesKeyForLocal() {
            // Arrange
            let source = AdapterSource.local(
                path: URL(fileURLWithPath: "/tmp/adapters/my-adapter")
            )

            // Act
            let key = AdapterManager.cacheKey(for: source)

            // Assert
            #expect(key == "local--my-adapter")
        }
    }

    // MARK: - resolve

    @Suite("resolve")
    struct ResolveTests {

        @Test("returns local path directly when file exists")
        func returnsLocalPathDirectly() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let localFile = dir.appendingPathComponent("local-adapter.safetensors")
            try Data("local-adapter-data".utf8).write(to: localFile)
            let source = AdapterSource.local(path: localFile)
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )

            // Act
            let result = try await manager.resolve(source)

            // Assert
            #expect(result == localFile)
        }

        @Test("throws when local adapter file not found")
        func throwsWhenLocalNotFound() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let nonExistentFile = dir.appendingPathComponent("non-existent.safetensors")
            let source = AdapterSource.local(path: nonExistentFile)
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )

            // Act & Assert
            await #expect(throws: LLMLocalError.self) {
                try await manager.resolve(source)
            }
        }

        @Test("downloads and caches GitHub Release adapter")
        func downloadsAndCachesGitHubRelease() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )

            // Act
            let result = try await manager.resolve(source)

            // Assert
            #expect(FileManager.default.fileExists(atPath: result.path()))
            let isCached = await manager.isCached(source)
            #expect(isCached == true)
        }

        @Test("returns cached path on second resolve without re-download")
        func returnsCachedOnSecondResolve() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )

            // Act
            let firstResult = try await manager.resolve(source)
            let secondResult = try await manager.resolve(source)

            // Assert
            #expect(firstResult == secondResult)
        }

        @Test("downloads and caches HuggingFace adapter")
        func downloadsAndCachesHuggingFace() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.huggingFace(id: "user/adapter-model")
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )

            // Act
            let result = try await manager.resolve(source)

            // Assert
            #expect(FileManager.default.fileExists(atPath: result.path()))
            let isCached = await manager.isCached(source)
            #expect(isCached == true)
        }

        @Test("throws when GitHub Release download fails")
        func throwsWhenGitHubDownloadFails() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate(shouldThrow: true)
            )

            // Act & Assert
            await #expect(throws: LLMLocalError.self) {
                try await manager.resolve(source)
            }
        }
    }

    // MARK: - isUpdateAvailable

    @Suite("isUpdateAvailable")
    struct IsUpdateAvailableTests {

        @Test("returns true when adapter is not cached")
        func returnsTrueWhenNotCached() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )

            // Act
            let result = await manager.isUpdateAvailable(for: source, latestTag: "v2.0")

            // Assert
            #expect(result == true)
        }

        @Test("returns false when version matches")
        func returnsFalseWhenVersionMatches() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )
            // Cache the adapter first
            _ = try await manager.resolve(source)

            // Act
            let result = await manager.isUpdateAvailable(for: source, latestTag: "v1.0")

            // Assert
            #expect(result == false)
        }

        @Test("returns true when version differs")
        func returnsTrueWhenVersionDiffers() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )
            // Cache the adapter with v1.0
            _ = try await manager.resolve(source)

            // Act
            let result = await manager.isUpdateAvailable(for: source, latestTag: "v2.0")

            // Assert
            #expect(result == true)
        }
    }

    // MARK: - cachedAdapters

    @Suite("cachedAdapters")
    struct CachedAdaptersTests {

        @Test("returns empty list initially")
        func returnsEmptyListInitially() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )

            // Act
            let adapters = await manager.cachedAdapters()

            // Assert
            #expect(adapters.isEmpty)
        }

        @Test("returns all cached adapters")
        func returnsAllCachedAdapters() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )
            let source1 = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter1.safetensors"
            )
            let source2 = AdapterSource.huggingFace(id: "user/adapter-model")
            _ = try await manager.resolve(source1)
            _ = try await manager.resolve(source2)

            // Act
            let adapters = await manager.cachedAdapters()

            // Assert
            #expect(adapters.count == 2)
            let keys = Set(adapters.map(\.key))
            #expect(keys.contains(AdapterManager.cacheKey(for: source1)))
            #expect(keys.contains(AdapterManager.cacheKey(for: source2)))
        }
    }

    // MARK: - isCached

    @Suite("isCached")
    struct IsCachedTests {

        @Test("returns false for uncached adapter")
        func returnsFalseForUncached() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )

            // Act
            let result = await manager.isCached(source)

            // Assert
            #expect(result == false)
        }

        @Test("returns true for cached adapter")
        func returnsTrueForCached() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )
            _ = try await manager.resolve(source)

            // Act
            let result = await manager.isCached(source)

            // Assert
            #expect(result == true)
        }
    }

    // MARK: - deleteAdapter

    @Suite("deleteAdapter")
    struct DeleteAdapterTests {

        @Test("removes specific adapter from cache")
        func removesSpecificAdapter() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source1 = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter1.safetensors"
            )
            let source2 = AdapterSource.huggingFace(id: "user/adapter-model")
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )
            _ = try await manager.resolve(source1)
            _ = try await manager.resolve(source2)

            // Act
            try await manager.deleteAdapter(for: source1)

            // Assert
            let isCached1 = await manager.isCached(source1)
            let isCached2 = await manager.isCached(source2)
            #expect(isCached1 == false)
            #expect(isCached2 == true)
            let adapters = await manager.cachedAdapters()
            #expect(adapters.count == 1)
        }
    }

    // MARK: - clearAll

    @Suite("clearAll")
    struct ClearAllTests {

        @Test("removes all adapters from cache")
        func removesAllAdapters() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let manager = AdapterManager(
                adapterDirectory: dir,
                networkDelegate: MockAdapterNetworkDelegate()
            )
            let source1 = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter1.safetensors"
            )
            let source2 = AdapterSource.huggingFace(id: "user/adapter-model")
            _ = try await manager.resolve(source1)
            _ = try await manager.resolve(source2)

            // Act
            try await manager.clearAll()

            // Assert
            let adapters = await manager.cachedAdapters()
            #expect(adapters.isEmpty)
        }
    }

    // MARK: - Persistence

    @Suite("persistence")
    struct PersistenceTests {

        @Test("persists registry to disk after resolve")
        func persistsRegistryToDisk() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let mockDelegate = MockAdapterNetworkDelegate()

            // Act - resolve with one manager instance
            let manager1 = AdapterManager(
                adapterDirectory: dir, networkDelegate: mockDelegate
            )
            _ = try await manager1.resolve(source)

            // Assert - create new manager instance and verify data persists
            let manager2 = AdapterManager(
                adapterDirectory: dir, networkDelegate: mockDelegate
            )
            let adapters = await manager2.cachedAdapters()
            #expect(adapters.count == 1)
            #expect(adapters[0].key == AdapterManager.cacheKey(for: source))
        }

        @Test("loads registry from disk on new instance")
        func loadsRegistryFromDisk() async throws {
            // Arrange
            let dir = try AdapterManagerTests.makeTempDir()
            defer { AdapterManagerTests.removeTempDir(dir) }
            let source1 = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )
            let source2 = AdapterSource.huggingFace(id: "user/adapter-model")
            let mockDelegate = MockAdapterNetworkDelegate()

            // Act - resolve adapters with first instance
            let manager1 = AdapterManager(
                adapterDirectory: dir, networkDelegate: mockDelegate
            )
            _ = try await manager1.resolve(source1)
            _ = try await manager1.resolve(source2)

            // Assert - new instance should load both
            let manager2 = AdapterManager(
                adapterDirectory: dir, networkDelegate: mockDelegate
            )
            let adapters = await manager2.cachedAdapters()
            #expect(adapters.count == 2)
            let isCached1 = await manager2.isCached(source1)
            let isCached2 = await manager2.isCached(source2)
            #expect(isCached1 == true)
            #expect(isCached2 == true)
        }
    }
}
