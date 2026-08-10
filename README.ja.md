[English](README.md) | 日本語

# LLMLocal

iOS / macOS デバイス上でローカル LLM 推論を実現する Swift パッケージ

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018.0+%20%7C%20macOS%2015.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 特徴

- **オンデバイス推論** - クラウド API に依存しないプライバシー保護型 AI 機能
- **MLX バックエンド** - Apple Silicon 最適化された高速推論エンジン
- **エージェント統合** - `LocalAgentClient` が swift-llm-client の `AgentCapableClient` に準拠。クラウドプロバイダーと同じエージェントループでローカル LLM を使用可能
- **ツールコール** - ネイティブ function calling 対応。モデルごとの対応可否を `ModelProfile.toolCallSupport` で管理し、非対応モデルへのツール付きリクエストは明示的にエラー
- **モデル管理** - ダウンロード追跡・レジューム・ローカルキャッシュ
- **LoRA サポート** - GitHub Releases / HuggingFace / ローカルからアダプタ読み込み
- **メモリ監視** - デバイスメモリに応じた自動アンロード
- **マルチモデル切替** - LRU ベースの自動モデルスワッピング

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-local.git", .upToNextMajor(from: "3.0.0"))
]
```

### モジュール構成

用途に応じて必要なモジュールのみをインポートできる：

| モジュール | 用途 |
|-----------|------|
| `LLMLocal` | アンブレラ（全モジュール + LLMLocalService + LocalAgentClient） |
| `LLMLocalClient` | プロトコル層のみ（アプリ抽象化用） |
| `LLMLocalMLX` | MLX バックエンド（DI 設定用） |

## クイックスタート

```swift
import LLMLocal

// 1. サービスを作成
let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry(cacheDirectory: cacheDirectory)
)

// 2. プリセットモデルで生成（ストリーミング）
for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "SwiftUIでリストを作る方法を教えて"
) {
    print(token, terminator: "")
}
```

### 生成パラメータのカスタマイズ

```swift
// maxTokens: nil（デフォルト）はコンテキスト上限まで生成
let config = GenerationConfig(
    maxTokens: 512,
    temperature: 0.7,
    topP: 0.9
)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "創造的な短い物語を書いて",
    config: config
) {
    print(token, terminator: "")
}
```

### エージェントクライアントとして使用

```swift
import LLMLocal

let client = LocalAgentClient(service: service)

// swift-llm-client の AgentCapableClient として、
// クラウドプロバイダーと同じエージェントループに注入できる
let response = try await client.executeAgentStep(
    messages: [.user("東京の天気は？")],
    model: ModelPresets.qwen3_4B,
    systemPrompt: "あなたは親切なアシスタントです",
    tools: tools,
    toolChoice: .auto,
    responseSchema: nil,
    thinkingMode: .disabled,
    reasoningEffort: nil,
    maxTokens: nil,
    cachePolicy: .implicit
)
```

ツールコールの可否はモデル依存。`ModelProfile.toolCallSupport` が
`.unsupported` のモデル（DeepSeek R1 蒸留、Gemma 3 等）にツールを渡すと
`LLMLocalError.toolCallsUnsupported` がスローされる。

### LoRA アダプタの使用

```swift
let modelWithAdapter = ModelSpec(
    id: "qwen-with-lora",
    base: .huggingFace(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit"),
    adapter: .huggingFace(id: "your-org/your-adapter"),
    contextLength: 262_144,
    displayName: "Fine-tuned Qwen",
    description: "Domain-specific fine-tuned model",
    estimatedMemoryBytes: 2_400_000_000
)
```

### カスタムダウンローダー

mlx-swift-lm 3.x の `Downloader` / `TokenizerLoader` 注入に対応する。
デフォルトは Hugging Face Hub だが、S3 やアプリ内バンドル等の独自取得戦略を注入できる。

```swift
let backend = MLXBackend(
    downloader: myCustomDownloader,   // 省略時は Hugging Face Hub
    tokenizerLoader: nil              // 省略時は swift-transformers AutoTokenizer
)
```

## アーキテクチャ

4 層構造で関心の分離を実現する：

```
Layer 0: LLMLocalClient      プロトコル + 共有型
Layer 1: LLMLocalModels       モデル管理
Layer 2: LLMLocalMLX          MLX 具象実装
Umbrella: LLMLocal            サービス + エージェントアダプタ + 再エクスポート
```

## ドキュメント

詳細なガイドと API リファレンスは DocC ドキュメントを参照。

| ガイド | 内容 |
|-------|------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/) | 全パブリック API |

## 要件

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+
- Xcode 16.0+

## 依存関係

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 3.5.1) - LLM クライアント抽象化
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (3.x) - MLX 推論フレームワーク
- [swift-huggingface](https://github.com/huggingface/swift-huggingface) - Hugging Face Hub クライアント
- [swift-transformers](https://github.com/huggingface/swift-transformers) - トークナイザー

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照

## リンク

- [完全なドキュメント](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/)
- [Issue報告](https://github.com/no-problem-dev/swift-llm-local/issues)
- [ディスカッション](https://github.com/no-problem-dev/swift-llm-local/discussions)
- [リリースプロセス](RELEASE_PROCESS.md)
