---
title: "Rollout Strategy"
created: 2026-02-22
status: draft
references:
  - ./01_phase_wave.md
  - ../02_requirements/00_index.md
---

# Rollout Strategy

## リリース戦略: 段階的タグリリース

| Phase | バージョン | スコープ | 前提条件 |
|---|---|---|---|
| Phase 1 | v0.1.0 | Core（FF-01〜FF-05） | Wave 1-7 Manual QA パス |
| Phase 2 | v0.2.0 | Enhanced（FF-06〜FF-08） | Wave 2-4 Manual QA パス |
| Phase 3 | v0.3.0 | Nice-to-have（FF-09〜FF-10） | Wave 3-2 QA パス |
| 安定版 | v1.0.0 | API 安定宣言 | Phase 1-3 利用実績 + API 破壊的変更なし |

### SemVer ルール（v0.x.x 期間）

- `0.x.0`: Phase 単位のリリース（新機能追加）
- `0.x.y`: バグ修正、パッチリリース
- API 破壊的変更は `0.x.0` で許容（v1.0.0 前のため）

### v1.0.0 への移行条件

- Phase 1-3 が完了し、実アプリで利用実績がある
- public API への破壊的変更が不要と判断される
- v1.0.0 以降は SemVer strict（破壊的変更は major bump）

---

## リリース手順

### Phase 完了時（v0.x.0 リリース）

```
1. develop ブランチで全 Wave 完了を確認
2. Manual QA チェックリストを全パス
3. develop → main へ PR 作成・マージ
4. main でタグ作成: git tag v0.x.0
5. GitHub Release 作成（リリースノート付き）
6. タグ push: git push origin v0.x.0
```

### バグ修正時（v0.x.y パッチ）

```
1. main からブランチ作成: fix/{概要}
2. 修正 + テスト追加
3. fix → main へ PR 作成・マージ
4. タグ作成: git tag v0.x.y
5. develop にもバックポート（cherry-pick or merge）
```

---

## ロールバック手順

### SPM 消費側のロールバック

```swift
// Package.swift で特定バージョンに固定
.package(url: "...", exact: "0.1.0")

// または前バージョンの範囲に制限
.package(url: "...", "0.1.0"..<"0.2.0")
```

### パッケージ側のロールバック

```
1. 問題のあるタグを削除: git tag -d v0.x.0 && git push origin :v0.x.0
2. 修正後に同一バージョンで再タグ、または次パッチバージョン（v0.x.1）でリリース
```

**タグ削除の判断基準**:
- リリース後 24 時間以内かつ消費者がほぼいない場合: タグ削除 + 同一バージョン再発行
- それ以外: 次パッチバージョンで修正リリース

---

## リリースチェックリスト

### v0.1.0（Phase 1 完了時）

- [ ] `swift build` 成功（macOS + iOS）
- [ ] `swift test --skip LLMLocalMLXTests` 全パス
- [ ] 実機 Integration Tests パス
- [ ] Manual QA チェックリスト全パス（`01_phase_wave.md#Wave 1-7`）
- [ ] NFR パフォーマンス基準達成
- [ ] DocC コメント付与済み
- [ ] README.md 作成（利用方法、対応プラットフォーム、制約事項）
- [ ] CHANGELOG.md 作成
- [ ] GitHub Release 作成

### v0.2.0（Phase 2 完了時）

- [ ] Phase 1 の全テストが引き続きパス（リグレッションなし）
- [ ] Phase 2 Manual QA チェックリスト全パス
- [ ] CHANGELOG.md 更新
- [ ] GitHub Release 作成

---

## 検討事項

| 項目 | 現時点の方針 | 将来検討 |
|---|---|---|
| GitHub Actions CI | なし（ローカルテスト） | `swift build` + Unit Test の自動化 |
| DocC ホスティング | ローカル生成 | GitHub Pages での公開 |
| SPM バイナリターゲット | 不使用 | モデルファイルのプリバンドル検討 |
