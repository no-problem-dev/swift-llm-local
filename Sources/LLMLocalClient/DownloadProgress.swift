import Foundation

/// Download progress information.
///
/// Reports the current state of a model download, including byte-level
/// progress and the name of the file currently being downloaded.
public struct DownloadProgress: Sendable {
    /// Progress fraction (0.0 - 1.0).
    public let fraction: Double

    /// Downloaded bytes so far.
    public let completedBytes: Int64

    /// Total bytes to download.
    public let totalBytes: Int64

    /// Currently downloading file name (nil if unknown).
    public let currentFile: String?

    /// Creates a new download progress value.
    ///
    /// - Parameters:
    ///   - fraction: Progress fraction (0.0 - 1.0).
    ///   - completedBytes: Downloaded bytes so far.
    ///   - totalBytes: Total bytes to download.
    ///   - currentFile: Currently downloading file name (nil if unknown).
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
