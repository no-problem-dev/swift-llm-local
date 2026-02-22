---
title: "Architecture"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../02_requirements/01_functional_requirements.md
---

# Architecture

## パッケージ全体構成

```
swift-llm-local/
├── Package.swift
├── Sources/
│   ├── LLMLocalClient/          # Layer 0: Protocol + 共通型（外部依存なし）
│   │   ├── LLMLocalBackend.swift
│   │   ├── GenerationConfig.swift
│   │   ├── GenerationStats.swift
│   │   ├── ModelSpec.swift
│   │   ├── ModelSource.swift
│   │   └── LLMLocalError.swift
│   │
│   ├── LLMLocalModels/          # Layer 1: モデル管理
│   │   ├── ModelManager.swift
│   │   ├── ModelCache.swift
│   │   ├── DownloadProgress.swift
│   │   └── AdapterManager.swift  # Phase 2
│   │
│   ├── LLMLocalMLX/             # Layer 2: MLX 具体実装
│   │   ├── MLXBackend.swift
│   │   └── MLXModelLoader.swift
│   │
│   └── LLMLocal/                # Umbrella + Service 層
│       ├── LLMLocal.swift        # 再エクスポート
│       └── LLMLocalService.swift # Backend + ModelManager 統合
│
├── Tests/
│   ├── LLMLocalClientTests/
│   ├── LLMLocalModelsTests/
│   └── LLMLocalMLXTests/       # 実機テスト（CI 除外）
│
└── specs/
```

## 依存関係図

```
                    ┌─────────────────┐
                    │   LLMLocal      │  Umbrella（再エクスポート）
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌──────────────┐ ┌────────────┐ ┌────────────────┐
     │ LLMLocalMLX  │ │LLMLocal    │ │ LLMLocalClient │
     │              │ │Models      │ │                │
     │ mlx-swift-lm │ │            │ │ Protocol のみ  │
     │ 依存あり      │ │ Foundation │ │ 外部依存なし    │
     └──────┬───────┘ └─────┬──────┘ └────────────────┘
            │               │                ▲
            └───────────────┴────────────────┘
                   LLMLocalClient に依存
```

## コア Protocol 設計

### LLMLocalBackend

```swift
// LLMLocalClient モジュール

/// ローカル LLM 推論バックエンドの抽象化
public protocol LLMLocalBackend: Sendable {
    /// モデルをロードする
    func loadModel(_ spec: ModelSpec) async throws

    /// テキストを生成する（ストリーミング）
    func generate(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, Error>

    /// モデルをアンロードしてメモリを解放する
    func unloadModel() async

    /// モデルがロード済みかどうか
    var isLoaded: Bool { get async }

    /// 現在ロードされているモデルの情報
    var currentModel: ModelSpec? { get async }
}
```

### LLMLocalService

```swift
// LLMLocal アンブレラモジュール（LLMLocalClient + LLMLocalModels に依存）

/// アプリケーション層が使う高レベルサービス
/// Backend + ModelManager を統合するファサード
public actor LLMLocalService {
    private let backend: any LLMLocalBackend
    private let modelManager: ModelManager

    public init(backend: any LLMLocalBackend, modelManager: ModelManager) {
        self.backend = backend
        self.modelManager = modelManager
    }

    /// デフォルト構成（MLX Backend + 標準キャッシュ）でサービスを作成
    /// Note: LLMLocalMLX を import するアプリ側で利用
    // public static func makeDefault() -> LLMLocalService

    /// モデルを準備して推論する（未DLなら自動DL）
    public func generate(
        model: ModelSpec,
        prompt: String,
        config: GenerationConfig = .default
    ) -> AsyncThrowingStream<String, Error>

    /// モデルのダウンロード状態を確認
    public func isModelCached(_ spec: ModelSpec) async -> Bool

    /// モデルを事前ダウンロード
    public func prefetch(_ spec: ModelSpec) async throws

    /// 最後の生成の統計情報を取得
    public var lastGenerationStats: GenerationStats? { get async }
}
```

## 型定義

### ModelSpec

```swift
/// モデルの完全な仕様定義
public struct ModelSpec: Sendable, Hashable, Codable {
    /// 一意な識別子（アプリ内で使用）
    public let id: String

    /// ベースモデルのソース
    public let base: ModelSource

    /// LoRA アダプターのソース（オプショナル）
    public let adapter: AdapterSource?

    /// 最大コンテキスト長
    public let contextLength: Int

    /// アプリ表示用の名前
    public let displayName: String

    /// モデルの説明
    public let description: String
}
```

### ModelSource

```swift
/// ベースモデルの取得先
public enum ModelSource: Sendable, Hashable, Codable {
    /// HuggingFace リポジトリから取得
    case huggingFace(id: String)

    /// ローカルファイルパスから取得
    case local(path: URL)
}
```

### AdapterSource

```swift
/// LoRA アダプターの取得先
public enum AdapterSource: Sendable, Hashable, Codable {
    /// GitHub Releases から取得
    case gitHubRelease(repo: String, tag: String, asset: String)

    /// HuggingFace リポジトリから取得
    case huggingFace(id: String)

    /// ローカルファイルパスから取得
    case local(path: URL)
}
```

### GenerationConfig

```swift
/// テキスト生成のパラメータ
public struct GenerationConfig: Sendable {
    /// 最大生成トークン数
    public var maxTokens: Int

    /// サンプリング温度（0.0-2.0）
    public var temperature: Float

    /// Top-p サンプリング（0.0-1.0）
    public var topP: Float

    /// デフォルト設定
    public static let `default` = GenerationConfig(
        maxTokens: 1024,
        temperature: 0.7,
        topP: 0.9
    )
}
```

### GenerationStats

```swift
/// 生成結果の統計情報
public struct GenerationStats: Sendable {
    /// 生成トークン数
    public let tokenCount: Int

    /// トークン生成速度（tok/s）
    public let tokensPerSecond: Double

    /// 合計所要時間
    public let duration: Duration
}
```

## エラー設計

```swift
/// LLMLocal 全体のエラー型
public enum LLMLocalError: Error, Sendable {
    /// モデルのダウンロードに失敗
    case downloadFailed(modelId: String, underlying: Error)

    /// モデルのロードに失敗
    case loadFailed(modelId: String, underlying: Error)

    /// メモリ不足でモデルをロードできない
    case insufficientMemory(required: Int, available: Int)

    /// ストレージ容量不足
    case insufficientStorage(required: Int64, available: Int64)

    /// モデルが未ロードの状態で推論を試みた
    case modelNotLoaded

    /// モデルロード中に別のロードを試みた
    case loadInProgress

    /// 生成がキャンセルされた
    case cancelled

    /// アダプターの合成に失敗（Phase 2）
    case adapterMergeFailed(underlying: Error)

    /// 非対応のモデル形式
    case unsupportedModelFormat(String)
}
```

## アプリ側の利用イメージ

```swift
import LLMLocal

// 1. モデル定義
let swallow = ModelSpec(
    id: "swallow-7b",
    base: .huggingFace(id: "mlx-community/swallow-7b-instruct-4bit"),
    adapter: nil,
    contextLength: 4096,
    displayName: "Swallow 7B",
    description: "日本語特化 LLM"
)

// 2. サービス初期化
let service = LLMLocalService(
    backend: MLXBackend(),
    modelManager: ModelManager()
)

// 3. ストリーミング生成
for try await token in service.generate(model: swallow, prompt: "日本の首都は") {
    print(token, terminator: "")
}
```
