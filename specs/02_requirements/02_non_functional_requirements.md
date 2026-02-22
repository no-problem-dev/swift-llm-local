---
title: "Non-Functional Requirements"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
---

# Non-Functional Requirements

## NFR-01: パフォーマンス

| 指標 | 目標値 | 備考 |
|---|---|---|
| トークン生成速度 | 5 tok/s 以上 | iPhone 16 Pro、7B Q4 モデル |
| モデルロード時間 | 30 秒以内 | キャッシュ済みモデル |
| 初回ダウンロード | プログレス表示 | 4GB+ のため時間は回線依存 |

## NFR-02: メモリ

| 指標 | 目標値 | 備考 |
|---|---|---|
| モデルロード後の追加メモリ | モデルサイズ + 500MB 以内 | KV キャッシュ含む |
| アイドル時のメモリ | 50MB 以内 | モデルアンロード済み |

## NFR-03: 対応プラットフォーム

| プラットフォーム | バージョン | 備考 |
|---|---|---|
| iOS | 18.0+ | MLX Swift の要件 |
| macOS | 15.0+ | 開発・テスト用 |

## NFR-04: Swift バージョン

- Swift Tools Version: 6.2
- Swift Concurrency 完全準拠（Sendable, actor isolation）

## NFR-05: テスト

| 種類 | 要件 |
|---|---|
| Unit Test | Protocol 層は Mock でテスト可能 |
| Integration Test | 実モデルを使ったテスト（CI では除外可） |

## NFR-06: ドキュメント

- DocC 対応（swift-docc-plugin 統合）
- 主要 API に doc comment 付与

## NFR-07: 依存最小化

- LLMLocalClient モジュールは外部依存ゼロ
- MLX 依存は LLMLocalMLX モジュールに閉じる
