---
title: "Model Manager Design"
created: 2026-02-22
status: draft
references:
  - ./01_architecture.md
  - ../02_requirements/01_functional_requirements.md
---

# Model Manager Design

## 概要

`ModelManager` はモデルのダウンロード・キャッシュ・ストレージ管理を担当する actor。

## ModelManager

```swift
// LLMLocalModels モジュール

import LLMLocalClient

public actor ModelManager {

    /// キャッシュディレクトリ
    private let cacheDirectory: URL

    /// ダウンロード済みモデルのメタデータ
    private var cachedMetadata: [String: CachedModelInfo] = [:]

    public init(cacheDirectory: URL? = nil) {
        // デフォルト: Application Support/LLMLocal/models/
        self.cacheDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("LLMLocal/models")
    }

    // MARK: - Query

    /// キャッシュ済みモデルの一覧を取得
    public func cachedModels() -> [CachedModelInfo]

    /// モデルがキャッシュ済みか判定
    public func isCached(_ spec: ModelSpec) -> Bool

    /// キャッシュの合計サイズを取得
    public func totalCacheSize() throws -> Int64

    // MARK: - Download

    /// モデルをダウンロードしてキャッシュする
    public func download(_ spec: ModelSpec) async throws

    /// ダウンロード進捗付きでモデルをダウンロード（Phase 2）
    public func downloadWithProgress(
        _ spec: ModelSpec
    ) -> AsyncThrowingStream<DownloadProgress, Error>

    // MARK: - Delete

    /// モデルのキャッシュを削除
    public func deleteCache(for spec: ModelSpec) throws

    /// 全キャッシュを削除
    public func clearAllCache() throws
}
```

## CachedModelInfo

```swift
/// キャッシュ済みモデルの情報
public struct CachedModelInfo: Sendable, Codable {
    /// モデル ID
    public let modelId: String

    /// モデル表示名
    public let displayName: String

    /// キャッシュサイズ（バイト）
    public let sizeInBytes: Int64

    /// ダウンロード日時
    public let downloadedAt: Date

    /// ローカルパス
    public let localPath: URL
}
```

## DownloadProgress（Phase 2）

```swift
/// ダウンロード進捗情報
public struct DownloadProgress: Sendable {
    /// 進捗率（0.0 - 1.0）
    public let fraction: Double

    /// ダウンロード済みバイト数
    public let completedBytes: Int64

    /// 合計バイト数
    public let totalBytes: Int64

    /// 現在ダウンロード中のファイル名
    public let currentFile: String?
}
```

## キャッシュ戦略

### ディレクトリ構成

```
Application Support/
└── LLMLocal/
    ├── models/
    │   ├── mlx-community--swallow-7b-instruct-4bit/
    │   │   ├── config.json
    │   │   ├── tokenizer.json
    │   │   ├── model.safetensors
    │   │   └── metadata.json          # 独自メタデータ
    │   └── mlx-community--gemma-2-2b-it-4bit/
    │       └── ...
    ├── adapters/
    │   └── my-org--swallow-custom-v1/
    │       └── adapters.safetensors
    └── registry.json                   # キャッシュインデックス
```

### HuggingFace Hub キャッシュとの関係

mlx-swift-lm の `loadModel(id:)` は HuggingFace Hub の独自キャッシュ（`~/Library/Caches/huggingface/hub/`）を使う。

**Phase 1 の方針**: mlx-swift-lm のキャッシュ機構をそのまま活用する。独自キャッシュディレクトリは将来のアダプター管理（Phase 2）に使用する。

**理由**:
- 車輪の再発明を避ける
- HF Hub のキャッシュはレジューム対応済み
- `ModelManager` は「キャッシュ済みかの判定」「削除」「サイズ計算」に注力する

## アダプター管理（Phase 2）

### GitHub Releases からのダウンロード

```swift
extension ModelManager {
    /// GitHub Releases からアダプターをダウンロード
    func downloadAdapter(
        from source: AdapterSource
    ) async throws -> URL {
        switch source {
        case .gitHubRelease(let repo, let tag, let asset):
            let url = URL(string: "https://github.com/\(repo)/releases/download/\(tag)/\(asset)")!
            // URLSession でダウンロード → adapters/ に配置
            ...
        case .huggingFace(let id):
            // HF Hub からダウンロード
            ...
        case .local(let path):
            return URL(filePath: path)
        }
    }
}
```
