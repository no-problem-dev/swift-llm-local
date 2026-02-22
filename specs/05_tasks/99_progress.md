---
title: "Progress Tracking"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
---

# Progress Tracking

## Phase 1: Core（v0.1.0）

| Task | Wave | Status | Owner | Notes |
|---|---|---|---|---|
| T1: Verify mlx-swift-lm API | 1-1 | ✅ done | claude | swallow model ID invalid, others verified |
| T2: Initialize Package.swift | 1-1 | ✅ done | claude | resolved mlx-swift-lm 0.12.1 |
| T3: Protocol + model types | 1-2 | ✅ done | claude | LLMLocalBackend, ModelSpec, ModelSource, AdapterSource + 36 tests |
| T4: Config + Stats + Error | 1-2 | ✅ done | claude | GenerationConfig, GenerationStats, LLMLocalError + 33 tests |
| T5: ModelManager + cache | 1-3 | pending | - | blocked by T3, T4 |
| T6: MLXBackend | 1-4 | pending | - | blocked by T1, T3, T4 |
| T7: Umbrella + Service + Presets | 1-5 | pending | - | blocked by T5, T6 |
| T8: Integration Tests | 1-6 | pending | - | blocked by T7 |
| T9: E2E + Manual QA | 1-7 | pending | - | blocked by T8 |

## Phase 2: Enhanced（v0.2.0）

| Task | Wave | Status | Owner | Notes |
|---|---|---|---|---|
| T10: DownloadProgress | 2-1 | pending | - | blocked by T5 |
| T11: Memory monitoring | 2-1 | pending | - | blocked by T6, T7 |
| T12: AdapterManager | 2-2 | pending | - | blocked by T3, T5 |
| T13: LoRA merge | 2-2 | pending | - | blocked by T6, T12 |
| T14: Phase 2 Integration Tests | 2-3 | pending | - | blocked by T10-T13 |
| T15: Phase 2 E2E + QA | 2-4 | pending | - | blocked by T14 |

## Phase 3: Nice-to-have（v0.3.0）

| Task | Wave | Status | Owner | Notes |
|---|---|---|---|---|
| T16: Background download | 3-1 | pending | - | blocked by T10 |
| T17: Multi-model switching | 3-1 | pending | - | blocked by T7, T11 |
| T18: Phase 3 Integration + QA | 3-2 | pending | - | blocked by T16, T17 |

---

## 検討事項

| # | 項目 | 関連タスク | 優先度 | 状態 |
|---|---|---|---|---|
| 1 | mlx-swift-lm のパッケージ URL・プロダクト名の確定 | T1, T2 | 高 | ✅ 確認済み（URL, MLXLLM, MLXLMCommon） |
| 2 | GenerateParameters の正確なフィールド確認 | T1, T6 | 高 | ✅ 確認済み（temperature, maxTokens, topP, repetitionPenalty） |
| 3 | iOS Sandbox での HuggingFace Hub キャッシュ動作確認 | T1, T5 | 高 | ✅ 確認済み（Documents or Application Support） |
| 4 | プリセットモデル HuggingFace ID の実在確認 | T1, T7 | 中 | ⚠️ gemma OK, swallow-7b-instruct-4bit は存在しない |
| 5 | CI 設定（GitHub Actions）の検討 | - | 低 | 将来対応 |
| 6 | DocC ホスティングの検討 | - | 低 | 将来対応 |

---

## マイルストーン

| マイルストーン | 条件 | 状態 |
|---|---|---|
| Wave 1-1 完了 | T1, T2 完了 | ✅ done |
| Wave 1-2 完了 | T3, T4 完了 | ✅ done |
| Wave 1-3/1-4 完了 | T5, T6 完了 | pending |
| Wave 1-5 完了 | T7 完了 | pending |
| Wave 1-6 完了 | T8 完了 | pending |
| **Phase 1 完了（v0.1.0）** | T9 完了 | pending |
| Wave 2-1/2-2 完了 | T10-T13 完了 | pending |
| Wave 2-3 完了 | T14 完了 | pending |
| **Phase 2 完了（v0.2.0）** | T15 完了 | pending |
| Wave 3-1 完了 | T16, T17 完了 | pending |
| **Phase 3 完了（v0.3.0）** | T18 完了 | pending |
