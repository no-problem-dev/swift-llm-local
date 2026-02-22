---
title: "Test Strategy"
created: 2026-02-22
status: draft
references:
  - ./01_phase_wave.md
  - ../02_requirements/02_non_functional_requirements.md
  - ../02_requirements/03_constraints.md
  - ../03_design_spec/02_mlx_backend.md
---

# Test Strategy

## テスト階層

```
Phase 1:
├── Wave 1-2〜1-5: Unit Tests（TDD、各 Wave に同梱）
├── Wave 1-6: Integration Tests
└── Wave 1-7: E2E + Manual QA

Phase 2:
├── Wave 2-1〜2-2: Unit Tests（TDD、各 Wave に同梱）
├── Wave 2-3: Integration Tests
└── Wave 2-4: E2E + Manual QA

Phase 3:
├── Wave 3-1: Unit Tests（TDD）
└── Wave 3-2: Integration Tests + QA
```

## Unit Tests

### 方針
- TDD: テストを先に書き、実装を後から書く
- 各 Wave の実装と同梱（別 Wave に分離しない）
- シミュレータで実行可能なテストのみ
- カバレッジ目標: Protocol 層（LLMLocalClient）は 90% 以上、その他は 80% 以上

### テスト対象と実行環境

| テストターゲット | 実行環境 | 対象モジュール |
|---|---|---|
| LLMLocalClientTests | シミュレータ / CI 可 | LLMLocalClient |
| LLMLocalModelsTests | シミュレータ / CI 可 | LLMLocalModels |
| LLMLocalMLXTests | 実機のみ | LLMLocalMLX |

### LLMLocalClientTests（Wave 1-2）

| テストケース | 検証内容 |
|---|---|
| ModelSpec Codable | エンコード → デコードでデータが保持される |
| ModelSpec Hashable | 同一パラメータで同一ハッシュ |
| ModelSource equality | `.huggingFace(id:)` の等値比較 |
| GenerationConfig default | `.default` の値が仕様通り（maxTokens: 1024, temperature: 0.7, topP: 0.9） |
| LLMLocalError cases | 各エラーケースが生成可能 |

### LLMLocalModelsTests（Wave 1-3）

| テストケース | 検証内容 |
|---|---|
| ModelManager isCached | 仮キャッシュディレクトリで true/false 判定 |
| ModelManager cachedModels | 複数モデルの一覧取得 |
| ModelManager deleteCache | ファイル削除の確認 |
| ModelManager clearAllCache | 全ファイル削除の確認 |
| ModelManager totalCacheSize | サイズ計算の正確性 |
| CachedModelInfo Codable | エンコード/デコード |

### LLMLocalMLXTests（Wave 1-4, 実機のみ）

| テストケース | 検証内容 |
|---|---|
| MLXBackend loadModel | 軽量モデルのロード成功 |
| MLXBackend generate | ストリーミングトークン生成 |
| MLXBackend unloadModel | アンロード後 isLoaded == false |
| MLXBackend duplicate load | 同一モデル再ロードはスキップ |
| MLXBackend loadInProgress | 二重ロードで LLMLocalError.loadInProgress |

### LLMLocalService Tests（Wave 1-5, シミュレータ可）

MockBackend + MockModelManager を使用。

| テストケース | 検証内容 |
|---|---|
| generate flow | 未キャッシュ → ロード → 推論のフロー |
| generate cached | キャッシュ済み → 直接推論 |
| isModelCached | ModelManager への委譲 |
| prefetch | ダウンロード呼び出し |
| cancellation | Task キャンセルの伝播 |

---

## Integration Tests（Wave 1-6, 2-3, 3-2）

### 方針
- 実機のみ（MLX は Metal 必須）
- `#if !targetEnvironment(simulator)` で分岐
- CI では除外（`--skip-tests LLMLocalMLXTests` フラグ）
- テストモデル: 軽量の MLX 量子化モデル（Gemma 2B 4bit 等、約 1.5GB）

### Phase 1 Integration Tests（Wave 1-6）

| テストケース | 検証内容 |
|---|---|
| Full flow | LLMLocalService → MLXBackend → モデルロード → 生成 → 統計取得 |
| Error handling | 不正モデル ID → `LLMLocalError.loadFailed` |
| Cancellation | 生成中の Task キャンセル → 正常終了 |
| Re-generation | アンロードなしで連続生成 |

### Phase 2 Integration Tests（Wave 2-3）

| テストケース | 検証内容 |
|---|---|
| DownloadProgress | 実モデル DL 中の進捗率遷移 |
| Memory warning | メモリ警告シミュレーション → アンロード |
| Adapter merge | ベースモデル + アダプター合成 → 推論 |

---

## E2E Tests（Wave 1-7, 2-4, 3-2）

### 方針
- クリティカルパスの自動テスト
- 実モデルを使用（CI 除外）
- NFR のパフォーマンス基準を検証

### Phase 1 E2E テスト

| テストケース | NFR 基準 | 参照 |
|---|---|---|
| トークン生成速度 | 5 tok/s 以上 | `02_requirements/02_non_functional_requirements.md#NFR-01` |
| モデルロード時間 | 30 秒以内（キャッシュ済み） | `02_requirements/02_non_functional_requirements.md#NFR-01` |
| アイドル時メモリ | 50MB 以内 | `02_requirements/02_non_functional_requirements.md#NFR-02` |
| モデルロード後メモリ | モデルサイズ + 500MB 以内 | `02_requirements/02_non_functional_requirements.md#NFR-02` |

---

## Manual QA

### Phase 1 チェックリスト（Wave 1-7）

| # | 項目 | 期待結果 |
|---|---|---|
| 1 | モデル初回ダウンロード → 推論 | ストリーミング出力が表示される |
| 2 | キャッシュ済みモデルの再ロード → 推論 | 30 秒以内にロード完了 |
| 3 | キャッシュ削除 → 再ダウンロード → 推論 | 正常に再取得・推論 |
| 4 | 推論中のキャンセル | エラーなく終了、次の推論が可能 |
| 5 | 不正なモデル ID 指定 | `LLMLocalError.loadFailed` が返る |
| 6 | 日本語プロンプトでの推論 | 日本語テキストが生成される |
| 7 | メモリ使用量確認 | NFR-02 の範囲内 |

### Phase 2 チェックリスト（Wave 2-4）

| # | 項目 | 期待結果 |
|---|---|---|
| 1 | DL 進捗通知 | 0.0 → 1.0 で進捗率が遷移 |
| 2 | メモリ警告発生 | モデル自動アンロード、OOM kill なし |
| 3 | ベースモデル + アダプター推論 | アダプター適用済みの出力 |
| 4 | 不正アダプター URL | `LLMLocalError.adapterMergeFailed` |

---

## テスト用 Mock 設計

### MockBackend

```swift
// LLMLocalClientTests 内に配置
actor MockBackend: LLMLocalBackend {
    var loadModelCalled = false
    var generateCalled = false
    var unloadCalled = false
    var shouldThrow: LLMLocalError?
    var mockTokens: [String] = ["Hello", " ", "World"]

    private var _isLoaded = false
    private var _currentModel: ModelSpec?

    func loadModel(_ spec: ModelSpec) async throws {
        if let error = shouldThrow { throw error }
        loadModelCalled = true
        _isLoaded = true
        _currentModel = spec
    }

    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        generateCalled = true
        let tokens = mockTokens
        return AsyncThrowingStream { continuation in
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }

    func unloadModel() async {
        unloadCalled = true
        _isLoaded = false
        _currentModel = nil
    }

    var isLoaded: Bool { _isLoaded }
    var currentModel: ModelSpec? { _currentModel }
}
```

### MockModelManager

テスト用の ModelManager は仮のキャッシュディレクトリ（`FileManager.default.temporaryDirectory` 配下）を使い、テスト終了時にクリーンアップする。
