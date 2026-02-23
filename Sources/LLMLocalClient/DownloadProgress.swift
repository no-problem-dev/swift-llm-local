import Foundation

/// ダウンロード進捗情報
///
/// モデルダウンロードの現在の状態を報告します。
/// バイト単位の進捗と現在ダウンロード中のファイル名を含みます。
public struct DownloadProgress: Sendable {
    /// 進捗率（0.0〜1.0）。
    public let fraction: Double

    /// ダウンロード済みバイト数。
    public let completedBytes: Int64

    /// ダウンロード総バイト数。
    public let totalBytes: Int64

    /// 現在ダウンロード中のファイル名（不明な場合は nil）。
    public let currentFile: String?

    /// 新しいダウンロード進捗値を生成します。
    ///
    /// - Parameters:
    ///   - fraction: 進捗率（0.0〜1.0）。
    ///   - completedBytes: ダウンロード済みバイト数。
    ///   - totalBytes: ダウンロード総バイト数。
    ///   - currentFile: 現在ダウンロード中のファイル名（不明な場合は nil）。
    public init(
        fraction: Double,
        completedBytes: Int64,
        totalBytes: Int64,
        currentFile: String?
    ) {
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentFile = currentFile
    }
}
