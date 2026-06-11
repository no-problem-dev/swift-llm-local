import Foundation
import HuggingFace
import LLMLocalClient

/// モデルのオンディスク保存レイアウトの単一の定義。
///
/// 保存先パスの導出とスナップショット完全性の判定を 1 箇所に集約し、
/// 書き込み側（``DestinationHubDownloader``）と読み取り側（``LocalModelInventory``）が
/// 共有する。両者でパス規則がドリフトすると「DL したのに未 DL 扱い」になるため、
/// ここを唯一の真実とする。
enum ModelStorageLayout {

    /// モデルを配置するルート。既定は Application Support 配下（バックアップ対象外）。
    static func defaultBaseDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var base = support.appendingPathComponent("swift-llm-local/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // 数 GB のモデルは再取得可能なので iCloud バックアップから除外する。
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        return base
    }

    /// HF リポジトリ ID に対する保存先ディレクトリ（`{base}/{namespace}/{name}`）。
    static func destination(for repoID: Repo.ID, base: URL) -> URL {
        base
            .appendingPathComponent(repoID.namespace, isDirectory: true)
            .appendingPathComponent(repoID.name, isDirectory: true)
    }

    /// モデル仕様に対するローカル保存先。
    /// `.huggingFace` は base 配下、`.local` はそのパス自身。HF ID が不正なら `nil`。
    static func directory(for spec: ModelSpec, base: URL) -> URL? {
        switch spec.base {
        case .huggingFace(let id):
            guard let repoID = Repo.ID(rawValue: id) else { return nil }
            return destination(for: repoID, base: base)
        case .local(let path):
            return path
        }
    }

    /// 「設定 + 重み」が揃っているかを判定する。
    /// 重みは単一（`*.safetensors`）と分割（`*.safetensors.index.json`）の両方を許容する。
    static func hasCompleteSnapshot(at directory: URL) -> Bool {
        let fileManager = FileManager.default
        let config = directory.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: config.path) else { return false }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return contents.contains { name in
            name.hasSuffix(".safetensors") || name.hasSuffix(".safetensors.index.json")
        }
    }

    /// ディレクトリ配下の総バイト数（再帰）。存在しなければ `nil`。
    static func directorySize(at directory: URL) -> Int64? {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [],
            errorHandler: nil
        ) else { return nil }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            if let allocated = values?.totalFileAllocatedSize {
                total += Int64(allocated)
            } else if let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// ディレクトリの最終更新日時（DL 完了時刻の近似）。取得できなければ `nil`。
    static func modificationDate(at directory: URL) -> Date? {
        let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}
