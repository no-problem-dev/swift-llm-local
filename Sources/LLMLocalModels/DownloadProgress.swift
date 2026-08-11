import Foundation
import LLMLocalClient

// MARK: - DownloadProgressDelegate

/// Moves the bytes behind the registry's progress stream.
///
/// ``ModelRegistry`` owns the metadata; a conforming type owns the transfer. The progress handler
/// it is given is synchronous and `Sendable`, and the registry forwards each value straight into
/// its stream, so it may be called from any thread or actor — the Hugging Face downloader used by
/// the MLX backend reports on the main actor.
public protocol DownloadProgressDelegate: Sendable {
    /// Downloads the model and reports progress while the transfer runs.
    ///
    /// - Parameters:
    ///   - spec: Model to download.
    ///   - progressHandler: Called with each progress update while the download is in flight.
    /// - Returns: Total size of the downloaded model, in bytes. The registry records this number
    ///   verbatim as the model's size and never measures the file system.
    /// - Throws: Whatever the transfer fails with. The registry finishes its stream with that
    ///   error and records nothing.
    func download(
        _ spec: ModelSpec,
        progressHandler: @Sendable (DownloadProgress) -> Void
    ) async throws -> Int64
}

// MARK: - StubDownloadDelegate

/// Default delegate that transfers nothing and reports a fixed size.
///
/// Used when no delegate is injected. It never calls the progress handler, so a stream from
/// ``ModelRegistry/downloadWithProgress(_:)`` yields only the registry's own zero and full values,
/// and the model is registered with a size that no file on disk backs.
struct StubDownloadDelegate: DownloadProgressDelegate {
    /// Size reported for every stub download, in bytes.
    static let stubSize: Int64 = 1_000_000

    func download(
        _ spec: ModelSpec,
        progressHandler: @Sendable (DownloadProgress) -> Void
    ) async throws -> Int64 {
        StubDownloadDelegate.stubSize
    }
}
