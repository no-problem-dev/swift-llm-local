import Foundation
import LLMLocalClient

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

// MARK: - DownloadProgressDelegate

/// Protocol for injecting download behavior (for testing).
///
/// Implementations perform the actual download work, calling the progress handler
/// with updates as the download proceeds. The returned value is the total size
/// in bytes of the downloaded model.
public protocol DownloadProgressDelegate: Sendable {
    /// Downloads the model described by `spec`, reporting progress via `progressHandler`.
    ///
    /// - Parameters:
    ///   - spec: The model specification to download.
    ///   - progressHandler: A closure called with progress updates during the download.
    /// - Returns: The total size of the downloaded model in bytes.
    /// - Throws: Any error that occurs during the download.
    func download(
        _ spec: ModelSpec,
        progressHandler: @Sendable (DownloadProgress) -> Void
    ) async throws -> Int64
}

// MARK: - StubDownloadDelegate

/// Default stub delegate that simulates a completed download without network access.
///
/// This is the Phase 2 stub; real HuggingFace Hub download integration will
/// replace this in a future phase.
struct StubDownloadDelegate: DownloadProgressDelegate {
    /// Fixed size returned by the stub download.
    static let stubSize: Int64 = 1_000_000

    func download(
        _ spec: ModelSpec,
        progressHandler: @Sendable (DownloadProgress) -> Void
    ) async throws -> Int64 {
        StubDownloadDelegate.stubSize
    }
}
