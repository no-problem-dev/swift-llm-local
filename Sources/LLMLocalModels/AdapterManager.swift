import Foundation
import LLMLocalClient

// MARK: - AdapterNetworkDelegate

/// Protocol for downloading adapter files from remote sources.
///
/// Implementations handle the actual network operations for fetching
/// adapter files from GitHub Releases or Hugging Face Hub.
/// This protocol enables dependency injection for testing.
public protocol AdapterNetworkDelegate: Sendable {
    /// Downloads an adapter from a GitHub Release.
    ///
    /// - Parameters:
    ///   - repo: The GitHub repository (e.g. "owner/repo").
    ///   - tag: The release tag (e.g. "v1.0").
    ///   - asset: The asset filename (e.g. "adapter.safetensors").
    ///   - destination: The local file URL to save the downloaded file.
    func downloadGitHubRelease(
        repo: String, tag: String, asset: String, destination: URL
    ) async throws

    /// Downloads an adapter from the Hugging Face Hub.
    ///
    /// - Parameters:
    ///   - id: The Hugging Face model/adapter identifier (e.g. "user/adapter").
    ///   - destination: The local file URL to save the downloaded file.
    func downloadHuggingFace(id: String, destination: URL) async throws
}

// MARK: - StubAdapterNetworkDelegate

/// Stub delegate for Phase 2 -- creates placeholder files without network access.
///
/// This is used as the default delegate when no real network delegate is provided.
/// In Phase 3, this will be replaced with actual download implementations.
struct StubAdapterNetworkDelegate: AdapterNetworkDelegate {
    func downloadGitHubRelease(
        repo: String, tag: String, asset: String, destination: URL
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stub-adapter".utf8).write(to: destination)
    }

    func downloadHuggingFace(id: String, destination: URL) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stub-adapter".utf8).write(to: destination)
    }
}

// MARK: - AdapterInfo

/// Information about a cached adapter.
///
/// Tracks the version, source, download time, and local file path
/// for an adapter that has been downloaded and cached locally.
public struct AdapterInfo: Sendable, Codable {
    /// Unique cache key derived from the adapter source.
    public let key: String

    /// Version identifier (e.g. release tag or HuggingFace model ID).
    public let version: String

    /// The original source specification.
    public let source: AdapterSource

    /// When the adapter was downloaded.
    public let downloadedAt: Date

    /// Path to the locally cached adapter file.
    public let localPath: URL

    /// Creates a new adapter info.
    ///
    /// - Parameters:
    ///   - key: Unique cache key.
    ///   - version: Version identifier.
    ///   - source: The original adapter source.
    ///   - downloadedAt: When the adapter was downloaded.
    ///   - localPath: Path to the locally cached file.
    public init(
        key: String,
        version: String,
        source: AdapterSource,
        downloadedAt: Date,
        localPath: URL
    ) {
        self.key = key
        self.version = version
        self.source = source
        self.downloadedAt = downloadedAt
        self.localPath = localPath
    }
}

// MARK: - AdapterCache

/// Internal helper for reading and writing the adapter registry JSON file.
///
/// The registry is a simple JSON file mapping cache keys to ``AdapterInfo``.
/// This type is not an actor itself; it is used exclusively within
/// ``AdapterManager``'s actor-isolated context.
struct AdapterCache: Sendable {

    /// The directory where the registry file is stored.
    let directory: URL

    /// The path to the adapter registry JSON file.
    var registryPath: URL {
        directory.appendingPathComponent("adapter-registry.json")
    }

    /// Reads the registry from disk.
    ///
    /// - Returns: A dictionary mapping cache keys to ``AdapterInfo``.
    ///   Returns an empty dictionary if the file does not exist or cannot be decoded.
    func load() -> [String: AdapterInfo] {
        guard FileManager.default.fileExists(atPath: registryPath.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: registryPath)
            return try JSONDecoder().decode([String: AdapterInfo].self, from: data)
        } catch {
            return [:]
        }
    }

    /// Writes the registry to disk, creating the directory if needed.
    ///
    /// - Parameter registry: The dictionary of cache keys to ``AdapterInfo`` to persist.
    /// - Throws: An error if the file cannot be written.
    func save(_ registry: [String: AdapterInfo]) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(registry)
        try data.write(to: registryPath, options: .atomic)
    }
}

// MARK: - AdapterManager

/// Manages LoRA adapter downloads, versioning, and local storage.
///
/// `AdapterManager` handles downloading adapters from various sources
/// (GitHub Releases, HuggingFace, local paths) and managing their
/// local cache with version tracking.
///
/// ## Usage
///
/// ```swift
/// let manager = AdapterManager()
///
/// // Resolve an adapter source to a local file URL
/// let localURL = try await manager.resolve(
///     .gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
/// )
///
/// // Check if a newer version is available
/// let needsUpdate = await manager.isUpdateAvailable(
///     for: source, latestTag: "v2.0"
/// )
/// ```
public actor AdapterManager {

    /// The directory where adapter files are stored.
    private let adapterDirectory: URL

    /// In-memory registry of downloaded adapters, keyed by a unique key
    /// derived from the AdapterSource.
    private var adapterRegistry: [String: AdapterInfo] = [:]

    /// Persistence helper for the adapter registry.
    private let cache: AdapterCache

    /// Network delegate for downloading adapters (injectable for testing).
    private let networkDelegate: any AdapterNetworkDelegate

    /// Creates a new adapter manager.
    ///
    /// - Parameters:
    ///   - adapterDirectory: The directory for storing adapter files and registry.
    ///     Defaults to `~/Library/Application Support/LLMLocal/adapters`.
    ///   - networkDelegate: An optional delegate for performing downloads.
    ///     When `nil`, a stub delegate is used that creates placeholder files.
    public init(
        adapterDirectory: URL? = nil,
        networkDelegate: (any AdapterNetworkDelegate)? = nil
    ) {
        let dir = adapterDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )
            .first!
            .appendingPathComponent("LLMLocal/adapters")
        self.adapterDirectory = dir
        self.cache = AdapterCache(directory: dir)
        self.adapterRegistry = cache.load()
        self.networkDelegate = networkDelegate ?? StubAdapterNetworkDelegate()
    }

    // MARK: - Public API

    /// Resolves an AdapterSource to a local file URL.
    ///
    /// Downloads the adapter if not already cached. For local sources,
    /// validates the file exists and returns the path directly.
    ///
    /// - Parameter source: The adapter source to resolve.
    /// - Returns: A local file URL pointing to the adapter.
    /// - Throws: ``LLMLocalError/adapterMergeFailed(reason:)`` if a local adapter
    ///   is not found, or a download error if the remote fetch fails.
    public func resolve(_ source: AdapterSource) async throws -> URL {
        switch source {
        case .local(let path):
            guard FileManager.default.fileExists(atPath: path.path()) else {
                throw LLMLocalError.adapterMergeFailed(
                    reason: "Local adapter not found at \(path.path())"
                )
            }
            return path

        case .gitHubRelease(let repo, let tag, let asset):
            let key = Self.cacheKey(for: source)
            // Check if already cached with matching version
            if let info = adapterRegistry[key], info.version == tag {
                return info.localPath
            }
            // Download from GitHub Releases
            let localPath = adapterDirectory.appendingPathComponent(key)
            try await networkDelegate.downloadGitHubRelease(
                repo: repo, tag: tag, asset: asset, destination: localPath
            )
            let info = AdapterInfo(
                key: key,
                version: tag,
                source: source,
                downloadedAt: Date(),
                localPath: localPath
            )
            adapterRegistry[key] = info
            try cache.save(adapterRegistry)
            return localPath

        case .huggingFace(let id):
            let key = Self.cacheKey(for: source)
            if let info = adapterRegistry[key] {
                return info.localPath
            }
            let localPath = adapterDirectory.appendingPathComponent(key)
            try await networkDelegate.downloadHuggingFace(
                id: id, destination: localPath
            )
            let info = AdapterInfo(
                key: key,
                version: id,
                source: source,
                downloadedAt: Date(),
                localPath: localPath
            )
            adapterRegistry[key] = info
            try cache.save(adapterRegistry)
            return localPath
        }
    }

    /// Returns all cached adapters.
    ///
    /// - Returns: An array of ``AdapterInfo`` for every cached adapter.
    public func cachedAdapters() -> [AdapterInfo] {
        Array(adapterRegistry.values)
    }

    /// Checks if an adapter is cached.
    ///
    /// - Parameter source: The adapter source to check.
    /// - Returns: `true` if the adapter has been downloaded and cached.
    public func isCached(_ source: AdapterSource) -> Bool {
        let key = Self.cacheKey(for: source)
        return adapterRegistry[key] != nil
    }

    /// Deletes a cached adapter's registry entry.
    ///
    /// If the adapter is not cached, this method does nothing.
    ///
    /// - Parameter source: The adapter source to remove.
    /// - Throws: An error if the registry cannot be persisted.
    public func deleteAdapter(for source: AdapterSource) throws {
        let key = Self.cacheKey(for: source)
        adapterRegistry.removeValue(forKey: key)
        try cache.save(adapterRegistry)
    }

    /// Removes all cached adapter registry entries.
    ///
    /// - Throws: An error if the registry cannot be persisted.
    public func clearAll() throws {
        adapterRegistry.removeAll()
        try cache.save(adapterRegistry)
    }

    /// Checks if a newer version is available for a cached adapter.
    ///
    /// Returns `true` if the adapter is not cached or if the cached version
    /// differs from the specified latest tag.
    ///
    /// - Parameters:
    ///   - source: The adapter source to check.
    ///   - latestTag: The latest known version tag to compare against.
    /// - Returns: `true` if an update is available.
    public func isUpdateAvailable(
        for source: AdapterSource, latestTag: String
    ) -> Bool {
        let key = Self.cacheKey(for: source)
        guard let info = adapterRegistry[key] else { return true }
        return info.version != latestTag
    }

    // MARK: - Internal Helpers

    /// Generates a unique cache key for an adapter source.
    ///
    /// The key format varies by source type:
    /// - GitHub Release: `gh--{owner}--{repo}--{tag}--{asset}`
    /// - HuggingFace: `hf--{id with / replaced by --}`
    /// - Local: `local--{filename}`
    ///
    /// - Parameter source: The adapter source.
    /// - Returns: A unique string key suitable for use as a dictionary key
    ///   and filesystem-safe directory/file name.
    static func cacheKey(for source: AdapterSource) -> String {
        switch source {
        case .gitHubRelease(let repo, let tag, let asset):
            return "gh--\(repo.replacingOccurrences(of: "/", with: "--"))--\(tag)--\(asset)"
        case .huggingFace(let id):
            return "hf--\(id.replacingOccurrences(of: "/", with: "--"))"
        case .local(let path):
            return "local--\(path.lastPathComponent)"
        }
    }
}
