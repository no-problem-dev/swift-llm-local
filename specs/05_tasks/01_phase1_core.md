---
title: "Phase 1: Core Tasks"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../04_implementation_plan/01_phase_wave.md
  - ../03_design_spec/01_architecture.md
  - ../03_design_spec/02_mlx_backend.md
  - ../03_design_spec/03_model_manager.md
  - ../03_design_spec/04_package_manifest.md
  - ../02_requirements/01_functional_requirements.md
---

# Phase 1: Core（FF-01〜FF-05）

Phase 1 完了で `import LLMLocal` により HuggingFace 上の MLX モデルをストリーミング推論できる状態になる。

---

## Wave 1-1: Pre-verification + Package Foundation

### T1: Verify mlx-swift-lm API signatures

- description:
  - mlx-swift-lm パッケージの実 API を調査し、Design Spec の設計仮定を検証する
  - 検証対象: `ChatSession.streamResponse(to:)` の型シグネチャ、`GenerateParameters` のフィールド、iOS Sandbox での HuggingFace Hub キャッシュパス動作、プリセットモデル HuggingFace ID の実在確認
  - 完了時: 検証結果がドキュメント化され、Design Spec に差分があれば更新案が提示されている

- spec_refs:
  - FF-02（MLX バックエンド実装）
  - specs/03_design_spec/02_mlx_backend.md#MLX Swift LM の API マッピング
  - specs/03_design_spec/02_mlx_backend.md#MLXBackend 実装
  - specs/03_design_spec/02_mlx_backend.md#GenerationConfig → MLX パラメータ変換
  - specs/03_design_spec/04_package_manifest.md#注意事項
  - specs/02_requirements/01_functional_requirements.md#FR-02
  - specs/02_requirements/03_constraints.md#外部依存

- agent:
  - orchestrator-core:researcher

- deps:
  - none

- files:
  - create: specs/05_tasks/wave-1-1-api-verification-results.md

- verification:
  - [ ] `ChatSession.streamResponse(to:)` の正確な型シグネチャが記録されている
  - [ ] `GenerateParameters`（temperature, maxTokens）の指定方法が記録されている
  - [ ] mlx-swift-lm のパッケージ URL とプロダクト名（MLXLLM, MLXLMCommon）が確認されている
  - [ ] プリセットモデル HuggingFace ID（`mlx-community/gemma-2-2b-it-4bit` 等）の実在が確認されている
  - [ ] Design Spec との差分がある場合、更新案が記載されている

---

### T2: Initialize Package.swift and directory structure

- description:
  - Package.swift とディレクトリ構成を Design Spec に従って作成する
  - swift-tools-version: 6.2、platforms: iOS 18.0+, macOS 15.0+
  - T1 の検証結果に基づき mlx-swift-lm の依存バージョンを確定する（T1 と並列実行する場合は仮バージョンで作成し、T1 完了後に更新）
  - 完了時: `swift package resolve` が成功し、全ターゲットのディレクトリが存在する

- spec_refs:
  - specs/03_design_spec/04_package_manifest.md#Package.swift
  - specs/03_design_spec/01_architecture.md#パッケージ全体構成
  - specs/02_requirements/02_non_functional_requirements.md#NFR-03
  - specs/02_requirements/02_non_functional_requirements.md#NFR-04

- agent:
  - general-purpose

- deps:
  - none（T1 と並列可能。T1 の結果で依存バージョンを微調整する可能性あり）

- files:
  - create: Package.swift
  - create: Sources/LLMLocalClient/.gitkeep
  - create: Sources/LLMLocalModels/.gitkeep
  - create: Sources/LLMLocalMLX/.gitkeep
  - create: Sources/LLMLocal/.gitkeep
  - create: Tests/LLMLocalClientTests/.gitkeep
  - create: Tests/LLMLocalModelsTests/.gitkeep
  - create: Tests/LLMLocalMLXTests/.gitkeep

- verification:
  - [ ] `swift package resolve` が成功する
  - [ ] Package.swift の platforms が `.iOS(.v18), .macOS(.v15)` である
  - [ ] swift-tools-version が 6.2 である
  - [ ] 全ターゲットのディレクトリが存在する（Sources/LLMLocalClient, Sources/LLMLocalModels, Sources/LLMLocalMLX, Sources/LLMLocal, Tests/*）
  - [ ] 4 つのライブラリプロダクト（LLMLocal, LLMLocalClient, LLMLocalMLX）が定義されている

---

## Wave 1-2: LLMLocalClient Module（Protocol + 型定義）

### T3: Implement LLMLocalBackend protocol and core model types

- description:
  - LLMLocalClient モジュールの Protocol と モデル定義型を TDD で実装する
  - 対象: `LLMLocalBackend` protocol、`ModelSpec` struct、`ModelSource` enum、`AdapterSource` enum
  - 全型は `Sendable` 準拠。`ModelSpec` は `Hashable`, `Codable` 準拠
  - TDD: テストを先に書き、実装を後から書く
  - 完了時: LLMLocalBackend protocol が定義され、モデル型が Sendable/Codable/Hashable 準拠でテスト済み

- spec_refs:
  - FF-01（Protocol ベースの推論抽象化）
  - FF-03（HuggingFace モデルダウンロード・キャッシュ）
  - specs/03_design_spec/01_architecture.md#LLMLocalBackend
  - specs/03_design_spec/01_architecture.md#ModelSpec
  - specs/03_design_spec/01_architecture.md#ModelSource
  - specs/03_design_spec/01_architecture.md#AdapterSource
  - specs/02_requirements/01_functional_requirements.md#FR-01
  - specs/02_requirements/01_functional_requirements.md#FR-03
  - specs/02_requirements/02_non_functional_requirements.md#NFR-04
  - specs/04_implementation_plan/03_test_strategy.md#LLMLocalClientTests（Wave 1-2）

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T2（Package.swift とディレクトリ構成が必要）

- files:
  - create: Sources/LLMLocalClient/LLMLocalBackend.swift
  - create: Sources/LLMLocalClient/ModelSpec.swift
  - create: Sources/LLMLocalClient/ModelSource.swift
  - create: Sources/LLMLocalClient/AdapterSource.swift
  - create: Tests/LLMLocalClientTests/ModelSpecTests.swift
  - delete: Sources/LLMLocalClient/.gitkeep

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalClientTests/ModelSpecTests.swift
  - coverage_goal: 90%
  - red_phase: ModelSpec の Codable エンコード/デコード、Hashable 同一性判定、ModelSource の等値比較テストを作成（実装前に失敗させる）
  - green_phase: Protocol 定義と各型定義を最小限で実装しテストを通す

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（90%）
  - [ ] `swift build --target LLMLocalClient` が成功する
  - [ ] 全型が `Sendable` 準拠
  - [ ] `LLMLocalBackend` protocol に `loadModel`, `generate`, `unloadModel`, `isLoaded`, `currentModel` が定義されている

---

### T4: Implement GenerationConfig, GenerationStats, and LLMLocalError

- description:
  - LLMLocalClient モジュールの残りの型を TDD で実装する
  - 対象: `GenerationConfig` struct、`GenerationStats` struct、`LLMLocalError` enum
  - TDD: テストを先に書き、実装を後から書く
  - 完了時: 全型が定義され、LLMLocalClient モジュール全体がビルド・テスト成功

- spec_refs:
  - FF-01（Protocol ベースの推論抽象化）
  - FF-04（ストリーミング生成）
  - specs/03_design_spec/01_architecture.md#GenerationConfig
  - specs/03_design_spec/01_architecture.md#GenerationStats
  - specs/03_design_spec/01_architecture.md#エラー設計
  - specs/02_requirements/01_functional_requirements.md#FR-01-3
  - specs/02_requirements/01_functional_requirements.md#FR-05-2
  - specs/04_implementation_plan/03_test_strategy.md#LLMLocalClientTests（Wave 1-2）

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T2（Package.swift とディレクトリ構成が必要）

- files:
  - create: Sources/LLMLocalClient/GenerationConfig.swift
  - create: Sources/LLMLocalClient/GenerationStats.swift
  - create: Sources/LLMLocalClient/LLMLocalError.swift
  - create: Tests/LLMLocalClientTests/GenerationConfigTests.swift
  - create: Tests/LLMLocalClientTests/LLMLocalErrorTests.swift

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalClientTests/GenerationConfigTests.swift, Tests/LLMLocalClientTests/LLMLocalErrorTests.swift
  - coverage_goal: 90%
  - red_phase: GenerationConfig.default の値検証、GenerationStats のプロパティ検証、LLMLocalError の各ケース生成テストを作成
  - green_phase: 各型を最小限で実装しテストを通す

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（90%）
  - [ ] `swift build --target LLMLocalClient` が成功する
  - [ ] `swift test --filter LLMLocalClientTests` が成功する
  - [ ] `GenerationConfig.default` が仕様通りの値（maxTokens: 1024, temperature: 0.7, topP: 0.9）
  - [ ] `LLMLocalError` に全エラーケースが定義されている

---

## Wave 1-3: LLMLocalModels Module（モデル管理）

### T5: Implement ModelManager actor and cache types

- description:
  - LLMLocalModels モジュールの ModelManager actor と関連型を TDD で実装する
  - Phase 1 実装範囲: `cachedModels()`, `isCached()`, `totalCacheSize()`, `deleteCache()`, `clearAllCache()`
  - HuggingFace Hub キャッシュ（`~/Library/Caches/huggingface/hub/`）の状態監視
  - `CachedModelInfo` 型と内部ヘルパー `ModelCache`
  - TDD: 仮のキャッシュディレクトリ（`FileManager.default.temporaryDirectory`）を使ったテスト
  - 完了時: ModelManager が動作し、キャッシュの CRUD 操作がテスト済み

- spec_refs:
  - FF-03（HuggingFace モデルダウンロード・キャッシュ）
  - FF-05（モデルメタデータ管理）
  - specs/03_design_spec/03_model_manager.md#ModelManager
  - specs/03_design_spec/03_model_manager.md#CachedModelInfo
  - specs/03_design_spec/03_model_manager.md#キャッシュ戦略
  - specs/02_requirements/01_functional_requirements.md#FR-03
  - specs/02_requirements/01_functional_requirements.md#FR-04
  - specs/04_implementation_plan/03_test_strategy.md#LLMLocalModelsTests（Wave 1-3）

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T3, T4（LLMLocalClient の型定義に依存: ModelSpec, ModelSource, LLMLocalError）

- files:
  - create: Sources/LLMLocalModels/ModelManager.swift
  - create: Sources/LLMLocalModels/CachedModelInfo.swift
  - create: Sources/LLMLocalModels/ModelCache.swift
  - create: Tests/LLMLocalModelsTests/ModelManagerTests.swift
  - create: Tests/LLMLocalModelsTests/CachedModelInfoTests.swift
  - delete: Sources/LLMLocalModels/.gitkeep

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalModelsTests/ModelManagerTests.swift, Tests/LLMLocalModelsTests/CachedModelInfoTests.swift
  - coverage_goal: 80%
  - red_phase: isCached の true/false 判定、cachedModels の一覧取得、deleteCache のファイル削除、clearAllCache の全削除、totalCacheSize の計算、CachedModelInfo の Codable テストを作成
  - green_phase: ModelManager actor と CachedModelInfo を最小限で実装しテストを通す

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（80%）
  - [ ] `swift build --target LLMLocalModels` が成功する
  - [ ] `swift test --filter LLMLocalModelsTests` が成功する
  - [ ] ModelManager が actor として実装されている
  - [ ] テスト用の仮キャッシュディレクトリでテストが動作する

---

## Wave 1-4: LLMLocalMLX Module（MLX Backend）

### T6: Implement MLXBackend actor

- description:
  - LLMLocalMLX モジュールの MLXBackend actor を TDD で実装する
  - `LLMLocalBackend` Protocol に準拠
  - `loadModel`: HuggingFace ID 解決 → `MLXLLM.loadModel(id:)` → `ChatSession` 作成
  - `generate`: `ChatSession.streamResponse(to:)` → `AsyncThrowingStream` 変換
  - `unloadModel`: セッション破棄
  - 排他制御: ロード中の二重呼び出し防止（`LLMLocalError.loadInProgress`）
  - GPU キャッシュ設定（デフォルト 20MB）
  - GenerationConfig → MLX パラメータ変換（T1 の検証結果に基づく）
  - TDD: MockBackend を使った Protocol 準拠テスト（シミュレータ可）。MLX 実 API テストは Wave 1-6 で実施
  - 完了時: MLXBackend がコンパイルし、Mock テストが全パス

- spec_refs:
  - FF-02（MLX バックエンド実装）
  - FF-04（ストリーミング生成）
  - specs/03_design_spec/02_mlx_backend.md#MLXBackend 実装
  - specs/03_design_spec/02_mlx_backend.md#MLX Swift LM の API マッピング
  - specs/03_design_spec/02_mlx_backend.md#GenerationConfig → MLX パラメータ変換
  - specs/03_design_spec/02_mlx_backend.md#メモリ管理戦略
  - specs/02_requirements/01_functional_requirements.md#FR-02
  - specs/02_requirements/01_functional_requirements.md#FR-05
  - specs/02_requirements/03_constraints.md#C-02
  - specs/04_implementation_plan/03_test_strategy.md#LLMLocalMLXTests（Wave 1-4, 実機のみ）

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T1（mlx-swift-lm API 検証結果に基づく実装）
  - T3, T4（LLMLocalClient の Protocol と型定義に依存）

- files:
  - create: Sources/LLMLocalMLX/MLXBackend.swift
  - create: Sources/LLMLocalMLX/GenerationConfig+MLX.swift
  - create: Tests/LLMLocalMLXTests/MLXBackendTests.swift
  - delete: Sources/LLMLocalMLX/.gitkeep

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalMLXTests/MLXBackendTests.swift
  - coverage_goal: 70%
  - red_phase: MockBackend を使った Protocol 準拠テスト、排他制御（loadInProgress）テスト、GenerationConfig 変換テストを作成
  - green_phase: MLXBackend actor を実装しテストを通す。実 MLX API テストは Wave 1-6 で実施

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（70%）
  - [ ] `swift build --target LLMLocalMLX` が成功する
  - [ ] MLXBackend が `LLMLocalBackend` protocol に準拠している
  - [ ] 排他制御（loadInProgress）が実装されている
  - [ ] GPU キャッシュ設定がコンストラクタで設定されている

---

## Wave 1-5: LLMLocal Umbrella + LLMLocalService

### T7: Implement LLMLocal umbrella, LLMLocalService, and ModelPresets

- description:
  - LLMLocal アンブレラモジュールの再エクスポート、LLMLocalService actor、ModelPresets を TDD で実装する
  - 再エクスポート: `@_exported import LLMLocalClient`, `@_exported import LLMLocalModels`, `@_exported import LLMLocalMLX`
  - LLMLocalService: Backend + ModelManager を統合するファサード
    - `generate(model:prompt:config:)`: キャッシュ確認 → 未 DL ならロード → 推論
    - `isModelCached()`: ModelManager への委譲
    - `prefetch()`: 事前ダウンロード
    - `lastGenerationStats`: 直近の生成統計
  - ModelPresets: T1 で検証済みの HuggingFace ID を使用した推奨モデル定義
  - TDD: MockBackend + MockModelManager での LLMLocalService テスト
  - 完了時: `import LLMLocal` で全 public API にアクセスでき、Service のテストが全パス

- spec_refs:
  - FF-01〜FF-05（統合）
  - specs/03_design_spec/01_architecture.md#LLMLocalService
  - specs/03_design_spec/01_architecture.md#アプリ側の利用イメージ
  - specs/02_requirements/01_functional_requirements.md#FR-03-4
  - specs/02_requirements/01_functional_requirements.md#FR-05-2
  - specs/04_implementation_plan/03_test_strategy.md#LLMLocalService Tests（Wave 1-5, シミュレータ可）
  - specs/04_implementation_plan/03_test_strategy.md#テスト用 Mock 設計

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T3, T4（LLMLocalClient）
  - T5（LLMLocalModels）
  - T6（LLMLocalMLX）

- files:
  - create: Sources/LLMLocal/LLMLocal.swift
  - create: Sources/LLMLocal/LLMLocalService.swift
  - create: Sources/LLMLocal/ModelPresets.swift
  - create: Tests/LLMLocalClientTests/MockBackend.swift
  - create: Tests/LLMLocalClientTests/LLMLocalServiceTests.swift
  - delete: Sources/LLMLocal/.gitkeep

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalClientTests/LLMLocalServiceTests.swift
  - coverage_goal: 80%
  - red_phase: generate フロー（未キャッシュ → ロード → 推論）、generate cached、isModelCached 委譲、prefetch 動作、Task キャンセル伝播テストを作成
  - green_phase: LLMLocalService actor を実装しテストを通す

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（80%）
  - [ ] `swift build` が全ターゲットで成功する
  - [ ] `import LLMLocal` で LLMLocalBackend, ModelSpec, MLXBackend, ModelManager, LLMLocalService が利用可能
  - [ ] LLMLocalService の generate フロー（未キャッシュ → ロード → 推論）がテスト済み
  - [ ] ModelPresets に少なくとも 1 つのプリセットが定義されている

---

## Wave 1-6: Integration Tests

### T8: Implement Integration Tests

- description:
  - モジュール間の統合を検証する Integration Tests を実装する
  - 実機のみ（MLX は Metal 必須）。`#if !targetEnvironment(simulator)` で分岐
  - テストモデル: 軽量の MLX 量子化モデル（Gemma 2B 4bit 等、約 1.5GB）
  - テスト内容:
    - LLMLocalService → MLXBackend → モデルロード → ストリーミング生成のフルフロー
    - 不正モデル ID → `LLMLocalError.loadFailed`
    - 生成中の Task キャンセル → 正常終了
    - アンロードなしで連続生成
    - GenerationStats の値が妥当か（tokenCount > 0, tokensPerSecond > 0）
  - 完了時: 実機で統合テストが全パス

- spec_refs:
  - FF-01〜FF-05（横断）
  - specs/04_implementation_plan/03_test_strategy.md#Phase 1 Integration Tests（Wave 1-6）
  - specs/02_requirements/03_constraints.md#C-02
  - specs/04_implementation_plan/01_phase_wave.md#Wave 1-6

- agent:
  - orchestrator-core:qa-specialist

- deps:
  - T7（LLMLocal アンブレラ完了）

- files:
  - create: Tests/LLMLocalMLXTests/IntegrationTests.swift
  - modify: Tests/LLMLocalMLXTests/MLXBackendTests.swift

- unit_test:
  - required: false

- verification:
  - [ ] 実機で全 Integration Tests が通る
  - [ ] フルフロー（Service → Backend → モデルロード → 生成 → 統計取得）が動作する
  - [ ] エラーハンドリング（不正モデル ID → loadFailed）が正しく機能する
  - [ ] Task キャンセルが生成を中断し、正常に終了する
  - [ ] GenerationStats が妥当な値を返す

---

## Wave 1-7: E2E + Manual QA

### T9: Verify E2E scenarios and run Manual QA

- description:
  - 実使用シナリオでの動作確認とパフォーマンス計測を行う
  - E2E テスト:
    - `03_design_spec/01_architecture.md#アプリ側の利用イメージ` のコード例が実際に動作する
    - 初回ダウンロード → キャッシュ → 再ロードのフルサイクル
  - パフォーマンス計測:
    - トークン生成速度: 5 tok/s 以上（iPhone 16 Pro、7B Q4 モデル）
    - モデルロード時間: 30 秒以内（キャッシュ済みモデル）
    - アイドル時メモリ: 50MB 以内
  - Manual QA チェックリスト: 7 項目
  - 完了時: 全 QA チェックリストがパスし、v0.1.0 タグ作成可能な状態

- spec_refs:
  - FF-01〜FF-05（横断）
  - specs/04_implementation_plan/01_phase_wave.md#Wave 1-7
  - specs/04_implementation_plan/03_test_strategy.md#Phase 1 チェックリスト（Wave 1-7）
  - specs/04_implementation_plan/03_test_strategy.md#Phase 1 E2E テスト
  - specs/02_requirements/02_non_functional_requirements.md#NFR-01
  - specs/02_requirements/02_non_functional_requirements.md#NFR-02
  - specs/04_implementation_plan/05_rollout.md#v0.1.0（Phase 1 完了時）

- agent:
  - orchestrator-core:qa-specialist

- deps:
  - T8（Integration Tests 完了）

- files:
  - create: specs/05_tasks/wave-1-7-qa-results.md

- unit_test:
  - required: false

- verification:
  - [ ] モデル初回ダウンロード → 推論成功
  - [ ] キャッシュ済みモデルの再ロード → 推論成功（30 秒以内）
  - [ ] キャッシュ削除 → 再ダウンロード → 推論成功
  - [ ] 推論中のキャンセル → エラーなく終了
  - [ ] 不正なモデル ID → 適切なエラー
  - [ ] 日本語プロンプトでの推論 → 日本語テキストが生成される
  - [ ] メモリ使用量が NFR-02 の範囲内
  - [ ] トークン生成速度 5 tok/s 以上（iPhone 16 Pro、Gemma 2B で代替計測可）
  - [ ] Phase 1 完了 → v0.1.0 タグ作成可能

---

## Wave 競合チェック

### Wave 1-1

| Task | files.create | files.modify | 競合 |
|---|---|---|---|
| T1 | `specs/05_tasks/wave-1-1-api-verification-results.md` | - | - |
| T2 | `Package.swift`, `Sources/*/`, `Tests/*/` | - | **競合なし** → 並列実行可能 |

### Wave 1-2

| Task | files.create | files.modify | 競合 |
|---|---|---|---|
| T3 | `Sources/LLMLocalClient/LLMLocalBackend.swift`, `ModelSpec.swift`, `ModelSource.swift`, `AdapterSource.swift`, `Tests/.../ModelSpecTests.swift` | - | - |
| T4 | `Sources/LLMLocalClient/GenerationConfig.swift`, `GenerationStats.swift`, `LLMLocalError.swift`, `Tests/.../GenerationConfigTests.swift`, `LLMLocalErrorTests.swift` | - | **競合なし** → 並列実行可能 |

### Wave 1-3 / 1-4

| Task | files.create | files.modify | 競合 |
|---|---|---|---|
| T5 | `Sources/LLMLocalModels/*`, `Tests/LLMLocalModelsTests/*` | - | - |
| T6 | `Sources/LLMLocalMLX/*`, `Tests/LLMLocalMLXTests/*` | - | **競合なし**（異なるモジュール） → 並列実行可能 |
