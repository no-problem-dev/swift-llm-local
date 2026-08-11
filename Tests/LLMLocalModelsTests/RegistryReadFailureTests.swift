import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocalModels

// MARK: - Helpers

/// Runs the operation and hands back whatever it threw, or `nil` when it returned normally.
///
/// Written this way rather than with `#expect(throws:)` so the assertion at the call site is
/// about *which* case was thrown. An unreadable registry that threw some other error would be as
/// wrong as one that threw nothing.
private func errorThrown(
    by operation: () async throws -> Void
) async -> (any Error)? {
    do {
        try await operation()
        return nil
    } catch {
        return error
    }
}

/// Whether the error is the one the registries raise for a registry file they could not read.
private func isRegistryUnreadable(_ error: (any Error)?) -> Bool {
    if case .registryUnreadable = error as? LLMLocalError { return true }
    return false
}

/// Records whether it was ever asked to fetch anything.
///
/// A registry that treated an unreadable file as empty would re-download every adapter it had
/// already fetched, over the files still sitting at those paths. Counting the calls is how that
/// shows up in a test.
private actor CountingAdapterNetworkDelegate: AdapterNetworkDelegate {

    private(set) var downloadCount = 0

    func downloadGitHubRelease(
        repo: String, tag: String, asset: String, destination: URL
    ) async throws {
        downloadCount += 1
        try write(to: destination)
    }

    func downloadHuggingFace(id: String, destination: URL) async throws {
        downloadCount += 1
        try write(to: destination)
    }

    private func write(to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("counted-adapter".utf8).write(to: destination)
    }
}

// MARK: - Tests

/// A registry file that cannot be read must not reach the caller as an empty registry.
///
/// Every test here contrasts the two states rather than asserting on one of them, because the
/// failure being guarded against is precisely that they become the same answer. The store these
/// registries are built on distinguishes them — a missing file reads as empty, a file that will
/// not decode throws — and these tests hold the registries to the same distinction.
///
/// The file-backed store is used deliberately: `InMemoryRegistryStore` has no stored form to be
/// unreadable, so its `load()` cannot fail and it cannot exercise this at all.
@Suite("Registry read failure")
struct RegistryReadFailureTests {

    // MARK: - Fixtures

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RegistryReadFailureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// JSON cut off part-way through, as an interrupted or truncated write leaves it.
    private static let truncatedJSON = Data(#"{"llama-3.2-1b": {"modelId": "llama-3.2"#.utf8)

    /// Well-formed JSON whose entries no longer match the entry type.
    ///
    /// This is what a schema change looks like from the read side, and it is the likeliest way a
    /// real device reaches this state — far likelier than a truncated file.
    private static let staleSchemaJSON = Data(#"{"llama-3.2-1b": {"name": "Llama"}}"#.utf8)

    private static func sampleSpec(id: String = "llama-3.2-1b") -> ModelSpec {
        ModelSpec(
            id: id,
            base: .huggingFace(id: "mlx-community/\(id)"),
            contextLength: 4096,
            displayName: "Llama 3.2 1B",
            description: "Test model",
            estimatedMemoryBytes: 1_500_000_000
        )
    }

    private static let modelRegistryFilename = "registry.json"
    private static let adapterRegistryFilename = "adapter-registry.json"

    // MARK: - ModelRegistry

    @Suite("ModelRegistry")
    struct ModelRegistryReadFailureTests {

        @Test("an unreadable registry is not an empty registry")
        func unreadableIsNotEmpty() async throws {
            // Arrange: two registries, one never written and one that will not decode.
            let emptyDir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(emptyDir) }
            let corruptDir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(corruptDir) }
            try RegistryReadFailureTests.truncatedJSON.write(
                to: corruptDir.appendingPathComponent(
                    RegistryReadFailureTests.modelRegistryFilename
                )
            )
            let neverWritten = try ModelRegistry(cacheDirectory: emptyDir)
            let unreadable = try ModelRegistry(cacheDirectory: corruptDir)

            // Act
            let models = try await neverWritten.cachedModels()
            let error = await errorThrown { _ = try await unreadable.cachedModels() }

            // Assert
            #expect(models.isEmpty)
            #expect(
                isRegistryUnreadable(error),
                """
                an unreadable registry must not answer with the empty list that means \
                'nothing is downloaded'; got \(String(describing: error))
                """
            )
        }

        @Test("a registry whose entries no longer decode is unreadable, not empty")
        func staleSchemaIsUnreadable() async throws {
            // Arrange
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            try RegistryReadFailureTests.staleSchemaJSON.write(
                to: dir.appendingPathComponent(RegistryReadFailureTests.modelRegistryFilename)
            )
            let registry = try ModelRegistry(cacheDirectory: dir)

            // Act
            let error = await errorThrown { _ = try await registry.cachedModels() }

            // Assert
            #expect(
                isRegistryUnreadable(error),
                """
                valid JSON that no longer matches CachedModelInfo is a registry that cannot be \
                read, not one that is empty; got \(String(describing: error))
                """
            )
        }

        @Test("isCached does not answer false for a registry it could not read")
        func isCachedDoesNotAnswerFalse() async throws {
            // Arrange
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            try RegistryReadFailureTests.truncatedJSON.write(
                to: dir.appendingPathComponent(RegistryReadFailureTests.modelRegistryFilename)
            )
            let registry = try ModelRegistry(cacheDirectory: dir)
            let spec = RegistryReadFailureTests.sampleSpec()

            // Act
            let error = await errorThrown { _ = try await registry.isCached(spec) }

            // Assert
            #expect(
                isRegistryUnreadable(error),
                """
                false would send the caller off to re-download a model that may already be on \
                disk; got \(String(describing: error))
                """
            )
        }

        @Test("totalCacheSize does not answer zero for a registry it could not read")
        func totalCacheSizeDoesNotAnswerZero() async throws {
            // Arrange
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            try RegistryReadFailureTests.truncatedJSON.write(
                to: dir.appendingPathComponent(RegistryReadFailureTests.modelRegistryFilename)
            )
            let registry = try ModelRegistry(cacheDirectory: dir)

            // Act
            let error = await errorThrown { _ = try await registry.totalCacheSize() }

            // Assert
            #expect(
                isRegistryUnreadable(error),
                "zero reads as 'nothing is using disk'; got \(String(describing: error))"
            )
        }

        @Test("registering a model does not overwrite a registry that could not be read")
        func registerModelLeavesUnreadableFileIntact() async throws {
            // Arrange
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            let file = dir.appendingPathComponent(
                RegistryReadFailureTests.modelRegistryFilename
            )
            let original = RegistryReadFailureTests.truncatedJSON
            try original.write(to: file)
            let registry = try ModelRegistry(cacheDirectory: dir)

            // Act
            let error = await errorThrown {
                try await registry.registerModel(
                    RegistryReadFailureTests.sampleSpec(), sizeInBytes: 1_000
                )
            }

            // Assert
            #expect(isRegistryUnreadable(error), "got \(String(describing: error))")
            #expect(
                try Data(contentsOf: file) == original,
                """
                every mutating method is a load-mutate-save over the whole file: a registry that \
                read the unreadable file as empty would write one entry over it, destroying the \
                evidence of the failure and orphaning the model directories the lost entries \
                pointed at
                """
            )
        }

        @Test("clearing the cache does not overwrite a registry that could not be read")
        func clearAllCacheLeavesUnreadableFileIntact() async throws {
            // Arrange
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            let file = dir.appendingPathComponent(
                RegistryReadFailureTests.modelRegistryFilename
            )
            let original = RegistryReadFailureTests.staleSchemaJSON
            try original.write(to: file)
            let registry = try ModelRegistry(cacheDirectory: dir)

            // Act
            let error = await errorThrown { try await registry.clearAllCache() }

            // Assert
            #expect(isRegistryUnreadable(error), "got \(String(describing: error))")
            #expect(
                try Data(contentsOf: file) == original,
                """
                clearing a registry that was read as empty would report success while leaving \
                every model file on disk with nothing left pointing at it
                """
            )
        }

        @Test("a repaired registry is read on the next call, not remembered as failed")
        func recoversOnceTheFileIsRemoved() async throws {
            // Arrange
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            let file = dir.appendingPathComponent(
                RegistryReadFailureTests.modelRegistryFilename
            )
            try RegistryReadFailureTests.truncatedJSON.write(to: file)
            let registry = try ModelRegistry(cacheDirectory: dir)
            let firstError = await errorThrown { _ = try await registry.cachedModels() }
            #expect(isRegistryUnreadable(firstError), "got \(String(describing: firstError))")

            // Act: the app resolves it the only way it can — by discarding the broken file.
            try FileManager.default.removeItem(at: file)

            // Assert: nothing was cached from the failure, so the same instance recovers.
            let models = try await registry.cachedModels()
            #expect(models.isEmpty)
            try await registry.registerModel(
                RegistryReadFailureTests.sampleSpec(), sizeInBytes: 2_000
            )
            #expect(try await registry.cachedModels().count == 1)
        }
    }

    // MARK: - AdapterRegistry

    @Suite("AdapterRegistry")
    struct AdapterRegistryReadFailureTests {

        @Test("an unreadable registry is not an empty registry")
        func unreadableIsNotEmpty() async throws {
            // Arrange
            let emptyDir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(emptyDir) }
            let corruptDir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(corruptDir) }
            try RegistryReadFailureTests.truncatedJSON.write(
                to: corruptDir.appendingPathComponent(
                    RegistryReadFailureTests.adapterRegistryFilename
                )
            )
            let neverWritten = try AdapterRegistry(adapterDirectory: emptyDir)
            let unreadable = try AdapterRegistry(adapterDirectory: corruptDir)

            // Act
            let adapters = try await neverWritten.cachedAdapters()
            let error = await errorThrown { _ = try await unreadable.cachedAdapters() }

            // Assert
            #expect(adapters.isEmpty)
            #expect(
                isRegistryUnreadable(error),
                "got \(String(describing: error))"
            )
        }

        @Test("isCached does not answer false for a registry it could not read")
        func isCachedDoesNotAnswerFalse() async throws {
            // Arrange
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            try RegistryReadFailureTests.truncatedJSON.write(
                to: dir.appendingPathComponent(RegistryReadFailureTests.adapterRegistryFilename)
            )
            let registry = try AdapterRegistry(adapterDirectory: dir)
            let source = AdapterSource.huggingFace(id: "user/adapter")

            // Act
            let error = await errorThrown { _ = try await registry.isCached(source) }

            // Assert
            #expect(isRegistryUnreadable(error), "got \(String(describing: error))")
        }

        @Test("isUpdateAvailable does not answer true for a registry it could not read")
        func isUpdateAvailableDoesNotAnswerTrue() async throws {
            // Arrange
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            try RegistryReadFailureTests.truncatedJSON.write(
                to: dir.appendingPathComponent(RegistryReadFailureTests.adapterRegistryFilename)
            )
            let registry = try AdapterRegistry(adapterDirectory: dir)
            let source = AdapterSource.gitHubRelease(
                repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
            )

            // Act
            let error = await errorThrown {
                _ = try await registry.isUpdateAvailable(for: source, latestTag: "v2.0")
            }

            // Assert
            #expect(
                isRegistryUnreadable(error),
                """
                an unrecorded adapter answers true, so an unreadable registry answering true \
                would read as 'go and fetch it'; got \(String(describing: error))
                """
            )
        }

        @Test("resolve asks for no download when the registry could not be read")
        func resolveDownloadsNothing() async throws {
            // Arrange: the registry already records this adapter, but the file will not decode,
            // so the entry that would have prevented a download cannot be seen.
            let dir = try RegistryReadFailureTests.makeTempDir()
            defer { RegistryReadFailureTests.removeTempDir(dir) }
            let file = dir.appendingPathComponent(
                RegistryReadFailureTests.adapterRegistryFilename
            )
            let original = RegistryReadFailureTests.truncatedJSON
            try original.write(to: file)
            let delegate = CountingAdapterNetworkDelegate()
            let registry = try AdapterRegistry(
                adapterDirectory: dir, networkDelegate: delegate
            )
            let source = AdapterSource.huggingFace(id: "user/adapter")

            // Act
            let error = await errorThrown { _ = try await registry.resolve(source) }

            // Assert
            #expect(isRegistryUnreadable(error), "got \(String(describing: error))")
            #expect(
                await delegate.downloadCount == 0,
                """
                resolving against a registry read as empty re-fetches every adapter over the \
                files already at those paths
                """
            )
            #expect(
                try Data(contentsOf: file) == original,
                "and then writes the result over the registry that could not be read"
            )
        }
    }
}
