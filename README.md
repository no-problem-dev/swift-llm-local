# swift-llm-local

iOS / macOS デバイス上でローカル LLM 推論を実現する Swift パッケージ

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018.0+%20%7C%20macOS%2015.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 概要

`swift-llm-local` は、MLX バックエンドを活用してオンデバイス LLM 推論を行うための Swift パッケージです。クラウド API に依存せず、プライバシーを保護しながら低レイテンシの AI 機能をアプリに組み込めます。

`mlx-swift-lm` が提供する低レベル推論 API の上に、プロダクションアプリに必要なアプリケーション層の抽象化を追加します。

### 主な機能

- ✅ **プロトコルベースのバックエンド抽象化** - MLX 実装に依存しない柔軟な設計
- ✅ **ストリーミング生成** - トークン単位の AsyncThrowingStream による逐次出力
- ✅ **モデル管理** - ダウンロード追跡・レジューム・ローカルキャッシュ
- ✅ **メモリ監視** - デバイスメモリに応じた自動アンロード
- ✅ **LoRA アダプタ対応** - GitHub Releases / HuggingFace / ローカルから読み込み
- ✅ **マルチモデル切替** - LRU ベースの自動モデルスワッピング
- ✅ **キャンセルサポート** - ユーザー起点の生成中断に対応
- ✅ **Actor ベース設計** - Swift Concurrency による安全な並行処理

## 必要要件

- iOS 18.0+
- macOS 15.0+
- Swift 6.2+

## 依存関係

- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (≥2.30.0) - MLX 推論フレームワーク

## インストール

### Swift Package Manager

`Package.swift` に以下を追加してください：

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-local.git", from: "0.3.0")
]
```

ターゲットの依存関係に追加：

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "LLMLocal", package: "swift-llm-local"),
    ]
)
```

#### モジュール構成

用途に応じて必要なモジュールのみをインポートできます：

| モジュール | 用途 |
|-----------|------|
| `LLMLocal` | アンブレラ（全モジュール + LLMLocalService） |
| `LLMLocalClient` | プロトコル層のみ（アプリ抽象化用、外部依存なし） |
| `LLMLocalMLX` | MLX バックエンド（DI 設定用） |

## クイックスタート

```swift
import LLMLocal

// 1. サービスを作成
let service = LLMLocalService(
    backend: MLXBackend(),
    modelManager: ModelManager()
)

// 2. プリセットモデルで生成（ストリーミング）
for try await token in service.generate(
    model: ModelPresets.gemma2B,
    prompt: "SwiftUIでリストを作る方法を教えて"
) {
    print(token, terminator: "")
}
```

## 使い方

### 基本的なテキスト生成

```swift
import LLMLocal

let service = LLMLocalService(
    backend: MLXBackend(),
    modelManager: ModelManager()
)

// ストリーミング生成
for try await token in service.generate(
    model: ModelPresets.gemma2B,
    prompt: "Hello, world!"
) {
    print(token, terminator: "")
}

// 生成統計の確認
if let stats = await service.lastGenerationStats {
    print("\n\(stats.tokenCount) tokens at \(stats.tokensPerSecond) tok/s")
}
```

### 生成パラメータのカスタマイズ

```swift
let config = GenerationConfig(
    maxTokens: 512,
    temperature: 0.7,
    topP: 0.9
)

for try await token in service.generate(
    model: ModelPresets.gemma2B,
    prompt: "創造的な短い物語を書いて",
    config: config
) {
    print(token, terminator: "")
}
```

### カスタムモデルの指定

```swift
let customModel = ModelSpec(
    id: "my-custom-model",
    base: .huggingFace(id: "mlx-community/some-model-4bit"),
    adapter: nil,
    contextLength: 4096,
    displayName: "Custom Model",
    description: "My fine-tuned model"
)

for try await token in service.generate(
    model: customModel,
    prompt: "Hello!"
) {
    print(token, terminator: "")
}
```

### メモリ監視付きサービス

```swift
let service = LLMLocalService(
    backend: MLXBackend(),
    modelManager: ModelManager(),
    memoryMonitor: MemoryMonitor()
)

// メモリ不足時に自動でモデルがアンロードされます
```

### LoRA アダプタの使用

```swift
let modelWithAdapter = ModelSpec(
    id: "gemma-with-lora",
    base: .huggingFace(id: "mlx-community/gemma-2-2b-it-4bit"),
    adapter: .huggingFace(id: "your-org/your-adapter"),
    contextLength: 4096,
    displayName: "Fine-tuned Gemma",
    description: "Domain-specific fine-tuned model"
)
```

### マルチモデル切替

```swift
let switcher = ModelSwitcher(maxLoadedModels: 2)

let service = LLMLocalService(
    backend: MLXBackend(),
    modelManager: ModelManager(),
    modelSwitcher: switcher
)

// モデル A で生成
for try await token in service.generate(model: modelA, prompt: "...") {
    print(token, terminator: "")
}

// モデル B に自動切替（LRU で管理）
for try await token in service.generate(model: modelB, prompt: "...") {
    print(token, terminator: "")
}
```

## アーキテクチャ

4 層構造で関心の分離を実現しています：

```
Layer 0: LLMLocalClient      プロトコル + 共有型（外部依存なし）
         ├─ LLMLocalBackend protocol
         ├─ ModelSpec, ModelSource, AdapterSource
         ├─ GenerationConfig, GenerationStats
         └─ LLMLocalError

Layer 1: LLMLocalModels       モデル管理
         ├─ ModelManager（キャッシュメタデータ）
         ├─ BackgroundDownloader（レジューム対応）
         └─ AdapterManager（LoRA/QLoRA）

Layer 2: LLMLocalMLX          MLX 具象実装
         ├─ MLXBackend（actor）
         ├─ MemoryMonitor
         └─ GenerationConfig+MLX

Umbrella: LLMLocal            サービス + 再エクスポート
          ├─ LLMLocalService（ファサード）
          ├─ ModelSwitcher（LRU マルチモデル）
          └─ ModelPresets
```

## サンプルアプリ

`Examples/LLMLocalExample/` にフル機能のサンプル iOS アプリが含まれています：

- チャット UI（ストリーミング表示）
- モデル選択・ダウンロード管理
- 生成パラメータ設定
- メモリ情報表示

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。詳細は [LICENSE](LICENSE) ファイルをご覧ください。

## サポート

問題が発生した場合や機能リクエストがある場合は、[GitHub の Issue](https://github.com/no-problem-dev/swift-llm-local/issues) を作成してください。
