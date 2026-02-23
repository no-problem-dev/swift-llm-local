[English](README_EN.md) | 日本語

# LLMLocal

iOS / macOS デバイス上でローカル LLM 推論を実現する Swift パッケージ

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018.0+%20%7C%20macOS%2015.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 特徴

- **オンデバイス推論** - クラウド API に依存しないプライバシー保護型 AI 機能
- **MLX バックエンド** - Apple Silicon 最適化された高速推論エンジン
- **モデル管理** - ダウンロード追跡・レジューム・ローカルキャッシュ
- **LoRA サポート** - GitHub Releases / HuggingFace / ローカルからアダプタ読み込み
- **メモリ監視** - デバイスメモリに応じた自動アンロード
- **マルチモデル切替** - LRU ベースの自動モデルスワッピング

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-local.git", .upToNextMajor(from: "1.0.0"))
]
```

### モジュール構成

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

## アーキテクチャ

4 層構造で関心の分離を実現しています：

```
Layer 0: LLMLocalClient      プロトコル + 共有型（外部依存なし）
Layer 1: LLMLocalModels       モデル管理
Layer 2: LLMLocalMLX          MLX 具象実装
Umbrella: LLMLocal            サービス + 再エクスポート
```

## ドキュメント

詳細なガイドと API リファレンスは DocC ドキュメントを参照してください。

| ガイド | 内容 |
|-------|------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/) | 全パブリック API |

## 要件

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+
- Xcode 16.0+

## 依存関係

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 1.0.0) - LLM クライアント抽象化
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (>= 2.30.0) - MLX 推論フレームワーク

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照

## リンク

- [完全なドキュメント](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/)
- [Issue報告](https://github.com/no-problem-dev/swift-llm-local/issues)
- [ディスカッション](https://github.com/no-problem-dev/swift-llm-local/discussions)
- [リリースプロセス](RELEASE_PROCESS.md)
