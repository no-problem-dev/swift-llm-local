---
title: "Reference Matrix"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../02_requirements/00_index.md
  - ../03_design_spec/00_index.md
---

# Reference Matrix（FF 単位）

## FF-01: Protocol ベースの推論抽象化

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-01` | 要件定義（loadModel, generate, unloadModel, isLoaded） |
| `03_design_spec/01_architecture.md` | `#LLMLocalBackend` | Protocol 定義（メソッドシグネチャ） |
| `03_design_spec/01_architecture.md` | `#GenerationConfig` | 生成パラメータ型 |
| `03_design_spec/01_architecture.md` | `#エラー設計` | LLMLocalError enum |
| `02_requirements/02_non_functional_requirements.md` | `#NFR-04` | Swift 6.2, Sendable 準拠 |

## FF-02: MLX バックエンド実装

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-02` | 要件定義（actor, 排他制御, GPU キャッシュ） |
| `03_design_spec/02_mlx_backend.md` | `#MLXBackend 実装` | actor 実装コード |
| `03_design_spec/02_mlx_backend.md` | `#MLX Swift LM の API マッピング` | mlx-swift-lm API 対応表 |
| `03_design_spec/02_mlx_backend.md` | `#GenerationConfig → MLX パラメータ変換` | パラメータ変換 |
| `03_design_spec/02_mlx_backend.md` | `#メモリ管理戦略` | GPU キャッシュ、アンロードタイミング |
| `02_requirements/03_constraints.md` | `#C-02` | iOS シミュレータ Metal 制約 |

## FF-03: HuggingFace モデルダウンロード・キャッシュ

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-03` | モデル定義要件（ModelSpec, ModelSource） |
| `02_requirements/01_functional_requirements.md` | `#FR-04` | ダウンロード・キャッシュ要件 |
| `03_design_spec/01_architecture.md` | `#ModelSpec` | 型定義 |
| `03_design_spec/01_architecture.md` | `#ModelSource` | 取得先 enum |
| `03_design_spec/03_model_manager.md` | `#ModelManager` | actor 定義 |
| `03_design_spec/03_model_manager.md` | `#CachedModelInfo` | キャッシュ情報型 |
| `03_design_spec/03_model_manager.md` | `#キャッシュ戦略` | ディレクトリ構成、HF Hub キャッシュ活用方針 |
| `02_requirements/03_constraints.md` | `#C-04` | モデルファイルサイズ制約 |

## FF-04: ストリーミング生成（AsyncThrowingStream）

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-05` | ストリーミング要件 |
| `03_design_spec/01_architecture.md` | `#LLMLocalBackend` | `generate` メソッドの戻り値型 |
| `03_design_spec/01_architecture.md` | `#GenerationStats` | 統計情報型 |
| `03_design_spec/02_mlx_backend.md` | `#MLXBackend 実装` | `generate` の実装（continuation パターン） |

## FF-05: モデルメタデータ管理

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-03-4` | プリセット定義（ModelPresets） |
| `03_design_spec/03_model_manager.md` | `#CachedModelInfo` | メタデータ型 |
| `03_design_spec/03_model_manager.md` | `#キャッシュ戦略` | registry.json によるインデックス管理 |

## FF-06: LoRA アダプター管理（Phase 2）

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-06` | アダプター管理要件 |
| `03_design_spec/01_architecture.md` | `#AdapterSource` | アダプターソース enum |
| `03_design_spec/03_model_manager.md` | `#アダプター管理（Phase 2）` | GitHub Releases DL 実装 |
| `02_requirements/00_index.md` | `#D-03` | アダプター配布方式の決定 |

## FF-07: メモリ監視・自動アンロード（Phase 2）

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-07` | メモリ管理要件 |
| `03_design_spec/02_mlx_backend.md` | `#メモリ管理戦略` | アンロードタイミング |
| `02_requirements/02_non_functional_requirements.md` | `#NFR-02` | メモリ目標値 |
| `02_requirements/03_constraints.md` | `#C-01` | iOS メモリ制限 |
| `02_requirements/03_constraints.md` | `#C-03` | バックグラウンド GPU 制約 |

## FF-08: ダウンロード進捗通知（Phase 2）

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-04-6` | 進捗通知要件 |
| `03_design_spec/03_model_manager.md` | `#DownloadProgress（Phase 2）` | 進捗型定義 |

## FF-09: バックグラウンドダウンロード（Phase 3）

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/01_functional_requirements.md` | `#FR-04-7` | レジューム対応要件 |
| `02_requirements/03_constraints.md` | `#C-03` | バックグラウンド制約 |

## FF-10: 複数モデル切り替え（Phase 3）

| 参照先 | 節 | 内容 |
|---|---|---|
| `02_requirements/00_index.md` | `#FF-10` | 機能定義 |
| `03_design_spec/02_mlx_backend.md` | `#メモリ管理戦略` | モデル切り替え時のアンロード |

---

## API 型定義参照

本パッケージの public API 型定義は全て Design Spec に記載済み。実装時は以下を参照する。

| 型 | 定義箇所 | モジュール |
|---|---|---|
| `LLMLocalBackend` | `03_design_spec/01_architecture.md#LLMLocalBackend` | LLMLocalClient |
| `LLMLocalService` | `03_design_spec/01_architecture.md#LLMLocalService` | LLMLocal |
| `ModelSpec` | `03_design_spec/01_architecture.md#ModelSpec` | LLMLocalClient |
| `ModelSource` | `03_design_spec/01_architecture.md#ModelSource` | LLMLocalClient |
| `AdapterSource` | `03_design_spec/01_architecture.md#AdapterSource` | LLMLocalClient |
| `GenerationConfig` | `03_design_spec/01_architecture.md#GenerationConfig` | LLMLocalClient |
| `GenerationStats` | `03_design_spec/01_architecture.md#GenerationStats` | LLMLocalClient |
| `LLMLocalError` | `03_design_spec/01_architecture.md#エラー設計` | LLMLocalClient |
| `MLXBackend` | `03_design_spec/02_mlx_backend.md#MLXBackend 実装` | LLMLocalMLX |
| `ModelManager` | `03_design_spec/03_model_manager.md#ModelManager` | LLMLocalModels |
| `CachedModelInfo` | `03_design_spec/03_model_manager.md#CachedModelInfo` | LLMLocalModels |
| `DownloadProgress` | `03_design_spec/03_model_manager.md#DownloadProgress（Phase 2）` | LLMLocalModels |
