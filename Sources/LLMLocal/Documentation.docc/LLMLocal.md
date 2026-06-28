# ``LLMLocal``

Apple Silicon デバイス上でオンデバイス LLM 推論を実現する Swift パッケージ全体のエントリポイント。

## Overview

`swift-llm-local` は iOS / macOS 向けのオンデバイス LLM 推論パッケージです。
クラウド API に依存せず、プライバシーを守りながら LLM をアプリに組み込めます。
Qwen3・Llama などの主要オープンモデルを Apple MLX フレームワーク経由で動かします。

パッケージは次の 3 つの公開ライブラリターゲットで構成されています。

- **LLMLocal**（このモジュール）: ``LLMLocalService``・``ModelPresets``・``LocalAgentClient`` を含むアンブレラ。アプリ開発のほとんどのケースはこれ 1 つをインポートするだけで完結します。
- **LLMLocalClient**: `LLMLocalBackend` プロトコル・`ModelSpec`・`GenerationConfig` などのプロトコル層と共有型。バックエンドを切り替えたい場合や、ライブラリコード（テスト含む）でバックエンドに依存させたくない場合に単体でインポートします。
- **LLMLocalMLX**: `MLXBackend` の実装モジュール。バックエンドを DI で差し込む設定箇所や、アダプター（LoRA）管理が必要な箇所でインポートします。

### 基本的な使い方

```swift
import LLMLocal

// サービスを作成（MLXBackend は LLMLocal が内包）
let service = LLMLocalService()

// プリセットモデルでテキストを生成（ストリーミング）
for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "SwiftUI でリストを作る方法は？"
) {
    print(token, terminator: "")
}
```

依存を最小化したいライブラリターゲットでは `LLMLocalClient` のみをインポートし、
DI コンテナで `MLXBackend`（`LLMLocalMLX`）を注入するパターンを使います。

詳しいセットアップ手順は <doc:GettingStarted> を参照してください。

## Topics

### Essentials

- <doc:GettingStarted>

### モジュール構成

- ``LLMLocalClient``
- ``LLMLocalMLX``

### サービス

- ``LLMLocalService``

### モデルプリセット

- ``ModelPresets``
- ``ModelSwitcher``

### エージェント統合

- ``LocalAgentClient``
