# ``LLMLocal``

iOS / macOS デバイス上でローカル LLM 推論を実現する Swift パッケージ。

## Overview

`LLMLocal` は Apple Silicon デバイス向けのオンデバイス LLM 推論ライブラリです。
クラウド API に依存せず、プライバシーを守りながら LLM をアプリに組み込めます。

ライブラリは 4 層のアーキテクチャで構成されています。

```
LLMLocalClient   プロトコル + 共有型（LLMLocalBackend, ModelSpec, GenerationConfig …）
LLMLocalModels   モデル管理（ModelRegistry, BackgroundDownloader …）
LLMLocalMLX      MLX 推論バックエンド（MLXBackend）
LLMLocal         アンブレラ（LLMLocalService, ModelPresets, LocalAgentClient）
```

アプリは通常、アンブレラの `LLMLocal` を 1 つインポートするだけで全機能を使えます。
抽象化層のみが必要な場合は `LLMLocalClient`、バックエンドの DI 設定には `LLMLocalMLX` だけをインポートすることもできます。

### 基本的な使い方

```swift
import LLMLocal

// サービスを作成
let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry()
)

// プリセットモデルでテキストを生成（ストリーミング）
for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "SwiftUI でリストを作る方法は？"
) {
    print(token, terminator: "")
}
```

詳しいセットアップ手順は <doc:GettingStarted> を参照してください。

## Topics

### Essentials

- <doc:GettingStarted>

### サービス

- ``LLMLocalService``

### モデルプリセット

- ``ModelPresets``
- ``ModelSwitcher``

### エージェント統合

- ``LocalAgentClient``
