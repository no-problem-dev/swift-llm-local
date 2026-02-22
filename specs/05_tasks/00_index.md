---
title: "Task Specifications Index"
created: 2026-02-22
status: draft
references:
  - ../04_implementation_plan/00_index.md
  - ../04_implementation_plan/01_phase_wave.md
  - ../03_design_spec/00_index.md
  - ../02_requirements/00_index.md
---

# Task Specifications Index

## 概要

swift-llm-local パッケージの実装タスク仕様書。Implementation Plan の Phase/Wave 構造に基づき、実装可能な粒度のタスクに分解する。

## Phase/Wave/Task 構造

```
Phase 1: Core（FF-01〜FF-05）→ v0.1.0
  Wave 1-1: Pre-verification + Package Foundation
    T1: Verify mlx-swift-lm API signatures (並列)
    T2: Initialize Package.swift and directory structure (並列)
        ↓ [Wave完了 → /compact]
  Wave 1-2: LLMLocalClient Module（Protocol + 型定義）
    T3: Implement LLMLocalBackend protocol + core model types (並列)
    T4: Implement GenerationConfig, GenerationStats, LLMLocalError (並列)
        ↓ [Wave完了 → /compact]
  Wave 1-3 / 1-4: LLMLocalModels + LLMLocalMLX（並列実行）
    T5: Implement ModelManager actor + cache types (Wave 1-3)
    T6: Implement MLXBackend actor (Wave 1-4)
        ↓ [Wave完了 → /compact]
  Wave 1-5: LLMLocal Umbrella + LLMLocalService
    T7: Implement LLMLocal umbrella + LLMLocalService + ModelPresets
        ↓ [Wave完了 → /compact]
  Wave 1-6: Integration Tests
    T8: Implement Integration Tests
        ↓ [Wave完了 → /compact]
  Wave 1-7: E2E + Manual QA
    T9: Verify E2E scenarios and run Manual QA
        ↓ [Wave完了 → /compact → Phase 1 Done]

Phase 2: Enhanced（FF-06〜FF-08）→ v0.2.0
  Wave 2-1 / 2-2: DownloadProgress + Memory + LoRA（並列実行）
    T10: Implement DownloadProgress stream (Wave 2-1)
    T11: Implement memory monitoring and auto-unload (Wave 2-1)
    T12: Implement AdapterManager (Wave 2-2)
    T13: Extend MLXBackend for LoRA adapter merging (Wave 2-2)
        ↓ [Wave完了 → /compact]
  Wave 2-3: Integration Tests (Phase 2)
    T14: Implement Phase 2 Integration Tests
        ↓ [Wave完了 → /compact]
  Wave 2-4: E2E + Manual QA (Phase 2)
    T15: Verify Phase 2 E2E and Manual QA
        ↓ [Wave完了 → /compact → Phase 2 Done]

Phase 3: Nice-to-have（FF-09〜FF-10）→ v0.3.0
  Wave 3-1: Background Download + Multi-model
    T16: Implement background download
    T17: Implement multi-model switching
        ↓ [Wave完了 → /compact]
  Wave 3-2: Integration Tests + QA (Phase 3)
    T18: Verify Phase 3 Integration Tests and QA
        ↓ [Wave完了 → /compact → Phase 3 Done]
```

## タスク数サマリー

| Phase | Wave 数 | Task 数 | 概算工数 |
|---|---|---|---|
| Phase 1: Core | 7 | 9 (T1〜T9) | 22-30h |
| Phase 2: Enhanced | 4 | 6 (T10〜T15) | 16-22h |
| Phase 3: Nice-to-have | 2 | 3 (T16〜T18) | 8-12h |
| **合計** | **13** | **18** | **46-64h** |

## ドキュメント一覧

| ファイル | 内容 |
|---|---|
| 01_phase1_core.md | Phase 1 のタスク定義（T1〜T9） |
| 02_phase2_enhanced.md | Phase 2 のタスク定義（T10〜T15） |
| 03_phase3_nicetohave.md | Phase 3 のタスク定義（T16〜T18） |
| 99_dependencies.md | タスク依存関係（テキスト形式） |
| 99_dependency_graph.md | 依存関係の Mermaid 図 |
| 99_progress.md | 進捗管理・検討事項 |
| 99_references.md | 参照マトリクス（機能別 spec_refs 一覧） |

## 並列化サマリー

| Wave | 並列可能タスク | 備考 |
|---|---|---|
| Wave 1-1 | T1 ‖ T2 | API 検証と Package.swift 作成は独立 |
| Wave 1-2 | T3 ‖ T4 | Protocol/型 と Config/Error は異なるファイル |
| Wave 1-3 / 1-4 | T5 ‖ T6 | LLMLocalModels と LLMLocalMLX は独立モジュール |
| Wave 2-1 / 2-2 | T10 ‖ T11 ‖ T12 ‖ T13 | Wave 2-1 と 2-2 は独立。ただし T10, T11 は同一モジュールで要注意 |
| Wave 3-1 | T16 ‖ T17 | 異なる機能領域 |

## エージェントマッピング

プロジェクト固有のエージェント定義はなし。以下の組み込みエージェントタイプを使用する。

| エージェント | 用途 | 対象タスク |
|---|---|---|
| orchestrator-core:researcher | API 検証・調査 | T1 |
| general-purpose | パッケージ初期化、一般実装 | T2 |
| orchestrator-core:tdd-guide | TDD 実装（テストファースト） | T3〜T7, T10〜T13, T16, T17 |
| orchestrator-core:qa-specialist | テスト実装・QA | T8, T9, T14, T15, T18 |
