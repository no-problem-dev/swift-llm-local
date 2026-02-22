---
title: "Phase/Wave Structure"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../03_design_spec/01_architecture.md
  - ../03_design_spec/02_mlx_backend.md
  - ../03_design_spec/03_model_manager.md
  - ../03_design_spec/04_package_manifest.md
  - ../02_requirements/01_functional_requirements.md
---

# Phase/Wave Structure

## Phase 1: Core（Must）

Phase 1 完了で `import LLMLocal` により HuggingFace 上の MLX モデルをストリーミング推論できる状態になる。

### Wave 1-1: Pre-verification + Package Foundation

**目的**: mlx-swift-lm の実 API を検証し、Design Spec の設計仮定を確定する。同時に Package.swift とディレクトリ構成を作成する。

| 項目 | 内容 |
|---|---|
| 対象 FF | 全 FF の基盤 |
| 対象モジュール | なし（パッケージ骨格のみ） |
| 並列化 | API 検証と Package.swift 作成は並列可能 |
| 依存 | なし（Phase 1 の起点） |

**実施内容**:

1. **mlx-swift-lm API 検証**
   - `ChatSession.streamResponse(to:)` の型シグネチャ確認
   - `GenerateParameters`（temperature, maxTokens）の指定方法確認
   - iOS Sandbox での HuggingFace Hub キャッシュパス動作確認
   - プリセットモデル HuggingFace ID の実在確認（`mlx-community/gemma-2-2b-it-4bit` 等）
   - 検証結果に基づき Design Spec を必要に応じて更新

2. **Package.swift 作成**
   - `03_design_spec/04_package_manifest.md#Package.swift` の定義に準拠
   - `swift package resolve` で依存解決を確認
   - ディレクトリ構成（`Sources/`, `Tests/`）を `03_design_spec/01_architecture.md#パッケージ全体構成` に準拠して作成

**完了条件**:
- mlx-swift-lm の API シグネチャが確定し、Design Spec に反映されている
- `swift package resolve` が成功する
- ディレクトリ構成が Design Spec と一致する

---

### Wave 1-2: LLMLocalClient モジュール（Protocol + 型定義）

**目的**: 全モジュールの基盤となる Protocol と型を定義する。外部依存なし。

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-01（Protocol 抽象化）、FF-04（型定義の一部）、FF-05（GenerationStats） |
| 対象モジュール | LLMLocalClient |
| 並列化 | 各ファイル（Protocol、型、エラー）は並列作成可能 |
| 依存 | Wave 1-1（Package.swift 完了） |

**実施内容**:

1. **Protocol 定義**: `LLMLocalBackend` protocol
   - 参照: `03_design_spec/01_architecture.md#LLMLocalBackend`
   - `loadModel`, `generate`, `unloadModel`, `isLoaded`, `currentModel`

2. **型定義**:
   - `ModelSpec`: `03_design_spec/01_architecture.md#ModelSpec`
   - `ModelSource`: `03_design_spec/01_architecture.md#ModelSource`
   - `AdapterSource`: `03_design_spec/01_architecture.md#AdapterSource`（Phase 2 用の enum 定義のみ）
   - `GenerationConfig`: `03_design_spec/01_architecture.md#GenerationConfig`
   - `GenerationStats`: `03_design_spec/01_architecture.md#GenerationStats`

3. **エラー型**: `LLMLocalError`
   - 参照: `03_design_spec/01_architecture.md#エラー設計`

4. **Unit Tests（TDD）**:
   - `ModelSpec` の Codable エンコード/デコード
   - `ModelSpec` の Hashable（同一性判定）
   - `GenerationConfig.default` の値
   - `LLMLocalError` の各ケース生成

**完了条件**:
- LLMLocalClient モジュールが `swift build` でコンパイル成功
- 全型が `Sendable` 準拠
- Unit Tests が全パス

---

### Wave 1-3: LLMLocalModels モジュール（モデル管理）

**目的**: モデルのキャッシュ状態監視・管理を行う ModelManager を実装する。

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-03（モデル定義・管理）、FF-05（モデルメタデータ） |
| 対象モジュール | LLMLocalModels |
| 並列化 | Wave 1-2 と並列不可（LLMLocalClient に依存）。Wave 1-4 と並列可能 |
| 依存 | Wave 1-2（LLMLocalClient の型定義） |

**実施内容**:

1. **ModelManager actor**
   - 参照: `03_design_spec/03_model_manager.md#ModelManager`
   - Phase 1 実装範囲: `cachedModels()`, `isCached()`, `totalCacheSize()`, `deleteCache()`, `clearAllCache()`
   - HuggingFace Hub キャッシュ（`~/Library/Caches/huggingface/hub/`）の状態監視

2. **CachedModelInfo**
   - 参照: `03_design_spec/03_model_manager.md#CachedModelInfo`

3. **ModelCache**（内部ヘルパー）
   - HuggingFace Hub キャッシュディレクトリのスキャン
   - モデル ID からキャッシュパスへの解決

4. **Unit Tests（TDD）**:
   - 仮のキャッシュディレクトリでの `isCached` / `cachedModels` 動作
   - `deleteCache` でファイルが削除されること
   - `CachedModelInfo` の Codable

**完了条件**:
- LLMLocalModels モジュールが `swift build` でコンパイル成功
- ModelManager の各メソッドが Unit Test でカバー

---

### Wave 1-4: LLMLocalMLX モジュール（MLX Backend）

**目的**: mlx-swift-lm をラップして LLMLocalBackend に準拠する MLXBackend を実装する。

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-02（MLX バックエンド）、FF-04（ストリーミング生成） |
| 対象モジュール | LLMLocalMLX |
| 並列化 | Wave 1-3 と並列可能（互いに依存しない） |
| 依存 | Wave 1-1（API 検証結果）、Wave 1-2（LLMLocalClient Protocol） |

**実施内容**:

1. **MLXBackend actor**
   - 参照: `03_design_spec/02_mlx_backend.md#MLXBackend 実装`
   - `LLMLocalBackend` Protocol 準拠
   - `loadModel`: HuggingFace ID 解決 → `MLXLLM.loadModel(id:)` → `ChatSession` 作成
   - `generate`: `ChatSession.streamResponse(to:)` → `AsyncThrowingStream` 変換
   - `unloadModel`: セッション破棄
   - 排他制御: ロード中の二重呼び出し防止（`LLMLocalError.loadInProgress`）

2. **GenerationConfig 変換**
   - 参照: `03_design_spec/02_mlx_backend.md#GenerationConfig → MLX パラメータ変換`
   - Wave 1-1 の検証結果に基づいて `GenerateParameters` への変換を実装

3. **GPU キャッシュ設定**
   - `MLX.GPU.set(cacheLimit:)` をコンストラクタで設定
   - デフォルト: 20MB

4. **Unit Tests（TDD）**:
   - MockBackend を使った Protocol 準拠テスト（シミュレータ可）
   - 排他制御（loadInProgress）のテスト
   - GenerationConfig 変換のテスト

**完了条件**:
- LLMLocalMLX モジュールが `swift build` でコンパイル成功
- MockBackend による Unit Tests が全パス

---

### Wave 1-5: LLMLocal アンブレラ + LLMLocalService

**目的**: Backend + ModelManager を統合するファサード（LLMLocalService）と再エクスポートを実装する。

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-01〜FF-05 の統合 |
| 対象モジュール | LLMLocal |
| 並列化 | なし（全モジュールの統合） |
| 依存 | Wave 1-2, 1-3, 1-4 すべて完了 |

**実施内容**:

1. **LLMLocal.swift（再エクスポート）**
   - `@_exported import LLMLocalClient`
   - `@_exported import LLMLocalModels`
   - `@_exported import LLMLocalMLX`

2. **LLMLocalService actor**
   - 参照: `03_design_spec/01_architecture.md#LLMLocalService`
   - `generate(model:prompt:config:)`: キャッシュ確認 → 未 DL ならロード → 推論
   - `isModelCached()`: ModelManager への委譲
   - `prefetch()`: 事前ダウンロード
   - `lastGenerationStats`: 直近の生成統計

3. **ModelPresets**
   - 参照: `02_requirements/01_functional_requirements.md#FR-03-4`
   - Wave 1-1 で検証済みの HuggingFace ID を使用

4. **Unit Tests（TDD）**:
   - MockBackend + MockModelManager での LLMLocalService テスト
   - `generate` フロー（未キャッシュ → DL → ロード → 推論）
   - `prefetch` 動作
   - `lastGenerationStats` 取得

**完了条件**:
- `import LLMLocal` で全 public API にアクセスできる
- LLMLocalService の Unit Tests が全パス

---

### Wave 1-6: Integration Tests

**目的**: モジュール間の統合を検証する。

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-01〜FF-05 横断 |
| 対象モジュール | 全モジュール |
| 並列化 | なし（統合テスト） |
| 依存 | Wave 1-5 完了 |

**実施内容**:

1. **コンポーネント統合テスト**（実機のみ）
   - LLMLocalService → MLXBackend → モデルロード → ストリーミング生成のフルフロー
   - 軽量モデル（Gemma 2B 等）を使用
   - `#if !targetEnvironment(simulator)` で分岐

2. **データフロー検証**
   - ModelSpec → MLXBackend.loadModel → ChatSession 生成の正常系
   - 未ロード時の generate 呼び出し → `LLMLocalError.modelNotLoaded`
   - Task キャンセルによる生成中断
   - GenerationStats の値が妥当か（tokenCount > 0, tokensPerSecond > 0）

**完了条件**:
- 実機で軽量モデルのストリーミング推論が動作する
- エラーハンドリングが正しく機能する

---

### Wave 1-7: E2E + Manual QA

**目的**: 実使用シナリオでの動作確認とパフォーマンス計測。

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-01〜FF-05 横断 |
| 並列化 | なし |
| 依存 | Wave 1-6 完了 |

**実施内容**:

1. **E2E テスト**
   - `03_design_spec/01_architecture.md#アプリ側の利用イメージ` のコード例が実際に動作する
   - 初回ダウンロード → キャッシュ → 再ロードのフルサイクル

2. **パフォーマンス計測**
   - トークン生成速度: `02_requirements/02_non_functional_requirements.md#NFR-01` の 5 tok/s 以上
   - モデルロード時間: 30 秒以内（キャッシュ済み）
   - アイドル時メモリ: 50MB 以内

3. **Manual QA チェックリスト**
   - [ ] モデル初回ダウンロード → 推論成功
   - [ ] キャッシュ済みモデルの再ロード → 推論成功
   - [ ] キャッシュ削除 → 再ダウンロード → 推論成功
   - [ ] 推論中のキャンセル → エラーなく終了
   - [ ] 不正なモデル ID → 適切なエラー
   - [ ] メモリ使用量が NFR-02 の範囲内

**完了条件**:
- 全 Manual QA チェックリストがパス
- NFR のパフォーマンス基準を満たす
- Phase 1 完了 → v0.1.0 タグ作成可能

---

## Phase 2: Enhanced（Should）

Phase 2 完了で LoRA アダプター管理、メモリ監視、ダウンロード進捗通知が利用可能になる。

### Wave 2-1: DownloadProgress + Memory Management

**目的**: ダウンロード進捗通知とメモリ安全管理を実装する。

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-07（メモリ管理）、FF-08（ダウンロード進捗） |
| 対象モジュール | LLMLocalModels, LLMLocalMLX |
| 並列化 | DownloadProgress とメモリ管理は並列作成可能 |
| 依存 | Phase 1 完了 |

**実施内容**:

1. **DownloadProgress ストリーム**
   - `ModelManager.downloadWithProgress()` → `AsyncThrowingStream<DownloadProgress, Error>`
   - 参照: `03_design_spec/03_model_manager.md#DownloadProgress（Phase 2）`

2. **メモリ監視**
   - `os_proc_available_memory()` によるメモリ監視
   - `didReceiveMemoryWarning` 通知に応じたモデルアンロード
   - 参照: `02_requirements/01_functional_requirements.md#FR-07`

3. **コンテキスト長制限**
   - デバイスメモリに応じた自動設定（8GB → 2048, 12GB → 4096）
   - `ModelSpec.contextLength` のバリデーション

4. **Unit Tests（TDD）**

**完了条件**:
- DownloadProgress ストリームが動作する
- メモリ警告時にモデルが安全にアンロードされる

---

### Wave 2-2: LoRA Adapter Management

**目的**: ベースモデル + LoRA アダプターの合成ロードを実装する。

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-06（LoRA アダプター管理） |
| 対象モジュール | LLMLocalModels, LLMLocalMLX |
| 並列化 | Wave 2-1 と並列可能 |
| 依存 | Phase 1 完了 |

**実施内容**:

1. **AdapterManager**
   - GitHub Releases からのアダプターダウンロード
   - アダプターのバージョン管理（tag ベース）
   - 参照: `03_design_spec/03_model_manager.md#アダプター管理（Phase 2）`

2. **MLXBackend 拡張**
   - `loadModel` でアダプター付き `ModelSpec` を受け取った場合の合成処理
   - ベースモデル + アダプターの互換性チェック
   - 参照: `02_requirements/01_functional_requirements.md#FR-06`

3. **Unit Tests（TDD）**

**完了条件**:
- ベースモデル + アダプターの合成ロード → 推論が動作する
- GitHub Releases からのアダプター DL が動作する

---

### Wave 2-3: Integration Tests（Phase 2）

| 項目 | 内容 |
|---|---|
| 依存 | Wave 2-1, 2-2 完了 |

**実施内容**:
- DownloadProgress ストリームの実モデル DL での動作確認
- メモリ警告シミュレーションでのアンロード動作
- アダプター合成 + 推論の統合テスト（実機のみ）

---

### Wave 2-4: E2E + Manual QA（Phase 2）

| 項目 | 内容 |
|---|---|
| 依存 | Wave 2-3 完了 |

**Manual QA チェックリスト**:
- [ ] DownloadProgress の進捗率が 0.0 → 1.0 で遷移する
- [ ] メモリ警告発生 → モデル自動アンロード → OOM kill なし
- [ ] ベースモデル + アダプターで推論成功
- [ ] 不正なアダプター URL → 適切なエラー
- Phase 2 完了 → v0.2.0 タグ作成可能

---

## Phase 3: Nice-to-have（Could）

### Wave 3-1: Background Download + Multi-model

| 項目 | 内容 |
|---|---|
| 対象 FF | FF-09（バックグラウンド DL）、FF-10（複数モデル切り替え） |
| 依存 | Phase 2 完了 |

**実施内容**:
- URLSession background configuration でのダウンロード
- 複数モデルの同時管理（LRU キャッシュ的なアンロード戦略）
- Unit Tests（TDD）

---

### Wave 3-2: Integration Tests + QA（Phase 3）

| 項目 | 内容 |
|---|---|
| 依存 | Wave 3-1 完了 |

- バックグラウンド DL の中断/再開テスト
- 複数モデル切り替えのメモリ管理テスト
- Phase 3 完了 → v0.3.0 タグ作成可能

---

## Phase/Wave 依存関係図

```
Phase 1:
  Wave 1-1 ──→ Wave 1-2 ──┬──→ Wave 1-3 ──┐
                           │                │
                           └──→ Wave 1-4 ──┤
                                            ▼
                                      Wave 1-5 ──→ Wave 1-6 ──→ Wave 1-7
                                                                    │
Phase 2:                                                            ▼
  Wave 2-1 ──┐                                               (Phase 1 Done)
             ├──→ Wave 2-3 ──→ Wave 2-4
  Wave 2-2 ──┘                      │
                                     ▼
Phase 3:                       (Phase 2 Done)
  Wave 3-1 ──→ Wave 3-2
```

## 並列化サマリー

| Wave | 並列可能な作業 |
|---|---|
| Wave 1-1 | API 検証 ‖ Package.swift 作成 |
| Wave 1-2 | 各ファイル（Protocol, 型, エラー）の作成 |
| Wave 1-3 / 1-4 | LLMLocalModels ‖ LLMLocalMLX（互いに独立） |
| Wave 2-1 / 2-2 | DownloadProgress ‖ LoRA Adapter（互いに独立） |
