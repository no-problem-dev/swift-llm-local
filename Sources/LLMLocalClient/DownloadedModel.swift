import Foundation

/// ディスク上に完全な形でダウンロード済みのモデル 1 件。
///
/// 「ダウンロード済み一覧」の表示・容量管理に使う。判定はインメモリのレジストリではなく
/// **ディスクの実体（完全なスナップショット）を真実**とするため、アプリ再起動後も正しく
/// 列挙できる。
public struct DownloadedModel: Sendable, Hashable, Codable, Identifiable {
    /// 対応する ``ModelSpec`` の `id`。
    public let modelId: String

    /// ディスク上の保存ディレクトリ。
    public let directory: URL

    /// ディスク上の実サイズ（バイト単位）。算出できない場合は `nil`。
    public let sizeInBytes: Int64?

    /// ダウンロード完了時刻の近似（保存ディレクトリの最終更新日時）。
    public let downloadedAt: Date?

    public var id: String { modelId }

    public init(
        modelId: String,
        directory: URL,
        sizeInBytes: Int64?,
        downloadedAt: Date?
    ) {
        self.modelId = modelId
        self.directory = directory
        self.sizeInBytes = sizeInBytes
        self.downloadedAt = downloadedAt
    }
}

extension DownloadedModel {
    /// 実サイズを人間可読な文字列で返す（例: "2.3 GB"）。不明なら "—"。
    public var formattedSize: String {
        guard let sizeInBytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeInBytes)
    }
}
