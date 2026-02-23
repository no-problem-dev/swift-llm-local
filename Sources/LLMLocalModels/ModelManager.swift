import Foundation
import LLMLocalClient

/// モデルキャッシュのメタデータ管理とキャッシュ操作を提供するアクター
///
/// `ModelManager` はローカルにダウンロード・キャッシュされたモデルを追跡し、
/// キャッシュディレクトリ内の `registry.json` ファイルにメタデータを保存します。
/// 実際のモデル重みは MLX バックエンドが Hugging Face Hub キャッシュ経由で管理し、
/// このアクターはメタデータレジストリのみを管理します。
///
/// ## Phase 1 スコープ
///
/// - キャッシュ済みモデルの一覧表示
/// - モデルのキャッシュ有無確認
/// - 合計キャッシュサイズの計算
/// - 特定モデルのキャッシュメタデータ削除
/// - 全キャッシュメタデータのクリア
/// - モデルの登録（ダウンロードスタブ。実際の HF ダウンロードは MLXBackend が担当）
public actor ModelManager {

    /// レジストリファイルとアダプターファイルを保存するディレクトリ。
    private let cacheDirectory: URL

    /// モデルIDをキーとするモデルメタデータのインメモリキャッシュ。
    private var cachedMetadata: [String: CachedModelInfo] = [:]

    /// レジストリをディスクに永続化する内部ヘルパー。
    private let cache: ModelCache

    /// 実際のダウンロード処理を行うデリゲート。
    private let downloadDelegate: any DownloadProgressDelegate

    /// レジューム可能なダウンロード用のバックグラウンドダウンローダーインスタンス。
    private let _backgroundDownloader: BackgroundDownloader

    /// レジューム可能なバックグラウンドモデルダウンロードを管理するダウンローダー。
    ///
    /// バックグラウンドモデルダウンロードの開始・一時停止・再開・キャンセルに使用します。
    public var backgroundDownloader: BackgroundDownloader {
        _backgroundDownloader
    }

    /// 新しいモデルマネージャーを作成します。
    ///
    /// - Parameters:
    ///   - cacheDirectory: レジストリとアダプターファイルを保存するディレクトリ。
    ///     デフォルトは `~/Library/Application Support/LLMLocal/models`。
    ///   - downloadDelegate: ダウンロードを実行するオプションのデリゲート。
    ///     `nil` の場合、即座のダウンロードをシミュレートするスタブデリゲートが使用されます。
    ///   - backgroundDownloader: オプションのバックグラウンドダウンローダーインスタンス。
    ///     `nil` の場合、キャッシュディレクトリを使用してデフォルトの ``BackgroundDownloader`` が作成されます。
    public init(
        cacheDirectory: URL? = nil,
        downloadDelegate: (any DownloadProgressDelegate)? = nil,
        backgroundDownloader: BackgroundDownloader? = nil
    ) {
        let dir = cacheDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("LLMLocal/models")
        self.cacheDirectory = dir
        self.cache = ModelCache(directory: dir)
        self.cachedMetadata = cache.load()
        self.downloadDelegate = downloadDelegate ?? StubDownloadDelegate()
        self._backgroundDownloader = backgroundDownloader
            ?? BackgroundDownloader(
                storageDirectory: dir.appendingPathComponent("bg-downloads")
            )
    }

    // MARK: - Public API

    /// すべてのキャッシュ済みモデルの一覧を返します。
    ///
    /// - Returns: 登録済みの全モデルの ``CachedModelInfo`` 配列。
    public func cachedModels() -> [CachedModelInfo] {
        Array(cachedMetadata.values)
    }

    /// 指定されたモデル仕様がキャッシュに登録されているかを確認します。
    ///
    /// - Parameter spec: 確認するモデル仕様。
    /// - Returns: モデルがキャッシュに登録されている場合は `true`。
    public func isCached(_ spec: ModelSpec) -> Bool {
        cachedMetadata[spec.id] != nil
    }

    /// すべてのキャッシュ済みモデルの合計サイズをバイト単位で返します。
    ///
    /// - Returns: 全登録モデルの `sizeInBytes` の合計。
    /// - Throws: 現在はスローしませんが、将来のファイルシステムベースのサイズ計算に対応するシグネチャです。
    public func totalCacheSize() throws -> Int64 {
        cachedMetadata.values.reduce(0) { $0 + $1.sizeInBytes }
    }

    /// 特定モデルのキャッシュメタデータエントリを削除します。
    ///
    /// モデルがキャッシュされていない場合、このメソッドは何も行いません。
    ///
    /// - Parameter spec: 削除するモデル仕様。
    /// - Throws: レジストリの永続化に失敗した場合。
    public func deleteCache(for spec: ModelSpec) throws {
        cachedMetadata.removeValue(forKey: spec.id)
        try cache.save(cachedMetadata)
    }

    /// すべてのキャッシュ済みモデルメタデータを削除します。
    ///
    /// - Throws: レジストリの永続化に失敗した場合。
    public func clearAllCache() throws {
        cachedMetadata.removeAll()
        try cache.save(cachedMetadata)
    }

    /// モデルをキャッシュメタデータに登録します。
    ///
    /// Phase 1 のスタブです。Phase 2 では実際のダウンロードは MLX バックエンドが処理します。
    /// 現在は指定されたサイズと現在のタイムスタンプでメタデータエントリを作成します。
    ///
    /// 同じIDのモデルが既に登録されている場合は上書きされます。
    ///
    /// - Parameters:
    ///   - spec: 登録するモデル仕様。
    ///   - sizeInBytes: モデルのサイズ（バイト単位）。
    /// - Throws: レジストリの永続化に失敗した場合。
    public func registerModel(_ spec: ModelSpec, sizeInBytes: Int64) throws {
        let info = CachedModelInfo(
            modelId: spec.id,
            displayName: spec.displayName,
            sizeInBytes: sizeInBytes,
            downloadedAt: Date(),
            localPath: cacheDirectory.appendingPathComponent(spec.id)
        )
        cachedMetadata[spec.id] = info
        try cache.save(cachedMetadata)
    }

    // MARK: - Download with Progress

    /// 進捗報告付きでモデルをダウンロードします。
    ///
    /// ダウンロードの進行に応じて ``DownloadProgress`` の更新を生成する
    /// `AsyncThrowingStream` を返します。ダウンロードが完了しモデルがキャッシュに
    /// 登録されるとストリームが完了します。
    ///
    /// Phase 2 では HuggingFace Hub ダウンロードを進捗追跡付きでラップします。
    /// 現在はモデル登録後に開始（0.0）と完了（1.0）を生成して進捗をシミュレートします。
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
