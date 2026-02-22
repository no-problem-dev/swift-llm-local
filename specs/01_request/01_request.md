---
title: "swift-llm-local Request"
created: 2026-02-22
status: draft
---

# Request: swift-llm-local

## 発端

iOS アプリでローカル LLM 推論を実現したい。クラウド API に依存せず、iPhone 上で日本語 LLM（Swallow 7B 等）を直接動かすことで、オフライン対応・プライバシー保護・レイテンシ削減を実現する。

## 背景

- **MLX Swift の成熟**: Apple が WWDC 2025 で MLX を公式推奨。mlx-swift-lm パッケージにより iOS 18+ での LLM 推論が実用的になった
- **デバイス性能の向上**: iPhone 17 Pro（12GB RAM）で Swallow 7B Q4 量子化が実用速度（12-14 tok/s）で動作する見込み
- **ファインチューニングの現実性**: Mac Studio + mlx-lm で LoRA ファインチューニングが個人レベルで可能。アダプター（数十MB）だけを配布すればよい
- **既存パッケージ資産**: no-problem-dev エコシステムに swift-llm-structured-outputs（リモート LLM）が既にあり、ローカル LLM のサービス層が不足している

## 課題

1. **MLX は低レベル**: `loadModel(id:)` → `streamResponse(to:)` で推論はできるが、モデル管理・ダウンロード進捗・メモリ管理・複数モデル切り替えといったアプリケーション層の責務をカバーしない
2. **抽象化の欠如**: アプリコードが MLX に直接依存すると、バックエンド切り替え（将来の Core ML 対応等）が困難
3. **LoRA アダプター管理**: ベースモデル（HuggingFace）+ アダプター（GitHub Releases）という二重ソースの管理が必要
4. **メモリ制約**: iPhone の実質利用可能 RAM（5-9GB）でのモデルライフサイクル管理が必要

## 解決方針

MLX を具体実装として差し込む、Protocol ベースのサービス層 Swift パッケージを作成する。

## 期待する成果

- iOS アプリから `import LLMLocal` で、ローカル LLM 推論をシンプルに利用できる
- モデルの取得・キャッシュ・推論が統一された API で提供される
- MLX への依存がパッケージ内部に閉じ、アプリ側は Protocol のみに依存する
