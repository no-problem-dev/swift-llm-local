# ``LLMLocalMLX``

Apple MLX フレームワークを使った Apple Silicon 向けローカル LLM 推論バックエンド実装。

## Overview

`LLMLocalMLX` は `LLMLocalBackend` プロトコルの具体実装モジュール。
`mlx-swift-lm` ライブラリをラップし、Hugging Face Hub からのモデルダウンロード、
GPU へのモデルロード、テキスト生成・ツールコール・プロンプトキャッシュ再利用を提供する。

通常はアンブレラの `LLMLocal` ターゲットを通じて利用するが、
バックエンドを DI で差し込む構成では `LLMLocalMLX` を直接インポートして
`MLXBackend` のインスタンスを生成する。

```swift
import LLMLocalMLX
import LLMLocalClient

// LoRA アダプターを持つバックエンドを構築して DI コンテナに登録
let backend = MLXBackend(
    gpuCacheLimit: 30 * 1024 * 1024,
    adapterResolver: myAdapterRegistry
)

// プロトコル経由で使用
let spec = ModelSpec(
    id: "qwen3-4b",
    base: .huggingFace(id: "mlx-community/Qwen3-4B-4bit"),
    contextLength: 32768,
    displayName: "Qwen3 4B",
    description: "バランス型オープンモデル",
    estimatedMemoryBytes: 2_400_000_000
)
try await backend.loadModel(spec)
```

`MLXBackend` は Swift の `actor` として実装されており、並行アクセスから内部状態を保護する。
`generateFromMessages` はターン間でプロンプトの KV キャッシュを再利用し、
長い会話でも毎回フルプロンプトを再処理するコストを避ける。

## Topics

### バックエンド実装

- ``MLXBackend``

### ダウンロード

- ``DestinationHubDownloader``

### ローカルモデル管理

- ``LocalModelInventory``

### メモリ監視

- ``MemoryProvider``
