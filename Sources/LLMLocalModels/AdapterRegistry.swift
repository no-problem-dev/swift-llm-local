import Foundation
import LLMLocalClient
import PersistenceCore
import PersistenceFileSystem

// MARK: - AdapterNetworkDelegate

/// Fetches adapter files from a remote source.
///
/// ``AdapterRegistry`` decides what to fetch and where it goes; the conforming type moves the
/// bytes. The destination it is handed is the path the registry later returns from
/// ``AdapterRegistry/resolve(_:)``, and the MLX backend feeds that path to the model loader as an
/// adapter *directory* — so an implementation has to materialize a directory holding the adapter
/// weights and config there, not a single file.
public protocol AdapterNetworkDelegate: Sendable {
    /// Downloads a release asset from GitHub.
    ///
    /// - Parameters:
    ///   - repo: Repository in `owner/name` form.
    ///   - tag: Release tag, which the registry also records as the adapter's version.
    ///   - asset: Asset file name within the release.
    ///   - destination: Path to materialize; see the protocol discussion for its shape.
    func downloadGitHubRelease(
        repo: String, tag: String, asset: String, destination: URL
    ) async throws

    /// Downloads an adapter repository from Hugging Face Hub.
    ///
    /// - Parameters:
    ///   - id: Repository id in `user/name` form. No revision is involved, and the registry
    ///     records this id as the adapter's version.
    ///   - destination: Path to materialize; see the protocol discussion for its shape.
    func downloadHuggingFace(id: String, destination: URL) async throws
}

// MARK: - StubAdapterNetworkDelegate

/// Default delegate that writes a placeholder instead of downloading.
///
/// Used when no network delegate is injected. It creates the parent directory and writes a short
/// marker string at the destination path, which is enough for the registry to record a cache entry
/// but is not something a model can load.
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

/// An adapter recorded as downloaded, with the version and path kept for it.
///
/// Persisted in the adapter registry JSON. Nothing here ties the adapter to a base model; see
/// ``AdapterRegistry`` for what that omission costs.
public struct AdapterInfo: Sendable, Codable {
    /// Key derived from the source, unique per source.
    ///
    /// Doubles as the file name under the adapter directory, so it is also the on-disk location.
    public let key: String

    /// Version marker used for update checks.
    ///
    /// The release tag for a GitHub source, and the repository id itself for a Hugging Face source
    /// — which makes Hugging Face entries compare against tags they can never equal.
    public let version: String

    public let source: AdapterSource

    public let downloadedAt: Date

    /// Path the registry hands out for this adapter.
    ///
    /// `adapterDirectory/{key}` for downloaded adapters, or the caller's own path for a local
    /// source. The MLX backend loads it as an adapter directory.
    public let localPath: URL

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

// MARK: - AdapterRegistry

/// Downloads LoRA adapters, keeps them on disk, and records what was fetched.
///
/// Sources are GitHub release assets, Hugging Face repositories, or local paths. ``resolve(_:)``
/// turns any of them into a local URL, downloading first when needed. It has exactly the shape the
/// MLX backend expects of an adapter resolver but does not declare the conformance, so wiring this
/// registry into the backend means adding `extension AdapterRegistry: AdapterResolving {}` in the
/// app.
///
/// ## Adapters are not matched against base models
///
/// A LoRA adapter is trained against one specific base model, and nothing here knows which. The
/// cache key comes from the adapter source alone, ``ModelSpec`` pairs a base and an adapter with
/// no compatibility check, and resolving succeeds for any pairing. A mismatch is caught only when
/// MLX loads the adapter into the model, and surfaces as
/// ``LLMLocalError/loadFailed(modelId:reason:)`` from `loadModel` — after the multi-gigabyte base
/// weights have already been downloaded and read. Errors from this registry itself arrive earlier
/// and as ``LLMLocalError/adapterMergeFailed(reason:)``, because the backend resolves the adapter
/// before it touches MLX.
///
/// Adapters are applied at load time rather than fused: MLX loads the adapter into the freshly
/// built model container on every load, unloading the model drops it, and nothing is written back
/// to the base model directory. One downloaded base can therefore be reused with several adapters.
///
/// ## Versions
///
/// A GitHub source encodes tag and asset in its cache key, so a new tag is simply a new entry —
/// the previous entry and its file stay behind. A Hugging Face source has no version dimension at
/// all: once cached, ``resolve(_:)`` returns the same file no matter what changed upstream, and
/// only forgetting the entry with ``deleteAdapter(for:)`` forces a fresh download.
///
/// ## Usage
///
/// ```swift
/// let registry = AdapterRegistry()
///
/// // Resolve an adapter source to a local file URL
/// let localURL = try await registry.resolve(
///     .gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
/// )
///
/// // Check whether a newer version is available
/// let needsUpdate = await registry.isUpdateAvailable(
///     for: source, latestTag: "v2.0"
/// )
/// ```
public actor AdapterRegistry {

    /// Directory holding the downloaded adapters and the registry JSON.
    private let adapterDirectory: URL

    /// Loaded entries, keyed by the cache key derived from each source.
    private var adapterRegistry: [String: AdapterInfo] = [:]

    /// Whether the store has already been read into memory.
    private var isLoaded: Bool = false

    /// Backing store for the registry JSON. Reports an unreadable or corrupt file as an empty
    /// registry rather than throwing, after which cached adapters are re-downloaded over their
    /// existing files.
    private let cache: any RegistryStore<AdapterInfo>

    /// Performs the downloads. Defaults to a stub that writes a placeholder.
    private let networkDelegate: any AdapterNetworkDelegate

    /// Creates a registry that stores adapters in a directory and records them in a JSON file.
    ///
    /// - Parameters:
    ///   - adapterDirectory: Directory for the adapter files and the registry. Defaults to
    ///     `~/Library/Application Support/LLMLocal/adapters`.
    ///   - registryStore: Persistence for the entries. When `nil`, `adapter-registry.json` inside
    ///     the adapter directory is used.
    ///   - networkDelegate: Performs the downloads. When `nil`, a stub writes a placeholder file
    ///     and no bytes are fetched.
    public init(
        adapterDirectory: URL? = nil,
        registryStore: (any RegistryStore<AdapterInfo>)? = nil,
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
        self.cache = registryStore
            ?? FileSystemRegistryStore<AdapterInfo>(
                directory: dir,
                filename: "adapter-registry.json"
            )
        self.networkDelegate = networkDelegate ?? StubAdapterNetworkDelegate()
    }

    // MARK: - Private Helpers

    /// Reads the store into memory on first use; later calls return immediately.
    private func ensureLoaded() async {
        guard !isLoaded else { return }
        adapterRegistry = await cache.load()
        isLoaded = true
    }

    // MARK: - Public API

    /// Returns a local URL for an adapter, downloading it first when it is not cached.
    ///
    /// A local source is checked for existence and returned untouched — nothing is copied into the
    /// adapter directory and no entry is recorded, so the file stays owned by the caller. A remote
    /// source is downloaded to `adapterDirectory/{cacheKey}` and its entry saved before the URL is
    /// returned; a Hugging Face source that is already recorded is returned from the registry
    /// without any freshness check.
    ///
    /// Nothing verifies that the adapter fits the base model it is about to be loaded into.
    ///
    /// - Parameter source: Adapter to resolve.
    /// - Returns: Local URL for the adapter, which the MLX backend loads as an adapter directory.
    /// - Throws: ``LLMLocalError/adapterMergeFailed(reason:)`` when a local adapter is missing, and
    ///   whatever the network delegate or the registry save throws.
    public func resolve(_ source: AdapterSource) async throws -> URL {
        await ensureLoaded()
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
            try await cache.save(adapterRegistry)
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
            try await cache.save(adapterRegistry)
            return localPath
        }
    }

    /// Every recorded adapter, in no particular order.
    ///
    /// Entries can outlive their files; the recorded paths are not checked. Local sources never
    /// appear here, since ``resolve(_:)`` does not record them.
    public func cachedAdapters() async -> [AdapterInfo] {
        await ensureLoaded()
        return Array(adapterRegistry.values)
    }

    /// Reports whether an adapter has a registry entry.
    ///
    /// Answered from the registry alone, without checking the file at the recorded path. A local
    /// source always answers `false`, because resolving one records nothing.
    ///
    /// - Parameter source: Adapter to look up.
    /// - Returns: `true` when an entry exists for the source's cache key.
    public func isCached(_ source: AdapterSource) async -> Bool {
        await ensureLoaded()
        let key = Self.cacheKey(for: source)
        return adapterRegistry[key] != nil
    }

    /// Forgets an adapter, leaving its downloaded file on disk.
    ///
    /// Only the registry entry goes; the file under the adapter directory is untouched, so this
    /// frees no space and is safe to call while a model has the adapter loaded. Its real use is
    /// forcing the next ``resolve(_:)`` to download again over the same path — the only way to
    /// refresh a Hugging Face adapter.
    ///
    /// - Parameter source: Adapter to forget. An unknown source still triggers a registry save.
    /// - Throws: When the registry file cannot be written.
    public func deleteAdapter(for source: AdapterSource) async throws {
        await ensureLoaded()
        let key = Self.cacheKey(for: source)
        adapterRegistry.removeValue(forKey: key)
        try await cache.save(adapterRegistry)
    }

    /// Forgets every adapter, leaving the downloaded files on disk.
    ///
    /// The files under the adapter directory stay and lose their last reference, so reclaiming
    /// that space means sweeping the directory separately.
    ///
    /// - Throws: When the registry file cannot be written.
    public func clearAll() async throws {
        await ensureLoaded()
        adapterRegistry.removeAll()
        try await cache.save(adapterRegistry)
    }

    /// Reports whether a recorded adapter's version differs from a tag the caller already looked up.
    ///
    /// Nothing is fetched here — the latest tag has to be obtained elsewhere; this only compares.
    /// An adapter with no entry answers `true`. For a Hugging Face source the recorded version is
    /// the repository id rather than a tag, so the comparison is meaningless and ``resolve(_:)``
    /// would not re-download regardless of the answer.
    ///
    /// - Parameters:
    ///   - source: Adapter to check.
    ///   - latestTag: Latest version tag, obtained elsewhere.
    /// - Returns: `true` when the adapter is unrecorded or its recorded version differs.
    public func isUpdateAvailable(
        for source: AdapterSource, latestTag: String
    ) async -> Bool {
        await ensureLoaded()
        let key = Self.cacheKey(for: source)
        guard let info = adapterRegistry[key] else { return true }
        return info.version != latestTag
    }

    // MARK: - Internal Helpers

    /// Builds the cache key for an adapter source.
    ///
    /// The key is also the file name used under the adapter directory, so it has to stay
    /// path-safe. Shape by source:
    /// - GitHub release: `gh--{owner}--{repo}--{tag}--{asset}`
    /// - Hugging Face: `hf--{id, slashes replaced by --}`
    /// - Local: `local--{filename}`
    ///
    /// Only the repository id's slashes are replaced, so a tag or asset name containing a path
    /// separator produces a key that nests when it is appended to the directory.
    ///
    /// - Parameter source: Adapter source to key.
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
