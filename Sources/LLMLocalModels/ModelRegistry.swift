import Foundation
import LLMLocalClient
import PersistenceCore
import PersistenceFileSystem

/// モデルキャッシュのメタデータ管理とキャッシュ操作を提供するアクター
///
/// `ModelRegistry` はローカルにダウンロード・キャッシュされたモデルを追跡し、
/// ``RegistryStore`` 経由でメタデータを永続化する。
/// 実際のモデル重みは MLX バックエンドが Hugging Face Hub キャッシュ経由で管理し、
/// このアクターはメタデータレジストリのみを管理する。
public actor ModelRegistry {

    /// レジストリファイルとアダプターファイルを保存するディレクトリ。
    private let cacheDirectory: URL

    /// モデルIDをキーとするモデルメタデータのインメモリキャッシュ。
    private var cachedMetadata: [String: CachedModelInfo] = [:]

    /// ストアからの初回ロードが完了しているかどうか。
    private var isLoaded: Bool = false

    /// レジストリを永続化するストア。
    private let cache: any RegistryStore<CachedModelInfo>

    /// 実際のダウンロード処理を行うデリゲート。
    private let downloadDelegate: any DownloadProgressDelegate

    /// レジューム可能なダウンロード用のバックグラウンドダウンローダーインスタンス。
    private let _backgroundDownloader: BackgroundDownloader

    /// レジューム可能なバックグラウンドモデルダウンロードを管理するダウンローダー。
    ///
    /// バックグラウンドモデルダウンロードの開始・一時停止・再開・キャンセルに使用する。
    public var backgroundDownloader: BackgroundDownloader {
        _backgroundDownloader
    }

    /// 新しいモデルレジストリを作成する。
    ///
    /// - Parameters:
    ///   - cacheDirectory: レジストリとアダプターファイルを保存するディレクトリ。
    ///     デフォルトは `~/Library/Application Support/LLMLocal/models`。
    ///   - registryStore: レジストリの永続化ストア。
    ///     `nil` の場合、キャッシュディレクトリの `registry.json` を使用する。
    ///   - downloadDelegate: ダウンロードを実行するオプションのデリゲート。
    ///     `nil` の場合、即座のダウンロードをシミュレートするスタブデリゲートを使用する。
    ///   - backgroundDownloader: オプションのバックグラウンドダウンローダーインスタンス。
    ///     `nil` の場合、キャッシュディレクトリを使用してデフォルトの ``BackgroundDownloader`` を作成する。
    public init(
        cacheDirectory: URL? = nil,
        registryStore: (any RegistryStore<CachedModelInfo>)? = nil,
        downloadDelegate: (any DownloadProgressDelegate)? = nil,
        backgroundDownloader: BackgroundDownloader? = nil
    ) {
        let dir = cacheDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("LLMLocal/models")
        self.cacheDirectory = dir
        self.cache = registryStore
            ?? FileSystemRegistryStore<CachedModelInfo>(directory: dir)
        self.downloadDelegate = downloadDelegate ?? StubDownloadDelegate()
        self._backgroundDownloader = backgroundDownloader
            ?? BackgroundDownloader(
                storageDirectory: dir.appendingPathComponent("bg-downloads")
            )
    }

    // MARK: - Private Helpers

    /// ストアからのデータが未ロードの場合、非同期でロードする。
    private func ensureLoaded() async {
        guard !isLoaded else { return }
        cachedMetadata = await cache.load()
        isLoaded = true
    }

    // MARK: - Public API

    /// すべてのキャッシュ済みモデルの一覧を返す。
    ///
    /// - Returns: 登録済みの全モデルの ``CachedModelInfo`` 配列。
    public func cachedModels() async -> [CachedModelInfo] {
        await ensureLoaded()
        return Array(cachedMetadata.values)
    }

    /// 指定されたモデル仕様がキャッシュに登録されているかを確認する。
    ///
    /// - Parameter spec: 確認するモデル仕様。
    /// - Returns: モデルがキャッシュに登録されている場合は `true`。
    public func isCached(_ spec: ModelSpec) async -> Bool {
        await ensureLoaded()
        return cachedMetadata[spec.id] != nil
    }

    /// すべてのキャッシュ済みモデルの合計サイズをバイト単位で返す。
    ///
    /// - Returns: 全登録モデルの `sizeInBytes` の合計。
    /// - Throws: 現在はスローしないが、将来のファイルシステムベースのサイズ計算に対応するシグネチャ。
    public func totalCacheSize() async throws -> Int64 {
        await ensureLoaded()
        return cachedMetadata.values.reduce(0) { $0 + $1.sizeInBytes }
    }

    /// 特定モデルのキャッシュメタデータエントリを削除し、モデルファイルも除去する。
    ///
    /// モデルがキャッシュされていない場合、このメソッドは何も行わない。
    /// `modelFilesPath` が設定されている場合、そのディレクトリを削除してディスク容量を解放する。
    ///
    /// - Parameter spec: 削除するモデル仕様。
    /// - Throws: レジストリの永続化に失敗した場合。
    public func deleteCache(for spec: ModelSpec) async throws {
        await ensureLoaded()
        if let info = cachedMetadata[spec.id], let filesPath = info.modelFilesPath {
            try? FileManager.default.removeItem(at: filesPath)
        }
        cachedMetadata.removeValue(forKey: spec.id)
        try await cache.save(cachedMetadata)
    }

    /// すべてのキャッシュ済みモデルメタデータを削除し、モデルファイルも除去する。
    ///
    /// - Throws: レジストリの永続化に失敗した場合。
    public func clearAllCache() async throws {
        await ensureLoaded()
        for info in cachedMetadata.values {
            if let filesPath = info.modelFilesPath {
                try? FileManager.default.removeItem(at: filesPath)
            }
        }
        cachedMetadata.removeAll()
        try await cache.save(cachedMetadata)
    }

    /// モデルをキャッシュメタデータに登録する。
    ///
    /// 指定されたサイズと現在のタイムスタンプでメタデータエントリを作成する。
    /// 実際のダウンロードは MLX バックエンドが処理する。
    ///
    /// 同じIDのモデルが既に登録されている場合は上書きされる（upsert）。
    ///
    /// - Parameters:
    ///   - spec: 登録するモデル仕様。
    ///   - sizeInBytes: モデルのサイズ（バイト単位）。
    ///   - modelFilesPath: モデル実ファイルのパス。削除時にこのパスを使用してファイルを除去する。
    /// - Throws: レジストリの永続化に失敗した場合。
    public func registerModel(
        _ spec: ModelSpec,
        sizeInBytes: Int64,
        modelFilesPath: URL? = nil
    ) async throws {
        await ensureLoaded()
        let info = CachedModelInfo(
            modelId: spec.id,
            displayName: spec.displayName,
            sizeInBytes: sizeInBytes,
            downloadedAt: Date(),
            localPath: cacheDirectory.appendingPathComponent(spec.id),
            modelFilesPath: modelFilesPath
        )
        cachedMetadata[spec.id] = info
        try await cache.save(cachedMetadata)
    }

    // MARK: - Download with Progress

    /// 進捗報告付きでモデルをダウンロードする。
    ///
    /// ダウンロードの進行に応じて ``DownloadProgress`` の更新を生成する
    /// `AsyncThrowingStream` を返す。ダウンロードが完了しモデルがキャッシュに
    /// 登録されるとストリームが完了する。
    ///
    /// - Parameter spec: ダウンロードするモデル仕様。
    /// - Returns: ``DownloadProgress`` 値の ``AsyncThrowingStream``。
    public func downloadWithProgress(
        _ spec: ModelSpec
    ) -> AsyncThrowingStream<DownloadProgress, Error> {
        let delegate = self.downloadDelegate

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                do {
                    try Task.checkCancellation()

                    // Yield initial progress
                    continuation.yield(DownloadProgress(
                        fraction: 0.0,
                        completedBytes: 0,
                        totalBytes: 0,
                        currentFile: nil
                    ))

                    try Task.checkCancellation()

                    // Perform download via delegate
                    let sizeInBytes = try await delegate.download(spec) { progress in
                        continuation.yield(progress)
                    }

                    try Task.checkCancellation()

                    // Register model in cache
                    if let self = self {
                        try await self.registerModel(spec, sizeInBytes: sizeInBytes)
                    }

                    // Yield completion
                    continuation.yield(DownloadProgress(
                        fraction: 1.0,
                        completedBytes: sizeInBytes,
                        totalBytes: sizeInBytes,
                        currentFile: nil
                    ))

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
