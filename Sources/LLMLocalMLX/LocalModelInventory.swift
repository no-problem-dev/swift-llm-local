import Foundation
import LLMLocalClient

/// ディスク上にダウンロード済みのモデルを列挙・問い合わせ・削除する在庫（インベントリ）。
///
/// ``DestinationHubDownloader`` が書き込んだ保存先（`ModelStorageLayout`）を**ディスクの実体として
/// 読み取る**ため、モデルがメモリにロードされていなくても、アプリ再起動後でも正しく
/// 「ダウンロード済みか」を判定できる。インメモリのレジストリに依存しない。
///
/// ## 使用例
///
/// ```swift
/// let inventory = LocalModelInventory()
/// let downloaded = inventory.downloadedModels(among: ModelPresets.all)
/// if inventory.isDownloaded(ModelPresets.qwen3_5_2B) { /* 選択可能にする */ }
/// try inventory.delete(ModelPresets.qwen3_5_2B)  // 容量解放
/// ```
public struct LocalModelInventory: Sendable {

    /// モデルが保存されているルートディレクトリ。
    /// 既定は ``DestinationHubDownloader`` と同じ Application Support 配下。
    private let baseDirectory: URL

    /// - Parameter baseDirectory: モデル保存ルート。`nil` で既定（DL 先と一致）。
    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? ModelStorageLayout.defaultBaseDirectory()
    }

    /// 指定モデルがディスク上に**完全な形で**ダウンロード済みかを返す。
    ///
    /// - Parameter spec: 確認するモデル仕様。
    /// - Returns: 設定 + 重みが揃っていれば `true`。
    public func isDownloaded(_ spec: ModelSpec) -> Bool {
        guard let dir = ModelStorageLayout.directory(for: spec, base: baseDirectory) else {
            return false
        }
        return ModelStorageLayout.hasCompleteSnapshot(at: dir)
    }

    /// 候補のうちダウンロード済みのものだけを ``DownloadedModel`` として返す。
    ///
    /// 実サイズ・DL 時刻の近似（ディレクトリ mtime）込み。HF Hub のスナップショットは
    /// アプリ側のモデル ID と独立に保存されるため、列挙には候補リスト（プリセット等）を渡す。
    ///
    /// - Parameter specs: 確認するモデル仕様の候補。
    /// - Returns: ダウンロード済みモデルの配列（DL 時刻の新しい順）。
    public func downloadedModels(among specs: [ModelSpec]) -> [DownloadedModel] {
        specs.compactMap { spec -> DownloadedModel? in
            guard let dir = ModelStorageLayout.directory(for: spec, base: baseDirectory),
                  ModelStorageLayout.hasCompleteSnapshot(at: dir)
            else { return nil }
            return DownloadedModel(
                modelId: spec.id,
                directory: dir,
                sizeInBytes: ModelStorageLayout.directorySize(at: dir),
                downloadedAt: ModelStorageLayout.modificationDate(at: dir)
            )
        }
        .sorted { ($0.downloadedAt ?? .distantPast) > ($1.downloadedAt ?? .distantPast) }
    }

    /// 指定モデルのディスク実サイズ（バイト単位）。未ダウンロードなら `nil`。
    public func diskSize(of spec: ModelSpec) -> Int64? {
        guard let dir = ModelStorageLayout.directory(for: spec, base: baseDirectory),
              ModelStorageLayout.hasCompleteSnapshot(at: dir)
        else { return nil }
        return ModelStorageLayout.directorySize(at: dir)
    }

    /// ダウンロード済みモデルの合計ディスク使用量（バイト単位）。
    public func totalDiskSize(among specs: [ModelSpec]) -> Int64 {
        downloadedModels(among: specs).reduce(0) { $0 + ($1.sizeInBytes ?? 0) }
    }

    /// 指定モデルのダウンロード済みファイルをディスクから削除する（容量解放）。
    ///
    /// `.local` 指定のモデルは外部所有のため削除しない（no-op）。
    /// 未ダウンロードの場合も何もしない。
    ///
    /// - Parameter spec: 削除するモデル仕様。
    /// - Throws: ディレクトリ削除に失敗した場合。
    public func delete(_ spec: ModelSpec) throws {
        // 外部所有の `.local` は削除対象にしない（誤って利用者のファイルを消さない）。
        guard case .huggingFace = spec.base,
              let dir = ModelStorageLayout.directory(for: spec, base: baseDirectory),
              FileManager.default.fileExists(atPath: dir.path)
        else { return }
        try FileManager.default.removeItem(at: dir)
    }
}
