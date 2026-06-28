# ``LLMLocalClient``

ローカル LLM バックエンドの抽象化プロトコルと、全モジュールで共有される型定義を提供するプロトコル層。

## Overview

`LLMLocalClient` はパッケージのプロトコル・共有型モジュールです。
バックエンド実装（`LLMLocalMLX`）と上位のアンブレラ（`LLMLocal`）の両方が依存する、
パッケージ内の最も下位に位置するライブラリターゲットです。

このモジュールだけをインポートすることで、バックエンドの具体的な実装に依存せず
抽象化された `LLMLocalBackend` プロトコルに対してコードを書けます。
テスト用のモックバックエンドを注入したい場合や、
SPM マルチモジュール構成で依存グラフを最小化したい場合に有効です。

```swift
import LLMLocalClient

// プロトコルに対してコードを書く
func configure(backend: any LLMLocalBackend) async throws {
    let spec = ModelSpec(
        id: "my-model",
        base: .huggingFace(id: "org/my-model"),
        contextLength: 8192,
        displayName: "My Model",
        description: "カスタムモデル",
        estimatedMemoryBytes: 2_000_000_000
    )
    try await backend.loadModel(spec)
}
```

このモジュールは `LLMClient` と `LLMTool`（`swift-llm-client` パッケージ）を
`@_exported import` で再エクスポートしています。
`LLMLocalClient` をインポートするだけで `ToolDefinition`・`LLMMessage` などの型も使えます。

## Topics

### バックエンドプロトコル

- ``LLMLocalBackend``
- ``AdapterResolving``

### モデル定義

- ``ModelSpec``
- ``ModelSource``
- ``AdapterSource``

### 生成設定と統計

- ``GenerationConfig``
- ``GenerationStats``

### ダウンロード管理

- ``DownloadProgress``
- ``DownloadedModel``
- ``ModelSizeTier``

### エラー

- ``LLMLocalError``
