import Foundation
import LLMLocalClient
import PersistenceCore
import PersistenceFileSystem

// MARK: - AdapterNetworkDelegate

/// リモートソースからアダプターファイルをダウンロードするプロトコル
///
/// GitHub Releases や Hugging Face Hub からのアダプターファイル取得に関する
/// 実際のネットワーク操作を処理します。テスト用の依存性注入を可能にするプロトコルです。
public protocol AdapterNetworkDelegate: Sendable {
    /// GitHub Release からアダプターをダウンロードします。
    ///
    /// - Parameters:
    ///   - repo: GitHub リポジトリ（例: "owner/repo"）。
    ///   - tag: リリースタグ（例: "v1.0"）。
    ///   - asset: アセットファイル名（例: "adapter.safetensors"）。
    ///   - destination: ダウンロードファイルを保存するローカルファイルURL。
    func downloadGitHubRelease(
        repo: String, tag: String, asset: String, destination: URL
    ) async throws

    /// Hugging Face Hub からアダプターをダウンロードします。
    ///
    /// - Parameters:
    ///   - id: Hugging Face のモデル/アダプター識別子（例: "user/adapter"）。
    ///   - destination: ダウンロードファイルを保存するローカルファイルURL。
    func downloadHuggingFace(id: String, destination: URL) async throws
}

// MARK: - StubAdapterNetworkDelegate

/// Phase 2 用スタブデリゲート — ネットワークアクセスなしでプレースホルダーファイルを作成します。
///
/// 実際のネットワークデリゲートが提供されない場合のデフォルトとして使用されます。
/// Phase 3 で実際のダウンロード実装に置き換えられます。
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

/// キャッシュされたアダプターの情報
///
/// ローカルにダウンロード・キャッシュされたアダプターのバージョン、ソース、
/// ダウンロード日時、ローカルファイルパスを追跡します。
public struct AdapterInfo: Sendable, Codable {
    /// アダプターソースから導出された一意のキャッシュキー。
    public let key: String

    /// バージョン識別子（例: リリースタグまたは HuggingFace モデルID）。
    public let version: String

    /// 元のソース指定。
    public let source: AdapterSource

    /// アダプターがダウンロードされた日時。
    public let downloadedAt: Date

    /// ローカルにキャッシュされたアダプターファイルのパス。
    public let localPath: URL

    /// 新しいアダプター情報を作成します。
    ///
    /// - Parameters:
    ///   - key: 一意のキャッシュキー。
    ///   - version: バージョン識別子。
    ///   - source: 元のアダプターソース。
    ///   - downloadedAt: アダプターがダウンロードされた日時。
    ///   - localPath: ローカルにキャッシュされたファイルのパス。
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

/// LoRA アダプターのダウンロード・バージョン管理・ローカルストレージを管理するアクター
///
/// `AdapterRegistry` は各種ソース（GitHub Releases、HuggingFace、ローカルパス）
/// からのアダプターダウンロードと、バージョン追跡によるローカルキャッシュ管理を行います。
///
/// ## Usage
///
/// ```swift
/// let registry = AdapterRegistry()
///
/// // アダプターソースをローカルファイルURLに解決
/// let localURL = try await registry.resolve(
///     .gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
/// )
///
/// // 新しいバージョンが利用可能か確認
/// let needsUpdate = await registry.isUpdateAvailable(
///     for: source, latestTag: "v2.0"
/// )
/// ```
public actor AdapterRegistry {

    /// アダプターファイルが保存されるディレクトリ。
    private let adapterDirectory: URL

    /// ダウンロード済みアダプターのインメモリレジストリ。
    /// AdapterSource から導出された一意のキーをキーとします。
    private var adapterRegistry: [String: AdapterInfo] = [:]

    /// アダプターレジストリを永続化するストア。
    private let cache: any RegistryStore<AdapterInfo>

    /// アダプターダウンロード用のネットワークデリゲート（テスト用に注入可能）。
    private let networkDelegate: any AdapterNetworkDelegate

    /// 新しいアダプターレジストリを作成します。
    ///
    /// - Parameters:
    ///   - adapterDirectory: アダプターファイルとレジストリを保存するディレクトリ。
    ///     デフォルトは `~/Library/Application Support/LLMLocal/adapters`。
    ///   - registryStore: レジストリの永続化ストア。
    ///     `nil` の場合、アダプターディレクトリの `adapter-registry.json` を使用します。
    ///   - networkDelegate: ダウンロードを実行するオプションのデリゲート。
    ///     `nil` の場合、プレースホルダーファイルを作成するスタブデリゲートが使用されます。
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
        self.adapterRegistry = cache.load()
        self.networkDelegate = networkDelegate ?? StubAdapterNetworkDelegate()
    }

    // MARK: - Public API

    /// AdapterSource をローカルファイルURLに解決します。
    ///
    /// まだキャッシュされていない場合はアダプターをダウンロードします。
    /// ローカルソースの場合はファイルの存在を検証し、パスを直接返します。
    ///
    /// - Parameter source: 解決するアダプターソース。
    /// - Returns: アダプターを指すローカルファイルURL。
    /// - Throws: ローカルアダプターが見つからない場合は ``LLMLocalError/adapterMergeFailed(reason:)``、
    ///   リモート取得に失敗した場合はダウンロードエラー。
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

    /// すべてのキャッシュ済みアダプターを返します。
    ///
    /// - Returns: キャッシュされた全アダプターの ``AdapterInfo`` 配列。
    public func cachedAdapters() -> [AdapterInfo] {
        Array(adapterRegistry.values)
    }

    /// アダプターがキャッシュされているか確認します。
    ///
    /// - Parameter source: 確認するアダプターソース。
    /// - Returns: アダプターがダウンロード・キャッシュ済みの場合は `true`。
    public func isCached(_ source: AdapterSource) -> Bool {
        let key = Self.cacheKey(for: source)
        return adapterRegistry[key] != nil
    }

    /// キャッシュされたアダプターのレジストリエントリを削除します。
    ///
    /// アダプターがキャッシュされていない場合、このメソッドは何もしません。
    ///
    /// - Parameter source: 削除するアダプターソース。
    /// - Throws: レジストリの永続化に失敗した場合のエラー。
    public func deleteAdapter(for source: AdapterSource) throws {
        let key = Self.cacheKey(for: source)
        adapterRegistry.removeValue(forKey: key)
        try cache.save(adapterRegistry)
    }

    /// すべてのキャッシュ済みアダプターレジストリエントリを削除します。
    ///
    /// - Throws: レジストリの永続化に失敗した場合のエラー。
    public func clearAll() throws {
        adapterRegistry.removeAll()
        try cache.save(adapterRegistry)
    }

    /// キャッシュされたアダプターの新しいバージョンが利用可能か確認します。
    ///
    /// アダプターがキャッシュされていないか、キャッシュされたバージョンが
    /// 指定された最新タグと異なる場合に `true` を返します。
    ///
    /// - Parameters:
    ///   - source: 確認するアダプターソース。
    ///   - latestTag: 比較対象の最新バージョンタグ。
    /// - Returns: アップデートが利用可能な場合は `true`。
    public func isUpdateAvailable(
        for source: AdapterSource, latestTag: String
    ) -> Bool {
        let key = Self.cacheKey(for: source)
        guard let info = adapterRegistry[key] else { return true }
        return info.version != latestTag
    }

    // MARK: - Internal Helpers

    /// アダプターソースの一意のキャッシュキーを生成します。
    ///
    /// キーのフォーマットはソースタイプにより異なります:
    /// - GitHub Release: `gh--{owner}--{repo}--{tag}--{asset}`
    /// - HuggingFace: `hf--{/ を -- に置換した id}`
    /// - Local: `local--{filename}`
    ///
    /// - Parameter source: アダプターソース。
    /// - Returns: 辞書キーおよびファイルシステム安全なディレクトリ/ファイル名として
    ///   使用可能な一意の文字列キー。
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
