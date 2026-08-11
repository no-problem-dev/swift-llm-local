import Foundation

/// Where a model's base weights are fetched from.
///
/// This is what turns a spec into bytes on disk. A remote source is downloaded on first load into
/// an app-owned directory keyed by the repository namespace and name, and reused from then on; a
/// local source is read in place and is never downloaded, moved, or deleted by this package.
public enum ModelSource: Sendable, Hashable, Codable {
    /// Weights published on the Hugging Face Hub, downloaded on first use.
    ///
    /// The MLX backend expects an MLX-format repository — mlx-community publishes the quantized
    /// conversions this package is built around.
    ///
    /// - Parameter id: Repository id in `namespace/name` form, such as
    ///   "mlx-community/Llama-3.2-1B-Instruct-4bit". A value that does not parse as a repository id
    ///   fails the load rather than being treated as a path.
    case huggingFace(id: String)

    /// Weights already present on disk, loaded straight from that directory.
    ///
    /// Use it for bundled models or for a directory managed by the app itself. Because the files are
    /// not app-owned, the inventory will report the model as downloaded but refuses to delete it.
    ///
    /// - Parameter path: Directory holding the model's config and weight files.
    case local(path: URL)
}
