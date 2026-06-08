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
        self.baseDirectory = baseDirectory ?? Self.defaultBaseDirectory()
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

        let destination = baseDirectory
            .appendingPathComponent(repoID.namespace, isDirectory: true)
            .appendingPathComponent(repoID.name, isDirectory: true)

        // 既にスナップショットが揃っていれば再ダウンロードしない（useLatest 指定時を除く）。
        if !useLatest, Self.hasCompleteSnapshot(at: destination) {
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

    // MARK: - Snapshot Completeness

    /// destination に「設定 + 重み」が揃っているかを判定します。
    ///
    /// 重みは単一（`model.safetensors`）と分割（`*.index.json`）の両方を許容します。
    static func hasCompleteSnapshot(at directory: URL) -> Bool {
        let fileManager = FileManager.default
        let config = directory.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: config.path) else { return false }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        let hasWeights = contents.contains { name in
            name.hasSuffix(".safetensors") || name.hasSuffix(".safetensors.index.json")
        }
        return hasWeights
    }

    // MARK: - Default Directory

    private static func defaultBaseDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var base = support.appendingPathComponent("swift-llm-local/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // 数 GB のモデルは再取得可能なので iCloud バックアップから除外する。
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        return base
    }
}
