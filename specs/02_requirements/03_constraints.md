---
title: "Constraints"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
---

# Constraints

## 技術的制約

### C-01: iOS メモリ制限
- iPhone 16 Pro: 実質利用可能 5-6GB（OS が 2-3GB 占有）
- iPhone 17 Pro: 実質利用可能 8-9GB（12GB RAM 予測）
- 7B Q4 モデル: 約 4.14GB → iPhone 16 Pro ではギリギリ
- **対策**: コンテキスト長制限（2048-4096）、KV キャッシュの動的管理

### C-02: iOS シミュレータで Metal が使えない
- MLX は Metal バックエンドに依存
- **対策**: 実機テスト必須。シミュレータでは Protocol の Mock テストのみ

### C-03: iOS バックグラウンド制約
- バックグラウンドで GPU を使い続けると iOS が kill する
- **対策**: フォアグラウンド限定の推論、またはバックグラウンド遷移時にモデルアンロード

### C-04: モデルファイルサイズ
- 7B Q4 モデル: 4GB+
- アプリバンドルに同梱不可 → オンデマンドダウンロード必須
- App Store の OTA ダウンロード制限（200MB）に抵触しないよう、モデルはアプリ外で管理

## 外部依存

| 依存先 | バージョン | 用途 | リスク |
|---|---|---|---|
| mlx-swift | 0.30.x | コア ML 演算 | Apple 公式、活発に開発中 |
| mlx-swift-lm | 最新 | LLM 推論 API | mlx-swift-examples から分離、安定化途上 |
| HuggingFace Hub | - | モデルホスティング | 無料、API 安定 |

## スコープ外

- リモート LLM API との統合（swift-llm-structured-outputs の責務）
- モデルのファインチューニング（Mac Studio + mlx-lm で別途実施）
- UI コンポーネント（アプリ側の責務）
- Android 対応
