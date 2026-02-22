---
title: "swift-llm-local Requirements Index"
created: 2026-02-22
status: draft
references:
  - ../01_request/01_request.md
---

# Requirements Index

## モジュール責務分離表

| モジュール | 責務 | 外部依存 |
|---|---|---|
| **LLMLocalClient** | Protocol 定義、共通型、GenerationConfig | なし（Foundation のみ） |
| **LLMLocalModels** | モデル管理（DL・キャッシュ・メタデータ・アダプター） | Foundation, LLMLocalClient |
| **LLMLocalMLX** | MLX バックエンド実装 | mlx-swift-lm, LLMLocalClient |
| **LLMLocal** | アンブレラモジュール（再エクスポート） | 上記すべて |

## 依存方向

```
LLMLocalClient（Protocol のみ、外部依存なし）
  ↑
LLMLocalModels（モデル管理）
  ↑
LLMLocalMLX（MLX 具体実装）
  ↑
LLMLocal（アンブレラ）
```

## 決定事項

| ID | 決定 | 根拠 |
|---|---|---|
| D-01 | MLX を推論バックエンドに採用 | Apple 公式推奨、最高性能、Swift ネイティブ |
| D-02 | ベースモデルは HuggingFace から取得 | 無料 CDN、MLX 対応済み、エコシステム最大 |
| D-03 | アダプターは GitHub Releases から配布 | 数十MB で収まる、無料、バージョン管理容易 |
| D-04 | マクロは初期スコープ外 | ボイラープレートが明確になってから導入 |
| D-05 | パッケージ名は `swift-llm-local` | 既存命名規則 `swift-{機能名}` に準拠 |

## 機能一覧（Feature Flag）

| ID | 機能 | 優先度 | Phase |
|---|---|---|---|
| FF-01 | Protocol ベースの推論抽象化 | Must | 1 |
| FF-02 | MLX バックエンド実装 | Must | 1 |
| FF-03 | HuggingFace モデルダウンロード・キャッシュ | Must | 1 |
| FF-04 | ストリーミング生成（AsyncThrowingStream） | Must | 1 |
| FF-05 | モデルメタデータ管理 | Must | 1 |
| FF-06 | LoRA アダプター管理（DL・合成） | Should | 2 |
| FF-07 | メモリ監視・自動アンロード | Should | 2 |
| FF-08 | ダウンロード進捗通知 | Should | 2 |
| FF-09 | バックグラウンドダウンロード（URLSession background） | Could | 3 |
| FF-10 | 複数モデル切り替え | Could | 3 |
