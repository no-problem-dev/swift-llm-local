import Foundation

/// Snapshot of how far a model download has got.
///
/// One value is delivered per progress update while weights are being fetched, on whatever task the
/// downloader runs on — hop to the main actor before driving UI with it. Updates stop as soon as
/// the transfer ends; the load continues afterwards, so the last update is not the moment the model
/// becomes usable.
public struct DownloadProgress: Sendable {
    /// Completed share of the transfer, from 0 to 1.
    ///
    /// Reported by the downloader rather than derived from the byte counts, so prefer it for a
    /// progress bar — the byte counts can still be zero while this is meaningful.
    public let fraction: Double

    /// Bytes transferred so far.
    public let completedBytes: Int64

    /// Total bytes expected, or zero while the size is not yet known.
    ///
    /// The first update of a download reports zero for both counts, so guard before dividing.
    public let totalBytes: Int64

    /// File currently being transferred, or `nil` when the downloader does not report file names.
    ///
    /// The MLX backend never fills this in; treat it as an optional detail, not as something UI can
    /// depend on.
    public let currentFile: String?

    /// - Parameters:
    ///   - fraction: Completed share of the transfer, from 0 to 1.
    ///   - completedBytes: Bytes transferred so far.
    ///   - totalBytes: Total bytes expected, or zero when not yet known.
    ///   - currentFile: File currently being transferred, or `nil` when unknown.
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
