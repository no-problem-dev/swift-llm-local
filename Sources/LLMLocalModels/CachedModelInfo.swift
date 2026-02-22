import Foundation

/// Information about a cached model, including its location and metadata.
public struct CachedModelInfo: Sendable, Codable {
    /// The unique identifier of the cached model.
    public let modelId: String

    /// Human-readable display name.
    public let displayName: String

    /// Size of the cached model in bytes.
    public let sizeInBytes: Int64

    /// When the model was downloaded.
    public let downloadedAt: Date

    /// Path to the local cache directory for this model.
    public let localPath: URL

    /// Creates a new cached model info.
    public init(
        modelId: String,
        displayName: String,
        sizeInBytes: Int64,
        downloadedAt: Date,
        localPath: URL
    ) {
        self.modelId = modelId
        self.displayName = displayName
        self.sizeInBytes = sizeInBytes
        self.downloadedAt = downloadedAt
        self.localPath = localPath
    }
}
