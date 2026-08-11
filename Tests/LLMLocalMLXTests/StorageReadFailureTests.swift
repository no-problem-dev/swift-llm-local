import Foundation
import HuggingFace
import Testing
@testable import LLMLocalClient
@testable import LLMLocalMLX

// MARK: - Helpers

/// Runs the operation and hands back whatever it threw, or `nil` when it returned normally.
///
/// Written this way rather than with `#expect(throws:)` so the assertion at the call site is about
/// *which* case was thrown. A directory that could not be read and threw something else would be as
/// wrong as one that threw nothing.
private func errorThrown(by operation: () throws -> Void) -> (any Error)? {
    do {
        try operation()
        return nil
    } catch {
        return error
    }
}

private func errorThrown(by operation: () async throws -> Void) async -> (any Error)? {
    do {
        try await operation()
        return nil
    } catch {
        return error
    }
}

/// Whether the error is the one the storage layer raises for something it could not read.
private func isStorageUnreadable(_ error: (any Error)?) -> Bool {
    if case .storageUnreadable = error as? LLMLocalError { return true }
    return false
}

// MARK: - Fixtures

/// Builds model directories on disk and can take the ability to read them away again.
///
/// Read permission is removed with mode `0o111`: the directory can still be traversed and its
/// children stat'd, but it will not list. That is the shape a real permissions problem takes, and it
/// is precisely the case a `fileExists` check cannot see — which is why the swallow was invisible.
private struct StorageFixture: ~Copyable {
    let base: URL

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-read-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    deinit {
        // Restore readability everywhere first, or the tree cannot be removed.
        if let walk = FileManager.default.enumerator(atPath: base.path) {
            for case let name as String in walk {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: base.appendingPathComponent(name).path
                )
            }
        }
        try? FileManager.default.removeItem(at: base)
    }

    /// Writes a Hugging Face style snapshot at `{namespace}/{name}`.
    @discardableResult
    func writeSnapshot(hfID: String, weightBytes: Int = 4096) throws -> URL {
        let dir = directory(hfID: hfID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("config.json"))
        try Data(repeating: 0, count: weightBytes)
            .write(to: dir.appendingPathComponent("model.safetensors"))
        return dir
    }

    func directory(hfID: String) -> URL {
        let parts = hfID.split(separator: "/", maxSplits: 1).map(String.init)
        return base
            .appendingPathComponent(parts[0], isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
    }

    /// Takes read permission away from a directory, leaving it traversable.
    func denyReads(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o111], ofItemAtPath: url.path
        )
    }

    func spec(_ id: String, hf: String) -> ModelSpec {
        ModelSpec(
            id: id, base: .huggingFace(id: hf), contextLength: 4096,
            displayName: id, description: "", estimatedMemoryBytes: 1_000_000
        )
    }
}

/// The tests need a real user to be denied by the permission bits.
private var permissionsAreEnforced: Bool { geteuid() != 0 }

// MARK: - #1 A directory that will not read is not an absent model

/// A model directory that cannot be read must not answer as one that is not there.
///
/// Every test here contrasts the two states rather than asserting on one of them, because the
/// failure being guarded against is exactly that they become the same answer. Downstream that
/// answer decides whether to spend a multi-gigabyte download on a model already on disk.
@Suite("Model storage read failure", .enabled(if: permissionsAreEnforced))
struct StorageReadFailureTests {

    @Test("an unreadable model directory is not an absent model")
    func unreadableIsNotAbsent() throws {
        // Arrange: one model on disk that cannot be listed, one that was never fetched.
        let fixture = try StorageFixture()
        let present = try fixture.writeSnapshot(hfID: "mlx-community/Present")
        try fixture.denyReads(at: present)
        let inventory = try LocalModelInventory(baseDirectory: fixture.base)

        // Act
        let absent = try inventory.isDownloaded(fixture.spec("absent", hf: "mlx-community/Absent"))
        let error = errorThrown {
            _ = try inventory.isDownloaded(fixture.spec("present", hf: "mlx-community/Present"))
        }

        // Assert
        #expect(absent == false)
        #expect(
            isStorageUnreadable(error),
            """
            false is the answer for a model that is not on the device, and it sends the caller off \
            to download gigabytes this device is already holding; got \(String(describing: error))
            """
        )
    }

    @Test("a directory that will not list is not an incomplete download either")
    func unreadableIsNotIncomplete() throws {
        // Arrange
        let fixture = try StorageFixture()
        let dir = try fixture.writeSnapshot(hfID: "ns/Model")
        try fixture.denyReads(at: dir)

        // Act
        let error = errorThrown { _ = try ModelStorageLayout.snapshotState(at: dir) }

        // Assert
        #expect(isStorageUnreadable(error), "got \(String(describing: error))")
    }

    @Test("the three states a readable path can be in are still distinguished")
    func readableStatesAreUnchanged() throws {
        // Arrange
        let fixture = try StorageFixture()
        let complete = try fixture.writeSnapshot(hfID: "ns/Complete")
        let partial = fixture.directory(hfID: "ns/Partial")
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: partial.appendingPathComponent("config.json"))

        // Act & Assert
        #expect(try ModelStorageLayout.snapshotState(at: complete) == .complete)
        #expect(try ModelStorageLayout.snapshotState(at: partial) == .incomplete)
        #expect(
            try ModelStorageLayout.snapshotState(at: fixture.directory(hfID: "ns/Nothing"))
                == .absent
        )
    }

    @Test("downloadedModels does not quietly drop a model it could not read")
    func downloadedModelsDoesNotDropUnreadable() throws {
        // Arrange
        let fixture = try StorageFixture()
        try fixture.writeSnapshot(hfID: "ns/Readable")
        let blocked = try fixture.writeSnapshot(hfID: "ns/Blocked")
        try fixture.denyReads(at: blocked)
        let inventory = try LocalModelInventory(baseDirectory: fixture.base)
        let specs = [
            fixture.spec("readable", hf: "ns/Readable"),
            fixture.spec("blocked", hf: "ns/Blocked"),
        ]

        // Act
        let error = errorThrown { _ = try inventory.downloadedModels(among: specs) }

        // Assert
        #expect(
            isStorageUnreadable(error),
            """
            a list one short is a list, and the caller reads it as 'that model is not installed'; \
            got \(String(describing: error))
            """
        )
    }

    /// The gate that decides whether to spend the download.
    ///
    /// The hub is pointed at a closed local port, so a downloader that mistook "cannot read" for
    /// "not downloaded" would fail trying to reach the network — a different error, arriving after
    /// it had already committed to fetching the model.
    @Test("the downloader refuses rather than re-fetching a model it could not read")
    func downloaderDoesNotRefetchUnreadableSnapshot() async throws {
        // Arrange
        let fixture = try StorageFixture()
        let dir = try fixture.writeSnapshot(hfID: "mlx-community/Already-Here")
        try fixture.denyReads(at: dir)
        let downloader = try DestinationHubDownloader(
            hub: HubClient(host: URL(string: "http://127.0.0.1:1")!, tokenProvider: .none),
            baseDirectory: fixture.base
        )

        // Act
        let error = await errorThrown {
            _ = try await downloader.download(
                id: "mlx-community/Already-Here",
                revision: nil,
                matching: ["*"],
                useLatest: false,
                progressHandler: { _ in }
            )
        }

        // Assert
        #expect(
            isStorageUnreadable(error),
            """
            downloadFailed here would mean the gate answered 'not downloaded' and the transfer was \
            already under way; got \(String(describing: error))
            """
        )
    }
}

// MARK: - #2 A size that could not be measured is not a size

/// A storage figure a user acts on must not silently understate what is there.
@Suite("Model storage size measurement", .enabled(if: permissionsAreEnforced))
struct StorageSizeFailureTests {

    /// Builds a model directory whose weights sit in a subdirectory that can be made unreadable.
    private static func writeShardedSnapshot(
        in fixture: borrowing StorageFixture, hfID: String, topBytes: Int, shardBytes: Int
    ) throws -> (model: URL, shards: URL) {
        let dir = fixture.directory(hfID: hfID)
        let shards = dir.appendingPathComponent("shards", isDirectory: true)
        try FileManager.default.createDirectory(at: shards, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("config.json"))
        try Data(repeating: 0, count: topBytes)
            .write(to: dir.appendingPathComponent("model.safetensors"))
        try Data(repeating: 0, count: shardBytes)
            .write(to: shards.appendingPathComponent("shard-1.safetensors"))
        return (dir, shards)
    }

    @Test("a subtree that cannot be walked is not zero bytes")
    func unreadableSubtreeIsNotZero() throws {
        // Arrange: two identical models; one has its shard directory closed off.
        let fixture = try StorageFixture()
        let readable = try Self.writeShardedSnapshot(
            in: fixture, hfID: "ns/Readable", topBytes: 1_000, shardBytes: 40_000
        )
        let blocked = try Self.writeShardedSnapshot(
            in: fixture, hfID: "ns/Blocked", topBytes: 1_000, shardBytes: 40_000
        )
        try fixture.denyReads(at: blocked.shards)

        // Act
        let measured = try ModelStorageLayout.directorySize(at: readable.model)
        let error = errorThrown { _ = try ModelStorageLayout.directorySize(at: blocked.model) }

        // Assert
        #expect((measured ?? 0) >= 41_000)
        #expect(
            isStorageUnreadable(error),
            """
            skipping the subtree returns roughly the 1 KB it could reach, which is a plausible \
            number, indistinguishable from an honest one, and 40x short of what deleting the model \
            would actually free; got \(String(describing: error))
            """
        )
    }

    @Test("totalDiskSize does not answer with a partial sum")
    func totalDiskSizeIsNotPartial() throws {
        // Arrange
        let fixture = try StorageFixture()
        try Self.writeShardedSnapshot(
            in: fixture, hfID: "ns/A", topBytes: 1_000, shardBytes: 40_000
        )
        let blocked = try Self.writeShardedSnapshot(
            in: fixture, hfID: "ns/B", topBytes: 1_000, shardBytes: 40_000
        )
        try fixture.denyReads(at: blocked.shards)
        let inventory = try LocalModelInventory(baseDirectory: fixture.base)
        let specs = [fixture.spec("a", hf: "ns/A"), fixture.spec("b", hf: "ns/B")]

        // Act
        let error = errorThrown { _ = try inventory.totalDiskSize(among: specs) }

        // Assert
        #expect(
            isStorageUnreadable(error),
            """
            "storage used" is what someone reads before deciding what to delete; \
            got \(String(describing: error))
            """
        )
    }

    @Test("a model that is not there has no size, and that is not a failure")
    func absentModelHasNoSize() throws {
        // Arrange
        let fixture = try StorageFixture()
        let inventory = try LocalModelInventory(baseDirectory: fixture.base)

        // Act & Assert
        #expect(try inventory.diskSize(of: fixture.spec("none", hf: "ns/None")) == nil)
        #expect(try inventory.totalDiskSize(among: [fixture.spec("none", hf: "ns/None")]) == 0)
    }
}

// MARK: - #3 The models root either is what it promises or is not returned

@Suite("Model storage root", .enabled(if: permissionsAreEnforced))
struct StorageRootTests {

    @Test("the root that is handed out is excluded from backup")
    func rootIsExcludedFromBackup() throws {
        // Arrange
        let fixture = try StorageFixture()

        // Act
        let base = try ModelStorageLayout.baseDirectory(under: fixture.base)

        // Assert
        #expect(FileManager.default.fileExists(atPath: base.path))
        #expect(
            try base.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
                == true,
            """
            the flag is the entire reason this directory is under Application Support rather than \
            Caches; without it multi-gigabyte weights go into iCloud backup
            """
        )
    }

    @Test("a root that could not be created is not returned as though it were")
    func uncreatableRootThrows() throws {
        // Arrange: a file sits where the models directory needs to go.
        let fixture = try StorageFixture()
        let blocked = fixture.base.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("not a directory".utf8)
            .write(to: blocked.appendingPathComponent("swift-llm-local"))

        // Act
        let error = errorThrown { _ = try ModelStorageLayout.baseDirectory(under: blocked) }

        // Assert
        #expect(
            error != nil,
            "returning the URL anyway hands the downloader a path nothing can be written to"
        )
    }

    @Test("a root that would not take the backup-exclusion flag is not returned")
    func unflaggableRootThrows() throws {
        // Arrange: the directory already exists and will not accept an extended attribute.
        let fixture = try StorageFixture()
        let support = fixture.base.appendingPathComponent("readonly", isDirectory: true)
        let models = support.appendingPathComponent("swift-llm-local/models", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: models.path
        )

        // Act
        let error = errorThrown { _ = try ModelStorageLayout.baseDirectory(under: support) }

        // Assert
        #expect(
            error != nil,
            """
            the flag failing silently is the whole defect: nothing else in the system ever mentions \
            that the weights are being backed up to iCloud
            """
        )
    }
}

// MARK: - #8 One policy for the Application Support lookup

/// Answers no directory at all, which is what the three call sites disagreed about handling.
private final class NoDirectoriesFileManager: FileManager, @unchecked Sendable {
    override func urls(
        for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        []
    }
}

@Suite("Application Support lookup")
struct ApplicationSupportDirectoryTests {

    /// Two call sites force-unwrapped this and one fell back to the temporary directory.
    ///
    /// Both are failures the caller never hears about: a crash it cannot catch, or a purgeable
    /// directory that makes "downloaded" stop being true without notice. The policy is now to say
    /// so.
    @Test("an empty lookup throws rather than crashing or degrading silently")
    func emptyLookupThrows() {
        // Act
        let error = errorThrown {
            _ = try ApplicationSupportDirectory.url(using: NoDirectoriesFileManager())
        }

        // Assert
        #expect(isStorageUnreadable(error), "got \(String(describing: error))")
    }

    @Test("the real lookup answers")
    func realLookupAnswers() throws {
        #expect(try ApplicationSupportDirectory.url().isFileURL)
    }
}
