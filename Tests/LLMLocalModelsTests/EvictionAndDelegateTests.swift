import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocalModels

// MARK: - Helpers

private func errorThrown(by operation: () async throws -> Void) async -> (any Error)? {
    do {
        try await operation()
        return nil
    } catch {
        return error
    }
}

/// Builds a temporary tree and can make part of it undeletable.
///
/// Deletion is blocked by taking write permission off the *parent*, which is what denies `unlink`.
/// The directory itself stays readable, so its contents are still there and still occupying the
/// storage the caller believes was reclaimed.
private struct EvictionFixture: ~Copyable {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("eviction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        if let walk = FileManager.default.enumerator(atPath: root.path) {
            for case let name as String in walk {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: root.appendingPathComponent(name).path
                )
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    var registryDirectory: URL { root.appendingPathComponent("registry", isDirectory: true) }

    /// A model files directory holding one file, optionally locked against deletion.
    func modelFiles(named name: String, deletable: Bool) throws -> URL {
        let parent = root.appendingPathComponent("\(name)-parent", isDirectory: true)
        let files = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2048).write(to: files.appendingPathComponent("weights.bin"))
        if !deletable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o555], ofItemAtPath: parent.path
            )
        }
        return files
    }

    func spec(_ id: String) -> ModelSpec {
        ModelSpec(
            id: id, base: .huggingFace(id: "mlx-community/\(id)"), contextLength: 4096,
            displayName: id, description: "", estimatedMemoryBytes: 1_000_000
        )
    }
}

private var permissionsAreEnforced: Bool { geteuid() != 0 }

// MARK: - #6 Eviction

/// Eviction that frees nothing must not report that it did.
///
/// Dropping the entry anyway is not a smaller version of succeeding — it is worse than failing. The
/// entry was the last thing pointing at those gigabytes, and `deleteCache(for:)` is the only thing
/// that would ever have used it to free them. This is the same argument the registry already makes
/// for refusing to overwrite a file it could not read.
@Suite("Model eviction failure", .enabled(if: permissionsAreEnforced))
struct ModelEvictionFailureTests {

    @Test("an eviction that could not delete the files keeps the entry that points at them")
    func failedDeleteKeepsEntry() async throws {
        // Arrange: two models, identical but for whether their files can be removed.
        let fixture = try EvictionFixture()
        let registry = try ModelRegistry(cacheDirectory: fixture.registryDirectory)
        let freeable = fixture.spec("freeable")
        let stuck = fixture.spec("stuck")
        let freeableFiles = try fixture.modelFiles(named: "freeable", deletable: true)
        let stuckFiles = try fixture.modelFiles(named: "stuck", deletable: false)
        try await registry.registerModel(freeable, sizeInBytes: 2048, modelFilesPath: freeableFiles)
        try await registry.registerModel(stuck, sizeInBytes: 2048, modelFilesPath: stuckFiles)

        // Act
        try await registry.deleteCache(for: freeable)
        let error = await errorThrown { try await registry.deleteCache(for: stuck) }

        // Assert
        #expect(try await registry.isCached(freeable) == false)
        #expect(!FileManager.default.fileExists(atPath: freeableFiles.path))
        #expect(error != nil, "the files are still there and the caller was told they were freed")
        #expect(
            try await registry.isCached(stuck) == true,
            """
            removing the entry leaves gigabytes on disk with nothing pointing at them — \
            deleteCache(for:) is the only thing that could ever have freed them, and it needs the \
            entry to find them
            """
        )
        #expect(FileManager.default.fileExists(atPath: stuckFiles.path))
    }

    @Test("clearing keeps what it could not delete and reports the failure")
    func clearAllKeepsWhatItCouldNotDelete() async throws {
        // Arrange
        let fixture = try EvictionFixture()
        let registry = try ModelRegistry(cacheDirectory: fixture.registryDirectory)
        let freeable = fixture.spec("freeable")
        let stuck = fixture.spec("stuck")
        let freeableFiles = try fixture.modelFiles(named: "freeable", deletable: true)
        let stuckFiles = try fixture.modelFiles(named: "stuck", deletable: false)
        try await registry.registerModel(freeable, sizeInBytes: 2048, modelFilesPath: freeableFiles)
        try await registry.registerModel(stuck, sizeInBytes: 2048, modelFilesPath: stuckFiles)

        // Act
        let error = await errorThrown { try await registry.clearAllCache() }

        // Assert
        #expect(error != nil)
        let remaining = try await registry.cachedModels().map(\.modelId).sorted()
        #expect(
            remaining == ["stuck"],
            """
            the work that succeeded is kept, and the entry whose files are still on disk is the one \
            left behind — reading the registry afterwards tells the caller exactly what is still \
            holding storage
            """
        )
        #expect(FileManager.default.fileExists(atPath: stuckFiles.path))
    }

    /// Files the user already removed through iOS storage management satisfy eviction.
    @Test("an entry whose files are already gone evicts cleanly")
    func alreadyDeletedFilesEvictCleanly() async throws {
        // Arrange
        let fixture = try EvictionFixture()
        let registry = try ModelRegistry(cacheDirectory: fixture.registryDirectory)
        let spec = fixture.spec("vanished")
        let files = try fixture.modelFiles(named: "vanished", deletable: true)
        try await registry.registerModel(spec, sizeInBytes: 2048, modelFilesPath: files)
        try FileManager.default.removeItem(at: files)

        // Act & Assert
        try await registry.deleteCache(for: spec)
        #expect(try await registry.isCached(spec) == false)
    }

    /// Persisted, not just dropped from memory.
    @Test("a kept entry survives into the saved registry")
    func keptEntryIsPersisted() async throws {
        // Arrange
        let fixture = try EvictionFixture()
        let registry = try ModelRegistry(cacheDirectory: fixture.registryDirectory)
        let stuck = fixture.spec("stuck")
        let stuckFiles = try fixture.modelFiles(named: "stuck", deletable: false)
        try await registry.registerModel(stuck, sizeInBytes: 2048, modelFilesPath: stuckFiles)
        _ = await errorThrown { try await registry.clearAllCache() }

        // Act: a fresh registry over the same directory reads from the file.
        let reopened = try ModelRegistry(cacheDirectory: fixture.registryDirectory)

        // Assert
        #expect(try await reopened.isCached(stuck) == true)
    }
}

// MARK: - #7 No delegate is not a completed download

/// Records whether it was ever asked to fetch anything.
private actor CountingNetworkDelegate: AdapterNetworkDelegate {
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
            at: destination, withIntermediateDirectories: true
        )
        try Data("weights".utf8).write(to: destination.appendingPathComponent("adapter.safetensors"))
    }
}

/// A default that fabricates success is the strongest form of this pattern.
///
/// The stub that used to fill this gap wrote a 13-byte text file and let the registry record it as
/// a cached adapter, so the next `resolve(_:)` returned that path without downloading anything, and
/// the mismatch only surfaced as an MLX load failure — after the multi-gigabyte base model had
/// already been fetched. It is what a caller who forgot to wire a downloader got.
@Suite("Adapter registry without a network delegate")
struct AdapterRegistryMissingDelegateTests {

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-no-delegate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("resolving a remote adapter without a delegate fails instead of recording a placeholder")
    func remoteResolveFailsWithoutDelegate() async throws {
        // Arrange: same call, two registries — one wired, one not.
        let wiredDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: wiredDir) }
        let bareDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: bareDir) }
        let delegate = CountingNetworkDelegate()
        let wired = try AdapterRegistry(adapterDirectory: wiredDir, networkDelegate: delegate)
        let bare = try AdapterRegistry(adapterDirectory: bareDir)
        let source = AdapterSource.huggingFace(id: "user/adapter")

        // Act
        _ = try await wired.resolve(source)
        let error = await errorThrown { _ = try await bare.resolve(source) }

        // Assert
        #expect(await delegate.downloadCount == 1)
        #expect(try await wired.isCached(source) == true)
        guard case .adapterMergeFailed = error as? LLMLocalError else {
            Issue.record("expected adapterMergeFailed, got \(String(describing: error))")
            return
        }
        #expect(
            try await bare.isCached(source) == false,
            """
            an entry recorded for an adapter nobody fetched makes every later resolve return that \
            path without downloading, and the mismatch only surfaces once MLX tries to load it
            """
        )
    }

    @Test("a GitHub adapter is refused the same way")
    func gitHubResolveFailsWithoutDelegate() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = try AdapterRegistry(adapterDirectory: dir)
        let source = AdapterSource.gitHubRelease(
            repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"
        )

        // Act
        let error = await errorThrown { _ = try await registry.resolve(source) }

        // Assert
        guard case .adapterMergeFailed = error as? LLMLocalError else {
            Issue.record("expected adapterMergeFailed, got \(String(describing: error))")
            return
        }
        #expect(
            try await FileManager.default.contentsOfDirectory(atPath: dir.path)
                .contains(where: { $0.hasPrefix("gh--") }) == false,
            "nothing may be written at the adapter path either"
        )
    }

    /// Removing the fabricating default must not cost the uses that never needed one.
    @Test("a local adapter still resolves without a delegate")
    func localResolveWorksWithoutDelegate() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = dir.appendingPathComponent("mine", isDirectory: true)
        try FileManager.default.createDirectory(at: adapter, withIntermediateDirectories: true)
        let registry = try AdapterRegistry(adapterDirectory: dir)

        // Act
        let resolved = try await registry.resolve(.local(path: adapter))

        // Assert
        #expect(resolved == adapter)
        #expect(try await registry.cachedAdapters().isEmpty)
    }
}
