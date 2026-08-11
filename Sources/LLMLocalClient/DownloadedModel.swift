import Foundation

/// One model whose files are complete on disk and ready to load without a download.
///
/// Membership is decided by looking at the files themselves — a directory counts only when both the
/// configuration and the weights are there — rather than by consulting a registry the app keeps in
/// memory. That is what makes the list survive a relaunch and makes an interrupted download absent
/// rather than listed and broken. Use it to show what is installed and to reclaim disk space.
public struct DownloadedModel: Sendable, Hashable, Codable, Identifiable {
    /// Identifier of the ``ModelSpec`` these files belong to.
    public let modelId: String

    /// Directory holding the model's configuration and weights.
    public let directory: URL

    /// Bytes the files occupy on disk.
    ///
    /// Measured by walking the directory, so it is the real cost of deleting or keeping the model,
    /// unlike ``ModelSpec/estimatedMemoryBytes`` which estimates memory while running. Not optional:
    /// a directory that could not be measured produces no `DownloadedModel` at all, because a value
    /// standing in for a failed measurement is one a caller sums into a storage total and shows to
    /// someone deciding what to delete.
    public let sizeInBytes: Int64

    /// When the download most likely finished, or `nil` when the date is unavailable.
    ///
    /// Taken from the directory's modification date, so anything that rewrites files inside it moves
    /// this forward. It is good enough for sorting the list newest first, not for an audit trail.
    public let downloadedAt: Date?

    public var id: String { modelId }

    public init(
        modelId: String,
        directory: URL,
        sizeInBytes: Int64,
        downloadedAt: Date?
    ) {
        self.modelId = modelId
        self.directory = directory
        self.sizeInBytes = sizeInBytes
        self.downloadedAt = downloadedAt
    }
}

extension DownloadedModel {
    /// On-disk size formatted for display, such as "2.3 GB".
    ///
    /// Uses the file count style, so the number matches what the Files app or Storage settings would
    /// report for the same directory.
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeInBytes)
    }
}
