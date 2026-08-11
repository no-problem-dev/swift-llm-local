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
