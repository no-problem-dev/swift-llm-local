---
title: "Phase 2: Enhanced Tasks"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../04_implementation_plan/01_phase_wave.md
  - ../03_design_spec/02_mlx_backend.md
  - ../03_design_spec/03_model_manager.md
  - ../02_requirements/01_functional_requirements.md
---

# Phase 2: Enhanced（FF-06〜FF-08）

Phase 2 完了で LoRA アダプター管理、メモリ監視、ダウンロード進捗通知が利用可能になる。

---

## Wave 2-1: DownloadProgress + Memory Management

### T10: Implement DownloadProgress stream

- description:
  - ModelManager に `downloadWithProgress()` メソッドを追加し、ダウンロード進捗を `AsyncThrowingStream<DownloadProgress, Error>` で通知する
  - `DownloadProgress` 型（fraction, completedBytes, totalBytes, currentFile）を実装
  - HuggingFace Hub のダウンロード API をラップして進捗情報を中継
  - TDD: Mock ダウンロードでの進捗通知テスト
  - 完了時: DownloadProgress ストリームが動作し、テスト済み

- spec_refs:
  - FF-08（ダウンロード進捗通知）
  - specs/03_design_spec/03_model_manager.md#DownloadProgress（Phase 2）
  - specs/02_requirements/01_functional_requirements.md#FR-04-6

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T5（ModelManager の基盤実装が必要）

- files:
  - create: Sources/LLMLocalModels/DownloadProgress.swift
  - modify: Sources/LLMLocalModels/ModelManager.swift
  - create: Tests/LLMLocalModelsTests/DownloadProgressTests.swift

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalModelsTests/DownloadProgressTests.swift
  - coverage_goal: 80%
  - red_phase: downloadWithProgress の進捗率遷移（0.0 → ... → 1.0）、キャンセル時の動作テストを作成
  - green_phase: DownloadProgress 型と downloadWithProgress メソッドを実装

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（80%）
  - [ ] `swift build --target LLMLocalModels` が成功する
  - [ ] DownloadProgress の fraction が 0.0 → 1.0 で遷移する
  - [ ] ダウンロードキャンセルが正常に動作する

---

### T11: Implement memory monitoring and auto-unload

- description:
  - メモリ監視機能を実装し、メモリ警告時にモデルを自動アンロードする
  - `os_proc_available_memory()` によるメモリ使用量監視
  - `didReceiveMemoryWarning` 通知に応じたモデルアンロード
  - デバイスメモリに応じたコンテキスト長自動設定（8GB → 2048, 12GB → 4096）
  - TDD: メモリ警告シミュレーションテスト
  - 完了時: メモリ警告時にモデルが安全にアンロードされる

- spec_refs:
  - FF-07（メモリ監視・自動アンロード）
  - specs/02_requirements/01_functional_requirements.md#FR-07
  - specs/03_design_spec/02_mlx_backend.md#メモリ管理戦略
  - specs/02_requirements/02_non_functional_requirements.md#NFR-02
  - specs/02_requirements/03_constraints.md#C-01
  - specs/02_requirements/03_constraints.md#C-03

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T6（MLXBackend の unloadModel が必要）
  - T7（LLMLocalService の統合が必要）

- files:
  - create: Sources/LLMLocalMLX/MemoryMonitor.swift
  - modify: Sources/LLMLocal/LLMLocalService.swift
  - create: Tests/LLMLocalMLXTests/MemoryMonitorTests.swift

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalMLXTests/MemoryMonitorTests.swift
  - coverage_goal: 80%
  - red_phase: メモリ警告時のアンロード動作、コンテキスト長自動設定のテストを作成
  - green_phase: MemoryMonitor を実装し、LLMLocalService に統合

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（80%）
  - [ ] `swift build` が成功する
  - [ ] メモリ警告発生時にモデルが安全にアンロードされる
  - [ ] デバイスメモリに応じたコンテキスト長が設定される

---

## Wave 2-2: LoRA Adapter Management

### T12: Implement AdapterManager

- description:
  - LoRA アダプターのダウンロード・バージョン管理を行う AdapterManager を TDD で実装する
  - GitHub Releases からのアダプターダウンロード
  - HuggingFace からのアダプターダウンロード
  - アダプターのバージョン管理（tag ベース）
  - ローカルアダプターのサポート
  - TDD: Mock ダウンロードでのテスト
  - 完了時: AdapterManager が全 AdapterSource ケースに対応し、テスト済み

- spec_refs:
  - FF-06（LoRA アダプター管理）
  - specs/03_design_spec/03_model_manager.md#アダプター管理（Phase 2）
  - specs/03_design_spec/01_architecture.md#AdapterSource
  - specs/02_requirements/01_functional_requirements.md#FR-06
  - specs/02_requirements/00_index.md#D-03

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T5（ModelManager の基盤実装が必要）
  - T3（AdapterSource 型定義に依存）

- files:
  - create: Sources/LLMLocalModels/AdapterManager.swift
  - create: Tests/LLMLocalModelsTests/AdapterManagerTests.swift

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalModelsTests/AdapterManagerTests.swift
  - coverage_goal: 80%
  - red_phase: GitHub Releases DL、HuggingFace DL、ローカルパス解決、バージョン管理テストを作成
  - green_phase: AdapterManager を実装しテストを通す

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（80%）
  - [ ] `swift build --target LLMLocalModels` が成功する
  - [ ] GitHub Releases からのアダプター DL ロジックが実装されている
  - [ ] AdapterSource の全ケース（gitHubRelease, huggingFace, local）に対応している

---

### T13: Extend MLXBackend for LoRA adapter merging

- description:
  - MLXBackend の `loadModel` を拡張し、LoRA アダプター付き ModelSpec での合成ロードに対応する
  - ベースモデル + アダプターの合成処理を mlx-swift-lm API で実装
  - ベースモデルとアダプターの互換性チェック
  - アダプターなしの ModelSpec との API 互換性を維持
  - TDD: Mock でのアダプター合成テスト
  - 完了時: アダプター付き ModelSpec で推論が可能な状態

- spec_refs:
  - FF-06（LoRA アダプター管理）
  - specs/02_requirements/01_functional_requirements.md#FR-06
  - specs/03_design_spec/02_mlx_backend.md#MLXBackend 実装

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T6（MLXBackend の基盤実装が必要）
  - T12（AdapterManager が必要）

- files:
  - modify: Sources/LLMLocalMLX/MLXBackend.swift
  - create: Tests/LLMLocalMLXTests/MLXBackendAdapterTests.swift

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalMLXTests/MLXBackendAdapterTests.swift
  - coverage_goal: 70%
  - red_phase: アダプター付き loadModel、互換性チェック、アダプターなしとの API 互換性テストを作成
  - green_phase: MLXBackend の loadModel を拡張しテストを通す

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（70%）
  - [ ] `swift build --target LLMLocalMLX` が成功する
  - [ ] アダプター付き ModelSpec で loadModel が動作する
  - [ ] アダプターなしの既存動作が壊れていない（リグレッションなし）

---

## Wave 2-3: Integration Tests (Phase 2)

### T14: Implement Phase 2 Integration Tests

- description:
  - Phase 2 の新機能について統合テストを実装する（実機のみ）
  - テスト内容:
    - DownloadProgress ストリームの実モデル DL での動作確認
    - メモリ警告シミュレーションでのアンロード動作
    - アダプター合成 + 推論の統合テスト
  - Phase 1 の全テストがリグレッションなく通ることを確認
  - 完了時: Phase 2 の統合テストが全パス

- spec_refs:
  - FF-06〜FF-08（横断）
  - specs/04_implementation_plan/03_test_strategy.md#Phase 2 Integration Tests（Wave 2-3）
  - specs/04_implementation_plan/01_phase_wave.md#Wave 2-3

- agent:
  - orchestrator-core:qa-specialist

- deps:
  - T10, T11, T12, T13（Phase 2 の全実装タスク完了）

- files:
  - create: Tests/LLMLocalMLXTests/Phase2IntegrationTests.swift

- unit_test:
  - required: false

- verification:
  - [ ] 実機で全 Phase 2 Integration Tests が通る
  - [ ] DownloadProgress の進捗率が 0.0 → 1.0 で遷移する
  - [ ] メモリ警告シミュレーションでモデルがアンロードされる
  - [ ] アダプター合成 + 推論が動作する
  - [ ] Phase 1 の全テストがリグレッションなく通る

---

## Wave 2-4: E2E + Manual QA (Phase 2)

### T15: Verify Phase 2 E2E and Manual QA

- description:
  - Phase 2 の Manual QA チェックリストを実行する
  - チェックリスト:
    - DownloadProgress の進捗率が 0.0 → 1.0 で遷移する
    - メモリ警告発生 → モデル自動アンロード → OOM kill なし
    - ベースモデル + アダプターで推論成功
    - 不正なアダプター URL → 適切なエラー
  - 完了時: 全 QA チェックリストがパスし、v0.2.0 タグ作成可能

- spec_refs:
  - FF-06〜FF-08（横断）
  - specs/04_implementation_plan/01_phase_wave.md#Wave 2-4
  - specs/04_implementation_plan/03_test_strategy.md#Phase 2 チェックリスト（Wave 2-4）
  - specs/04_implementation_plan/05_rollout.md#v0.2.0（Phase 2 完了時）

- agent:
  - orchestrator-core:qa-specialist

- deps:
  - T14（Phase 2 Integration Tests 完了）

- files:
  - create: specs/05_tasks/wave-2-4-qa-results.md

- unit_test:
  - required: false

- verification:
  - [ ] DownloadProgress の進捗率が 0.0 → 1.0 で遷移する
  - [ ] メモリ警告発生 → モデル自動アンロード → OOM kill なし
  - [ ] ベースモデル + アダプターで推論成功
  - [ ] 不正なアダプター URL → `LLMLocalError.adapterMergeFailed` が返る
  - [ ] Phase 2 完了 → v0.2.0 タグ作成可能

---

## Wave 競合チェック

### Wave 2-1 / 2-2

| Task | files.create | files.modify | 競合 |
|---|---|---|---|
| T10 | `Sources/LLMLocalModels/DownloadProgress.swift`, `Tests/.../DownloadProgressTests.swift` | `Sources/LLMLocalModels/ModelManager.swift` | T12 とは別ファイル |
| T11 | `Sources/LLMLocalMLX/MemoryMonitor.swift`, `Tests/.../MemoryMonitorTests.swift` | `Sources/LLMLocal/LLMLocalService.swift` | - |
| T12 | `Sources/LLMLocalModels/AdapterManager.swift`, `Tests/.../AdapterManagerTests.swift` | - | T10 とは別ファイル |
| T13 | `Tests/.../MLXBackendAdapterTests.swift` | `Sources/LLMLocalMLX/MLXBackend.swift` | - |

**競合分析**:
- T10 と T12: T10 は `ModelManager.swift` を modify、T12 は `AdapterManager.swift` を create → **競合なし** → 並列実行可能
- T11 と T13: T11 は `LLMLocalService.swift` を modify、T13 は `MLXBackend.swift` を modify → **競合なし** → 並列実行可能
- T10 と T11: T10 は `ModelManager.swift`、T11 は `LLMLocalService.swift` → **競合なし** → 並列実行可能
- T12 と T13: 独立ファイル → **競合なし** → 並列実行可能

結果: Wave 2-1 / 2-2 の 4 タスクは全て並列実行可能。
