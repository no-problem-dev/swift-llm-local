import Foundation
import HuggingFace
import LLMLocalClient
import MLXLMCommon

/// アプリ管理ディレクトリへ明示 destination でスナップショットを取得する ``Downloader``。
///
/// ## なぜ独自実装か
///
/// mlx-swift-lm の `#hubDownloader()` が使う swift-huggingface のキャッシュ経路
/// （`downloadSnapshot(returnCachePath: true)`）は、iOS サンドボックスの
/// `Caches/huggingface/hub` 上で **LFS 大ファイル（model.safetensors 等）の
/// キャッシュパス解決に失敗**し `cachedPathResolutionFailed` を投げる。
///
/// 明示 destination を渡す overload（`downloadSnapshot(to:)`）は、キャッシュ解決が
/// 失敗しても「destination へ move」にフォールバックするため throw しない。
/// 代わりにキャッシュ照合が効かないため、ダウンロード済みの検出は本実装が
/// destination ディレクトリの内容で行う。
public struct DestinationHubDownloader: Downloader {
    private let hub: HubClient
    private let baseDirectory: URL

    /// - Parameters:
    ///   - hub: Hugging Face Hub クライアント。デフォルトは匿名アクセス。
    ///   - baseDirectory: モデルを配置するルート。デフォルトは
    ///     Application Support 配下（バックアップ対象外に設定）。
    public init(hub: HubClient = HubClient(), baseDirectory: URL? = nil) {
        self.hub = hub
        self.baseDirectory = baseDirectory ?? ModelStorageLayout.defaultBaseDirectory()
    }

    public func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: id) else {
            throw LLMLocalError.downloadFailed(modelId: id, reason: "Invalid repository id: \(id)")
        }

        let destination = ModelStorageLayout.destination(for: repoID, base: baseDirectory)

        // 既にスナップショットが揃っていれば再ダウンロードしない（useLatest 指定時を除く）。
        if !useLatest, ModelStorageLayout.hasCompleteSnapshot(at: destination) {
            let progress = Progress(totalUnitCount: 1)
            progress.completedUnitCount = 1
            progressHandler(progress)
            return destination
        }

        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        do {
            return try await hub.downloadSnapshot(
                of: repoID,
                to: destination,
                revision: revision ?? "main",
                matching: patterns,
                progressHandler: { @MainActor progress in progressHandler(progress) }
            )
        } catch {
            throw LLMLocalError.downloadFailed(modelId: id, reason: "\(error)")
        }
    }

}
