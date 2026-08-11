[English](README.md) | 日本語

# LLMLocal

オープン LLM を iOS / macOS の端末上だけで動かす。Apple MLX 経由。API キーもネットワークもトークン課金も要らない。

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018.0+%20%7C%20macOS%2015.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 特徴

- **オンデバイス推論** — プロンプトも出力も端末から出ない
- **MLX バックエンド** — `mlx-swift-lm` による Apple Silicon 推論。GPU キャッシュに上限を設け、ターン間で KV キャッシュを再利用する
- **モデルプリセット** — Qwen・Gemma・Llama・Ministral・DeepSeek の仕様を用意。ロード前に端末のメモリと突き合わせられる見積もり値付き
- **エージェント統合** — `LocalAgentClient` が swift-llm-client の `AgentCapableClient` に準拠。クラウドプロバイダーと同じエージェントループにそのまま差し込める
- **ツールコール** — 対応可否はモデルごとに `ModelProfile.toolCallSupport` が持つ。非対応モデルにツールを渡すと、黙って劣化せずエラーになる
- **メモリ監視** — 逼迫時にモデルをアンロードする。iOS では放置した先にあるのがエラーではなくアプリの強制終了だから
- **マルチモデル切替** — 常駐は 1 モデル。2 つ目のモデルは 1 つ目に足されるのではなく置き換える
- **LoRA アダプター** — Hugging Face / GitHub Releases / ローカルファイルから読み込む

## クイックスタート

```swift
import LLMLocal

let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry(cacheDirectory: cacheDirectory)
)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "SwiftUI でリストを作る方法は？"
) {
    print(token, terminator: "")
}
```

そのモデルの初回呼び出しでは Hugging Face Hub から重みをダウンロードする。数 GB を利用者の
回線で落とすことになるので、初回は「リクエスト」ではなく「ダウンロード」として進捗を見せる。

```swift
// maxTokens: nil（デフォルト）はコンテキスト上限まで生成
let config = GenerationConfig(maxTokens: 512, temperature: 0.7, topP: 0.9)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "短い物語を書いて",
    config: config
) {
    print(token, terminator: "")
}
```

## ドキュメント

- [API リファレンス](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/) — モジュールごとの全パブリックシンボル
- [Getting Started](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/gettingstarted) — モデル選択・ツールコール・ダウンロード管理
- [Architecture](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/architecture) — 4 層構造と、どの層に依存すべきか

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-local.git", from: "4.0.0")
]
```

アプリは `LLMLocal` に依存する。ライブラリターゲットやテストは `LLMLocalClient` だけに依存し、
バックエンドは注入で受け取る（MLX 抜きでコンパイルできる）。

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "LLMLocal", package: "swift-llm-local"),
])
```

## 要件

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+
- Xcode 16.0+
- macOS は Apple Silicon。選んだモデルが載るだけの空きメモリがある端末

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照
