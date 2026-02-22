---
title: "Reference Matrix"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../04_implementation_plan/02_reference_matrix.md
---

# Reference Matrix（タスク別）

## Phase/Wave 単位の参照マトリクス

| 機能 | Requirements | Design Spec | Implementation Plan |
|---|---|---|---|
| Protocol 抽象化（FF-01） | 02_requirements/01_functional_requirements.md#FR-01 | 03_design_spec/01_architecture.md#LLMLocalBackend | 04_implementation_plan/01_phase_wave.md#Wave 1-2 |
| MLX Backend（FF-02） | 02_requirements/01_functional_requirements.md#FR-02 | 03_design_spec/02_mlx_backend.md | 04_implementation_plan/01_phase_wave.md#Wave 1-4 |
| モデル管理（FF-03） | 02_requirements/01_functional_requirements.md#FR-03 | 03_design_spec/01_architecture.md#ModelSpec | 04_implementation_plan/01_phase_wave.md#Wave 1-2, 1-3 |
| ストリーミング生成（FF-04） | 02_requirements/01_functional_requirements.md#FR-05 | 03_design_spec/01_architecture.md#GenerationStats | 04_implementation_plan/01_phase_wave.md#Wave 1-4 |
| メタデータ管理（FF-05） | 02_requirements/01_functional_requirements.md#FR-03-4 | 03_design_spec/03_model_manager.md#CachedModelInfo | 04_implementation_plan/01_phase_wave.md#Wave 1-3 |
| LoRA アダプター（FF-06） | 02_requirements/01_functional_requirements.md#FR-06 | 03_design_spec/03_model_manager.md#アダプター管理 | 04_implementation_plan/01_phase_wave.md#Wave 2-2 |
| メモリ管理（FF-07） | 02_requirements/01_functional_requirements.md#FR-07 | 03_design_spec/02_mlx_backend.md#メモリ管理戦略 | 04_implementation_plan/01_phase_wave.md#Wave 2-1 |
| DL 進捗通知（FF-08） | 02_requirements/01_functional_requirements.md#FR-04-6 | 03_design_spec/03_model_manager.md#DownloadProgress | 04_implementation_plan/01_phase_wave.md#Wave 2-1 |
| バックグラウンド DL（FF-09） | 02_requirements/01_functional_requirements.md#FR-04-7 | - | 04_implementation_plan/01_phase_wave.md#Wave 3-1 |
| 複数モデル切替（FF-10） | 02_requirements/00_index.md#FF-10 | 03_design_spec/02_mlx_backend.md#メモリ管理戦略 | 04_implementation_plan/01_phase_wave.md#Wave 3-1 |

---

## タスク別参照マトリクス

### Phase 1

| Task | Requirements | Design Spec | Test Strategy |
|---|---|---|---|
| T1 | FR-02, C-02, 外部依存 | 02_mlx_backend.md#API マッピング, 04_package_manifest.md#注意事項 | - |
| T2 | NFR-03, NFR-04 | 04_package_manifest.md#Package.swift, 01_architecture.md#パッケージ全体構成 | - |
| T3 | FR-01, FR-03 | 01_architecture.md#LLMLocalBackend, #ModelSpec, #ModelSource, #AdapterSource | 03_test_strategy.md#LLMLocalClientTests |
| T4 | FR-01-3, FR-05-2 | 01_architecture.md#GenerationConfig, #GenerationStats, #エラー設計 | 03_test_strategy.md#LLMLocalClientTests |
| T5 | FR-03, FR-04 | 03_model_manager.md#ModelManager, #CachedModelInfo, #キャッシュ戦略 | 03_test_strategy.md#LLMLocalModelsTests |
| T6 | FR-02, FR-05, C-02 | 02_mlx_backend.md#MLXBackend 実装, #GenerationConfig → MLX パラメータ変換, #メモリ管理戦略 | 03_test_strategy.md#LLMLocalMLXTests |
| T7 | FR-03-4, FR-05-2 | 01_architecture.md#LLMLocalService, #アプリ側の利用イメージ | 03_test_strategy.md#LLMLocalService Tests |
| T8 | FR-01〜FR-05 | - | 03_test_strategy.md#Phase 1 Integration Tests |
| T9 | NFR-01, NFR-02 | - | 03_test_strategy.md#Phase 1 チェックリスト |

### Phase 2

| Task | Requirements | Design Spec | Test Strategy |
|---|---|---|---|
| T10 | FR-04-6 | 03_model_manager.md#DownloadProgress | 03_test_strategy.md#Phase 2 Integration Tests |
| T11 | FR-07, NFR-02, C-01, C-03 | 02_mlx_backend.md#メモリ管理戦略 | 03_test_strategy.md#Phase 2 Integration Tests |
| T12 | FR-06, D-03 | 03_model_manager.md#アダプター管理, 01_architecture.md#AdapterSource | 03_test_strategy.md#Phase 2 Integration Tests |
| T13 | FR-06 | 02_mlx_backend.md#MLXBackend 実装 | 03_test_strategy.md#Phase 2 Integration Tests |
| T14 | FR-06〜FR-08 | - | 03_test_strategy.md#Phase 2 Integration Tests |
| T15 | - | - | 03_test_strategy.md#Phase 2 チェックリスト |

### Phase 3

| Task | Requirements | Design Spec | Test Strategy |
|---|---|---|---|
| T16 | FR-04-7, C-03 | - | - |
| T17 | FF-10 | 02_mlx_backend.md#メモリ管理戦略 | - |
| T18 | - | - | - |

---

## API 型定義参照（実装時クイックリファレンス）

| 型 | 定義箇所 | モジュール | 対象タスク |
|---|---|---|---|
| `LLMLocalBackend` | 03_design_spec/01_architecture.md#LLMLocalBackend | LLMLocalClient | T3 |
| `ModelSpec` | 03_design_spec/01_architecture.md#ModelSpec | LLMLocalClient | T3 |
| `ModelSource` | 03_design_spec/01_architecture.md#ModelSource | LLMLocalClient | T3 |
| `AdapterSource` | 03_design_spec/01_architecture.md#AdapterSource | LLMLocalClient | T3 |
| `GenerationConfig` | 03_design_spec/01_architecture.md#GenerationConfig | LLMLocalClient | T4 |
| `GenerationStats` | 03_design_spec/01_architecture.md#GenerationStats | LLMLocalClient | T4 |
| `LLMLocalError` | 03_design_spec/01_architecture.md#エラー設計 | LLMLocalClient | T4 |
| `MLXBackend` | 03_design_spec/02_mlx_backend.md#MLXBackend 実装 | LLMLocalMLX | T6 |
| `ModelManager` | 03_design_spec/03_model_manager.md#ModelManager | LLMLocalModels | T5 |
| `CachedModelInfo` | 03_design_spec/03_model_manager.md#CachedModelInfo | LLMLocalModels | T5 |
| `DownloadProgress` | 03_design_spec/03_model_manager.md#DownloadProgress | LLMLocalModels | T10 |
| `LLMLocalService` | 03_design_spec/01_architecture.md#LLMLocalService | LLMLocal | T7 |
