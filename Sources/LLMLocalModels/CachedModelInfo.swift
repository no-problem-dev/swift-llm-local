import Foundation

/// A model recorded as downloaded, with the paths and size kept for it.
///
/// Written to the registry JSON by ``ModelRegistry``. It records what a caller reported rather
/// than describing the file system: it survives its files being deleted from underneath it, and
/// nothing is re-measured when it is loaded. Comparing it with the on-disk snapshot — via
/// `LocalModelInventory` in the MLX module — is the only way to detect that it has gone stale.
public struct CachedModelInfo: Sendable, Codable {
    /// Identifier of the model, chosen by the app rather than derived from the download source.
    ///
    /// This is ``ModelSpec/id``: not a Hugging Face repository id, and carrying no revision, so
    /// two different sets of weights can be recorded under the same id over time.
    public let modelId: String

    public let displayName: String

    /// Size reported at registration time, in bytes.
    ///
    /// Taken on trust from whoever registered the model; the directory is never measured.
    public let sizeInBytes: Int64

    /// When the entry was recorded.
    ///
    /// This is the registration moment, which is not necessarily when the files finished
    /// downloading.
    public let downloadedAt: Date

    /// Path derived for this model inside the registry's own directory.
    ///
    /// Composed as `cacheDirectory/{modelId}`. The registry neither creates nor reads it, and the
    /// weights are not there — ``modelFilesPath`` points at the files that exist.
    public let localPath: URL

    /// Directory holding the downloaded model files, when the registrar supplied one.
    ///
    /// The only path eviction acts on: ``ModelRegistry/deleteCache(for:)`` and
    /// ``ModelRegistry/clearAllCache()`` delete this directory and nothing else, so an entry with
    /// `nil` here can never free disk space. Entries written before this field existed decode with
    /// `nil`.
    public let modelFilesPath: URL?

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
