import Foundation
import Testing
@testable import LLMLocalClient
@testable import LLMLocalMLX

@Suite("LocalModelInventory")
struct LocalModelInventoryTests {

    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inventory-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a Hugging Face style snapshot at `{namespace}/{name}` under the given base directory.
    ///
    /// - Parameters:
    ///   - complete: Writes both config.json and a weights file when true, so the inventory sees a
    ///     usable model; writes only config.json when false, which is the half-downloaded shape.
    ///   - weightBytes: Size of the placeholder weights file, used to check reported disk usage.
    private static func writeSnapshot(
        base: URL, hfID: String, complete: Bool, weightBytes: Int = 1024
    ) throws {
        let parts = hfID.split(separator: "/", maxSplits: 1).map(String.init)
        let dir = base
            .appendingPathComponent(parts[0], isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("config.json"))
        if complete {
            try Data(repeating: 0, count: weightBytes)
                .write(to: dir.appendingPathComponent("model.safetensors"))
        }
    }

    private static func spec(_ id: String, hf: String) -> ModelSpec {
        ModelSpec(
            id: id, base: .huggingFace(id: hf), contextLength: 4096,
            displayName: id, description: "", estimatedMemoryBytes: 1_000_000
        )
    }

    // MARK: - Tests

    @Test("完全なスナップショットは isDownloaded == true")
    func detectsCompleteSnapshot() throws {
        let base = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.writeSnapshot(base: base, hfID: "mlx-community/Qwen3.5-2B-6bit", complete: true)

        let inventory = try LocalModelInventory(baseDirectory: base)
        #expect(try inventory.isDownloaded(Self.spec("q2b", hf: "mlx-community/Qwen3.5-2B-6bit")))
    }

    @Test("config だけ（重み無し）は未完了として isDownloaded == false")
    func incompleteSnapshotIsNotDownloaded() throws {
        let base = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.writeSnapshot(base: base, hfID: "mlx-community/Partial-Model", complete: false)

        let inventory = try LocalModelInventory(baseDirectory: base)
        #expect(try !inventory.isDownloaded(Self.spec("partial", hf: "mlx-community/Partial-Model")))
    }

    @Test("未保存のモデルは isDownloaded == false")
    func missingIsNotDownloaded() throws {
        let base = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let inventory = try LocalModelInventory(baseDirectory: base)
        #expect(try !inventory.isDownloaded(Self.spec("none", hf: "mlx-community/Not-Downloaded")))
    }

    @Test("downloadedModels は完全なものだけ・サイズ込みで返す")
    func listsOnlyComplete() throws {
        let base = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.writeSnapshot(base: base, hfID: "ns/Complete", complete: true, weightBytes: 4096)
        try Self.writeSnapshot(base: base, hfID: "ns/Incomplete", complete: false)

        let specs = [
            Self.spec("complete", hf: "ns/Complete"),
            Self.spec("incomplete", hf: "ns/Incomplete"),
            Self.spec("missing", hf: "ns/Missing"),
        ]
        let inventory = try LocalModelInventory(baseDirectory: base)
        let downloaded = try inventory.downloadedModels(among: specs)

        #expect(downloaded.map(\.modelId) == ["complete"])
        #expect((downloaded.first?.sizeInBytes ?? 0) >= 4096)
    }

    @Test("delete はディスクから除去し isDownloaded == false になる")
    func deleteRemovesFromDisk() throws {
        let base = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.writeSnapshot(base: base, hfID: "ns/ToDelete", complete: true)
        let spec = Self.spec("del", hf: "ns/ToDelete")

        let inventory = try LocalModelInventory(baseDirectory: base)
        #expect(try inventory.isDownloaded(spec))
        try inventory.delete(spec)
        #expect(try !inventory.isDownloaded(spec))
    }

    @Test("totalDiskSize は完全なモデルの合計を返す")
    func totalSize() throws {
        let base = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.writeSnapshot(base: base, hfID: "ns/A", complete: true, weightBytes: 2048)
        try Self.writeSnapshot(base: base, hfID: "ns/B", complete: true, weightBytes: 2048)

        let specs = [Self.spec("a", hf: "ns/A"), Self.spec("b", hf: "ns/B")]
        let inventory = try LocalModelInventory(baseDirectory: base)
        #expect(try inventory.totalDiskSize(among: specs) >= 4096)
    }
}
