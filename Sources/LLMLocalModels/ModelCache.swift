import Foundation

/// Internal helper for reading and writing the model registry JSON file.
///
/// The registry is a simple JSON file mapping model IDs to ``CachedModelInfo``.
/// This type is not an actor itself; it is used exclusively within ``ModelManager``'s
/// actor-isolated context, so thread safety is guaranteed by the caller.
struct ModelCache: Sendable {

    /// The directory where the registry file is stored.
    let directory: URL

    /// The path to the registry JSON file.
    var registryPath: URL {
        directory.appendingPathComponent("registry.json")
    }

    /// Reads the registry from disk.
    ///
    /// - Returns: A dictionary mapping model IDs to ``CachedModelInfo``.
    ///   Returns an empty dictionary if the file does not exist or cannot be decoded.
    func load() -> [String: CachedModelInfo] {
        guard FileManager.default.fileExists(atPath: registryPath.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: registryPath)
            let decoder = JSONDecoder()
            return try decoder.decode([String: CachedModelInfo].self, from: data)
        } catch {
            return [:]
        }
    }

    /// Writes the registry to disk, creating the directory if needed.
    ///
    /// - Parameter metadata: The dictionary of model IDs to ``CachedModelInfo`` to persist.
    /// - Throws: An error if the file cannot be written.
    func save(_ metadata: [String: CachedModelInfo]) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: registryPath, options: .atomic)
    }
}
