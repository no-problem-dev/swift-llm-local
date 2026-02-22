---
title: "Design Spec Index"
created: 2026-02-22
status: draft
references:
  - ../02_requirements/00_index.md
---

# Design Spec Index

## Requirements → Design 対応表

| Requirement | Design Section | 設計方針 |
|---|---|---|
| FR-01: 推論バックエンド抽象化 | 01_architecture | LLMLocalBackend Protocol + Actor |
| FR-02: MLX バックエンド実装 | 02_mlx_backend | mlx-swift-lm ラッパー |
| FR-03: モデル定義・管理 | 01_architecture (型定義) | 型安全な ModelSpec + ModelPresets |
| FR-04: モデルダウンロード・キャッシュ | 03_model_manager | ModelManager actor |
| FR-05: ストリーミング生成 | 01_architecture, 02_mlx_backend | AsyncThrowingStream + GenerationStats |
| FR-06: LoRA アダプター管理（Phase 2） | 03_model_manager | AdapterSource + MLX マージ |
| FR-07: メモリ管理（Phase 2） | 02_mlx_backend | GPU キャッシュ + メモリ警告対応 |
| Package 構成 | 04_package_manifest | Package.swift + 依存管理 |

## 設計ドキュメント一覧

| ファイル | 内容 |
|---|---|
| 01_architecture.md | 全体構成、Protocol 設計、型定義、エラー設計 |
| 02_mlx_backend.md | MLX バックエンド実装、メモリ管理、テスト戦略 |
| 03_model_manager.md | モデル管理、キャッシュ、アダプター管理 |
| 04_package_manifest.md | Package.swift、依存バージョン管理 |

## 設計判断

| ID | 判断 | 選択肢 | 選択理由 |
|---|---|---|---|
| AD-01 | Protocol + Actor パターン | Protocol+Actor vs Class継承 vs Callback | Sendable 準拠、Swift Concurrency 親和性 |
| AD-02 | モジュール分割は 4 つ | 単一モジュール vs 4分割 | 依存最小化、テスタビリティ |
| AD-03 | HuggingFace Hub 統合は MLX 内蔵を活用 | 自前実装 vs MLX 内蔵 | 車輪の再発明を避ける |
| AD-04 | AsyncThrowingStream で統一 | AsyncThrowingStream vs AsyncSequence vs Callback | エラーハンドリング統合、キャンセル対応 |
| AD-05 | LLMLocalService は LLMLocal アンブレラに配置 | LLMLocalClient vs LLMLocal | ModelManager に依存するため Client 層に置けない |
| AD-06 | 命名は `LLMLocal-` 接頭辞で統一 | `LLMLocal-` vs `LocalLLM-` | パッケージ名 `swift-llm-local` との一貫性 |

## Phase 1 開始前の検証事項

| 項目 | 内容 | 影響する仕様 |
|---|---|---|
| mlx-swift-lm API 検証 | `ChatSession.streamResponse(to:)` の型シグネチャ確認 | FR-02, 02_mlx_backend |
| 生成パラメータ確認 | temperature, maxTokens の指定方法 | FR-01-3, GenerationConfig |
| iOS Sandbox 確認 | HuggingFace Hub のキャッシュが iOS で動作するか | FR-04, 03_model_manager |
| モデル ID 検証 | プリセットの HuggingFace ID が実在するか | FR-03-4, ModelPresets |
