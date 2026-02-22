---
title: "Phase 3: Nice-to-have Tasks"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../04_implementation_plan/01_phase_wave.md
  - ../02_requirements/01_functional_requirements.md
  - ../02_requirements/03_constraints.md
---

# Phase 3: Nice-to-have（FF-09〜FF-10）

Phase 3 完了でバックグラウンドダウンロードと複数モデル切り替えが利用可能になる。

---

## Wave 3-1: Background Download + Multi-model

### T16: Implement background download

- description:
  - URLSession background configuration を使ったモデルダウンロードを実装する
  - バックグラウンドでのダウンロード継続
  - ダウンロードのレジューム対応
  - アプリ再起動後のダウンロード復帰
  - TDD: Mock URLSession でのテスト
  - 完了時: バックグラウンドダウンロードが動作し、レジューム対応済み

- spec_refs:
  - FF-09（バックグラウンドダウンロード）
  - specs/02_requirements/01_functional_requirements.md#FR-04-7
  - specs/02_requirements/03_constraints.md#C-03

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T10（DownloadProgress の基盤が必要）

- files:
  - create: Sources/LLMLocalModels/BackgroundDownloader.swift
  - modify: Sources/LLMLocalModels/ModelManager.swift
  - create: Tests/LLMLocalModelsTests/BackgroundDownloaderTests.swift

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalModelsTests/BackgroundDownloaderTests.swift
  - coverage_goal: 80%
  - red_phase: バックグラウンド DL 開始・レジューム・完了通知のテストを作成
  - green_phase: BackgroundDownloader を実装しテストを通す

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（80%）
  - [ ] `swift build --target LLMLocalModels` が成功する
  - [ ] URLSession background configuration が正しく設定されている
  - [ ] ダウンロードのレジュームが動作する

---

### T17: Implement multi-model switching

- description:
  - 複数モデルの同時管理と切り替えを実装する
  - LRU キャッシュ的なアンロード戦略
  - モデル切り替え時のメモリ管理
  - 最大同時ロードモデル数の設定
  - TDD: Mock での切り替えテスト
  - 完了時: 複数モデルの切り替えが動作し、メモリ管理が適切

- spec_refs:
  - FF-10（複数モデル切り替え）
  - specs/02_requirements/00_index.md#FF-10
  - specs/03_design_spec/02_mlx_backend.md#メモリ管理戦略

- agent:
  - orchestrator-core:tdd-guide

- deps:
  - T11（メモリ管理の基盤が必要）
  - T7（LLMLocalService の基盤が必要）

- files:
  - create: Sources/LLMLocal/ModelSwitcher.swift
  - modify: Sources/LLMLocal/LLMLocalService.swift
  - create: Tests/LLMLocalClientTests/ModelSwitcherTests.swift

- unit_test:
  - required: true
  - test_file: Tests/LLMLocalClientTests/ModelSwitcherTests.swift
  - coverage_goal: 80%
  - red_phase: モデル切り替え、LRU アンロード、最大同時ロード制限テストを作成
  - green_phase: ModelSwitcher を実装しテストを通す

- verification:
  - [ ] Unit Test が通る
  - [ ] カバレッジ目標達成（80%）
  - [ ] `swift build` が成功する
  - [ ] 複数モデルの切り替えが正常に動作する
  - [ ] LRU アンロード戦略が実装されている
  - [ ] メモリ制限内でモデル切り替えが行われる

---

## Wave 3-2: Integration Tests + QA (Phase 3)

### T18: Verify Phase 3 Integration Tests and QA

- description:
  - Phase 3 の統合テストと QA を実施する
  - テスト内容:
    - バックグラウンド DL の中断/再開テスト（実機）
    - 複数モデル切り替えのメモリ管理テスト（実機）
  - Phase 1-2 の全テストがリグレッションなく通ることを確認
  - Manual QA チェックリスト
  - 完了時: 全テスト・QA パスし、v0.3.0 タグ作成可能

- spec_refs:
  - FF-09〜FF-10（横断）
  - specs/04_implementation_plan/01_phase_wave.md#Wave 3-2
  - specs/04_implementation_plan/05_rollout.md

- agent:
  - orchestrator-core:qa-specialist

- deps:
  - T16, T17（Phase 3 の全実装タスク完了）

- files:
  - create: Tests/LLMLocalMLXTests/Phase3IntegrationTests.swift
  - create: specs/05_tasks/wave-3-2-qa-results.md

- unit_test:
  - required: false

- verification:
  - [ ] バックグラウンド DL の中断/再開が正常に動作する
  - [ ] 複数モデル切り替えがメモリ制限内で動作する
  - [ ] Phase 1-2 の全テストがリグレッションなく通る
  - [ ] Phase 3 完了 → v0.3.0 タグ作成可能

---

## Wave 競合チェック

### Wave 3-1

| Task | files.create | files.modify | 競合 |
|---|---|---|---|
| T16 | `Sources/LLMLocalModels/BackgroundDownloader.swift`, `Tests/.../BackgroundDownloaderTests.swift` | `Sources/LLMLocalModels/ModelManager.swift` | - |
| T17 | `Sources/LLMLocal/ModelSwitcher.swift`, `Tests/.../ModelSwitcherTests.swift` | `Sources/LLMLocal/LLMLocalService.swift` | - |

**競合分析**: T16 と T17 は異なるモジュールのファイルを操作 → **競合なし** → 並列実行可能
