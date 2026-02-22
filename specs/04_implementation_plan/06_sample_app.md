---
title: "Sample App Implementation Plan"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../03_design_spec/01_architecture.md
---

# Sample App Implementation Plan

## 概要

swift-llm-local の全機能をデモする iOS サンプルアプリ。noproblem エコシステム（DesignSystem, SwiftMarkdownView）との統合を示す。

## 配置

`Examples/LLMLocalExample/`

## アーキテクチャ

- 単一ターゲット + フォルダ分離（Domain / DI / State / Views）
- XcodeGen (`project.yml`) でプロジェクト管理
- iOS 18+, Swift 6.2, strict concurrency

## 依存パッケージ

| パッケージ | product |
|---|---|
| swift-llm-local | `LLMLocal` |
| DesignSystem | `DesignSystem` |
| swift-markdown-view | `SwiftMarkdownView`, `SwiftMarkdownViewHighlightJS` |

## 画面構成

| Tab | 画面 | デモする機能 |
|---|---|---|
| Chat | ChatView | ストリーミング生成、Markdown レンダリング、生成統計 |
| Models | ModelListView | モデル DL 進捗、キャッシュ管理、モデル選択 |
| Settings | SettingsView | GenerationConfig 調整、テーマ切り替え、メモリ情報 |

## 主要パターン

1. **DI**: `ServiceFactory` で `LLMLocalService` / `ModelManager` / `MemoryMonitor` を生成
2. **State**: `@Observable @MainActor` の `ChatState` / `ModelState` / `SettingsState`
3. **Streaming**: `AsyncThrowingStream<String, Error>` を `@MainActor` 上で消費し UI 更新
4. **Markdown**: `MarkdownView(streamingContent)` でトークン追加ごとに再レンダリング

## スコープ外（初版）

- LoRA アダプター管理 UI
- バックグラウンドダウンロード
- 複数モデル同時切り替え
