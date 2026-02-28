import Foundation

/// キャッシュされたモデルの情報（所在とメタデータを含む）
public struct CachedModelInfo: Sendable, Codable {
    /// キャッシュされたモデルの一意識別子。
    public let modelId: String

    /// 人間可読な表示名。
    public let displayName: String

    /// キャッシュされたモデルのサイズ（バイト単位）。
    public let sizeInBytes: Int64

    /// モデルがダウンロードされた日時。
    public let downloadedAt: Date

    /// このモデルのローカルキャッシュディレクトリへのパス。
    public let localPath: URL

    /// モデル実ファイルのパス（HF Hub キャッシュディレクトリ）。
    ///
    /// 削除時にこのパスのディレクトリごと削除することで、
    /// ディスク上のモデルファイルを確実に除去します。
    public let modelFilesPath: URL?

    /// 新しいキャッシュモデル情報を作成します。
    public init(
        modelId: String,
        displayName: String,
        sizeInBytes: Int64,
        downloadedAt: Date,
        localPath: URL,
        modelFilesPath: URL? = nil
    ) {
        self.modelId = modelId
        self.displayName = displayName
        self.sizeInBytes = sizeInBytes
        self.downloadedAt = downloadedAt
        self.localPath = localPath
        self.modelFilesPath = modelFilesPath
    }
}
