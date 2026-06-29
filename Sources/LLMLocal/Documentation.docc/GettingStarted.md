# Getting Started

LLMLocal をプロジェクトに追加し、最初のオンデバイス LLM 推論を動かす。

## インストール

Package.swift の `dependencies` に追加する。

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/no-problem-dev/swift-llm-local.git",
        from: "2.2.6"
    )
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "LLMLocal", package: "swift-llm-local")
        ]
    )
]
```

## 基本的な使い方

### 1. サービスの構築

``LLMLocalService`` は推論バックエンドとモデルレジストリを束ねるファサード。
`MLXBackend` と `ModelRegistry` を渡して初期化する。

```swift
import LLMLocal

let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry()
)
```

メモリ警告時に自動アンロードするには `MemoryMonitor` を渡す。

```swift
let monitor = MemoryMonitor()
let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry(),
    memoryMonitor: monitor
)
await service.startMemoryMonitoring()
```

### 2. モデルの選択

``ModelPresets`` に主要なオープンモデルのプリセットが用意されている。
`estimatedMemoryBytes` でデバイスへの適合を確認できる。

```swift
// 軽量モデル（~350 MB）
let model = ModelPresets.qwen3_0_6B

// バランス型（~2.4 GB）
let model = ModelPresets.qwen3_4B

// 全プリセット一覧（メモリ昇順）
let all = ModelPresets.all
```

### 3. テキスト生成

``LLMLocalService/generate(model:prompt:config:)`` はモデルを自動ロードしてストリームを返す。
モデルがまだダウンロードされていない場合は自動的に Hugging Face Hub からダウンロードする。

```swift
let stream = await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "SwiftUI で非同期処理を行う方法を教えてください"
)

for try await token in stream {
    print(token, terminator: "")
}
```

生成パラメータを調整するには `GenerationConfig` を渡す。

```swift
let config = GenerationConfig(
    maxTokens: 512,
    temperature: 0.7,
    topP: 0.9
)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "短い詩を書いてください",
    config: config
) {
    print(token, terminator: "")
}
```

### 4. ツールコール

`generateFromMessages(model:messages:systemPrompt:config:tools:)` でエージェントループを構築できる。
ツールコール対応可否はモデルごとに `ModelProfile.toolCallSupport` で管理されている。

```swift
let tools: [ToolDefinition] = [weatherTool]

let stream = await service.generateFromMessages(
    model: ModelPresets.qwen3_4B,
    messages: [.user("東京の天気は？")],
    systemPrompt: "あなたは親切なアシスタントです",
    tools: tools
)

for try await output in stream {
    switch output {
    case .text(let text): print(text, terminator: "")
    case .toolCall(let call): try await executeTool(call)
    case .info(let stats): print("\n\(stats.tokensPerSecond) tok/s")
    }
}
```

### 5. ダウンロード済みモデルの管理

``LLMLocalService`` はディスクの実体を正として管理する。
インメモリのレジストリではなくファイルシステムを参照するため、アプリ再起動後も正確に判定できる。

```swift
// ダウンロード済み確認
if service.isDownloaded(ModelPresets.qwen3_4B) {
    // キャッシュから即座にロード可能
}

// ダウンロード済み一覧（実サイズ・DL時刻込み）
let downloaded = service.downloadedModels(among: ModelPresets.all)

// 容量解放
try await service.deleteDownload(ModelPresets.qwen3_4B)
```
