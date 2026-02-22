---
title: "Implementation Plan Index"
created: 2026-02-22
status: draft
references:
  - ../03_design_spec/00_index.md
  - ../02_requirements/00_index.md
---

# Implementation Plan Index

## 概要

swift-llm-local パッケージの実装計画書。Design Spec の設計を Phase/Wave 構造で実装可能な具体手順に分解する。

## ドキュメント一覧

| ファイル | 内容 |
|---|---|
| 01_phase_wave.md | Phase/Wave 構造定義 |
| 02_reference_matrix.md | FF 単位の参照マトリクス |
| 03_test_strategy.md | テスト戦略（Unit/Integration/E2E/Manual QA） |
| 04_development_rules.md | 開発ルール（ブランチ戦略、コーディング指針） |
| 05_rollout.md | ロールアウト・ロールバック手順 |
| 06_sample_app.md | サンプルアプリ（LLMLocalExample）実装計画 |
| 99_ai_instruction_template.md | AI 指示構成テンプレート + コンパクション条件 |

## Phase 概要

| Phase | スコープ | 成果物 | リリース |
|---|---|---|---|
| Phase 1 | Core（FF-01〜FF-05） | Protocol 層 + MLX Backend + Model Manager + Service | v0.1.0 |
| Phase 2 | Enhanced（FF-06〜FF-08） | LoRA アダプター + メモリ管理 + ダウンロード進捗 | v0.2.0 |
| Phase 3 | Nice-to-have（FF-09〜FF-10） | バックグラウンド DL + 複数モデル切り替え | v0.3.0 |

## 前提

- ソースコードは未作成（greenfield）
- mlx-swift-lm の API は Phase 1 Wave 1 で検証する
- iOS シミュレータでは MLX テスト不可（実機テスト必須）
