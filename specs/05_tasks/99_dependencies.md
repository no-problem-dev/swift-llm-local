---
title: "Task Dependencies"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ./01_phase1_core.md
  - ./02_phase2_enhanced.md
  - ./03_phase3_nicetohave.md
---

# Task Dependencies

## Phase 1: Core

### Wave 1-1
- **T1**: deps: none
- **T2**: deps: none
- T1 ‖ T2（並列実行可能）

### Wave 1-2
- **T3**: deps: T2
- **T4**: deps: T2
- T3 ‖ T4（並列実行可能、T2 完了後）

### Wave 1-3 / 1-4
- **T5**: deps: T3, T4（LLMLocalClient の型定義に依存）
- **T6**: deps: T1, T3, T4（API 検証結果 + LLMLocalClient に依存）
- T5 ‖ T6（並列実行可能、T3 + T4 完了後。T6 は追加で T1 も必要）

### Wave 1-5
- **T7**: deps: T3, T4, T5, T6（全モジュール完了）

### Wave 1-6
- **T8**: deps: T7

### Wave 1-7
- **T9**: deps: T8

---

## Phase 2: Enhanced

### Wave 2-1 / 2-2
- **T10**: deps: T5（ModelManager の基盤）
- **T11**: deps: T6, T7（MLXBackend + LLMLocalService）
- **T12**: deps: T3, T5（AdapterSource 型 + ModelManager）
- **T13**: deps: T6, T12（MLXBackend + AdapterManager）
- T10 ‖ T11 ‖ T12（並列実行可能）。T13 は T12 完了後。

### Wave 2-3
- **T14**: deps: T10, T11, T12, T13

### Wave 2-4
- **T15**: deps: T14

---

## Phase 3: Nice-to-have

### Wave 3-1
- **T16**: deps: T10（DownloadProgress の基盤）
- **T17**: deps: T7, T11（LLMLocalService + メモリ管理）
- T16 ‖ T17（並列実行可能）

### Wave 3-2
- **T18**: deps: T16, T17

---

## 依存関係サマリーテーブル

| Task | 直接依存 | Wave | Phase |
|---|---|---|---|
| T1 | - | 1-1 | 1 |
| T2 | - | 1-1 | 1 |
| T3 | T2 | 1-2 | 1 |
| T4 | T2 | 1-2 | 1 |
| T5 | T3, T4 | 1-3 | 1 |
| T6 | T1, T3, T4 | 1-4 | 1 |
| T7 | T3, T4, T5, T6 | 1-5 | 1 |
| T8 | T7 | 1-6 | 1 |
| T9 | T8 | 1-7 | 1 |
| T10 | T5 | 2-1 | 2 |
| T11 | T6, T7 | 2-1 | 2 |
| T12 | T3, T5 | 2-2 | 2 |
| T13 | T6, T12 | 2-2 | 2 |
| T14 | T10, T11, T12, T13 | 2-3 | 2 |
| T15 | T14 | 2-4 | 2 |
| T16 | T10 | 3-1 | 3 |
| T17 | T7, T11 | 3-1 | 3 |
| T18 | T16, T17 | 3-2 | 3 |

## 循環依存チェック

循環依存なし。全依存は下流 → 上流の一方向のみ。
