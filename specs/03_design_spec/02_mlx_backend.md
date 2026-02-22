---
title: "MLX Backend Design"
created: 2026-02-22
status: draft
references:
  - ./01_architecture.md
  - ../02_requirements/01_functional_requirements.md
---

# MLX Backend Design

## 概要

`LLMLocalMLX` モジュールは、mlx-swift-lm パッケージをラップして `LLMLocalBackend` プロトコルに準拠する具体実装を提供する。

## MLX Swift LM の API マッピング

### 利用する mlx-swift-lm API

| mlx-swift-lm API | 本パッケージでの用途 |
|---|---|
| `loadModel(id:)` | HuggingFace からのモデルロード |
| `ChatSession(model)` | 会話セッション管理 |
| `session.streamResponse(to:)` | ストリーミング生成 |
| `MLX.GPU.set(cacheLimit:)` | GPU メモリキャッシュ制御 |
| `ModelRegistry` | プリセットモデル参照 |

### MLXBackend 実装

```swift
// LLMLocalMLX モジュール

import MLXLLM
import MLXLMCommon
import LLMLocalClient

public actor MLXBackend: LLMLocalBackend {
    private var chatSession: ChatSession?
    private var loadedSpec: ModelSpec?

    /// GPU キャッシュサイズ（バイト）
    private let gpuCacheLimit: Int

    public init(gpuCacheLimit: Int = 20 * 1024 * 1024) {
        self.gpuCacheLimit = gpuCacheLimit
    }

    public func loadModel(_ spec: ModelSpec) async throws {
        // 既に同じモデルがロード済みなら何もしない
        if loadedSpec == spec { return }

        // 前のモデルをアンロード
        await unloadModel()

        // GPU キャッシュ設定
        MLX.GPU.set(cacheLimit: gpuCacheLimit)

        // HuggingFace ID を解決
        let hfID = switch spec.base {
        case .huggingFace(let id): id
        case .local(let path): path
        }

        // mlx-swift-lm でモデルロード
        let model = try await MLXLLM.loadModel(id: hfID)

        // LoRA アダプターがあれば合成（Phase 2）
        // if let adapter = spec.adapter { ... }

        chatSession = ChatSession(model)
        loadedSpec = spec
    }

    public func generate(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [chatSession] in
                guard let session = chatSession else {
                    continuation.finish(throwing: LLMLocalError.modelNotLoaded)
                    return
                }

                do {
                    for try await text in session.streamResponse(to: prompt) {
                        try Task.checkCancellation()
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMLocalError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func unloadModel() async {
        chatSession = nil
        loadedSpec = nil
    }

    public var isLoaded: Bool {
        chatSession != nil
    }

    public var currentModel: ModelSpec? {
        loadedSpec
    }
}
```

## GenerationConfig → MLX パラメータ変換

```swift
extension GenerationConfig {
    /// mlx-swift-lm の GenerateParameters に変換
    var mlxParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature
            // topP は mlx-swift-lm の対応状況に依存
        )
    }
}
```

## メモリ管理戦略

### GPU キャッシュ

```swift
// デフォルト: 20MB（mlx-swift-examples の推奨値）
MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
```

### モデルアンロードタイミング

1. **明示的アンロード**: `unloadModel()` 呼び出し時
2. **モデル切り替え時**: `loadModel()` で別モデルを指定した場合、自動で前モデルをアンロード
3. **メモリ警告時**: `ModelManager` からの通知に基づきアンロード（Phase 2）

## テスト戦略

### Unit Test（シミュレータ可）
- `LLMLocalBackend` の Mock を使ったテスト
- `ModelSpec`, `GenerationConfig` の型テスト

### Integration Test（実機のみ）
- 小さい MLX モデル（Gemma 2B 等）を使った実推論テスト
- `#if !targetEnvironment(simulator)` で分岐
