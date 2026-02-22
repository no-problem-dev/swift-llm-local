---
title: "Development Rules"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../02_requirements/02_non_functional_requirements.md
---

# Development Rules

## ブランチ戦略

| ブランチ | 用途 | マージ先 |
|---|---|---|
| `main` | リリースブランチ（タグを切る） | - |
| `develop` | 開発統合ブランチ | `main` |
| `feature/{wave}-{概要}` | Wave 単位の機能ブランチ | `develop` |
| `fix/{概要}` | バグ修正 | `develop` |

### ブランチ命名例

```
feature/wave-1-1-package-setup
feature/wave-1-2-llmlocalclient
feature/wave-1-3-model-manager
feature/wave-1-4-mlx-backend
feature/wave-1-5-umbrella-service
fix/model-cache-path
```

### マージルール

- `feature/*` → `develop`: PR 必須、ビルド成功確認
- `develop` → `main`: Phase 完了時にマージ、タグ作成
- `main` への直接 push 禁止

---

## コーディング指針

### Swift バージョン・言語設定

| 項目 | 設定 |
|---|---|
| Swift Tools Version | 6.2 |
| Strict Concurrency | complete（Swift 6 モード） |
| Minimum Deployment | iOS 18.0, macOS 15.0 |

### Concurrency ルール

- 全 public 型は `Sendable` 準拠
- 状態を持つ型は `actor` で実装（class 禁止）
- `@MainActor` はパッケージ内では使用しない（アプリ側の責務）
- `nonisolated` の明示的指定で actor isolation を明確にする

### 命名規則

| 対象 | ルール | 例 |
|---|---|---|
| モジュール名 | `LLMLocal` 接頭辞 | LLMLocalClient, LLMLocalMLX |
| Protocol | 名詞 or 形容詞 | `LLMLocalBackend` |
| Actor | 名詞 | `MLXBackend`, `ModelManager` |
| Struct | 名詞 | `ModelSpec`, `GenerationConfig` |
| Enum | 名詞 | `ModelSource`, `LLMLocalError` |
| メソッド | 動詞 or 動詞句 | `loadModel()`, `generate()` |

### エラーハンドリング

- 全エラーは `LLMLocalError` enum に集約（`03_design_spec/01_architecture.md#エラー設計`）
- 外部ライブラリのエラーは `underlying: Error` でラップ
- `preconditionFailure` / `fatalError` は使用禁止（全てを `throws` で処理）

### ドキュメント

- 全 public API に DocC コメント付与
- パラメータ、戻り値、throws の説明を含める
- コード例（`/// ```swift ... ````）は主要 API に付与

### 依存ルール

| モジュール | 許可される依存 |
|---|---|
| LLMLocalClient | Foundation のみ（外部依存ゼロ） |
| LLMLocalModels | Foundation, LLMLocalClient |
| LLMLocalMLX | MLXLLM, MLXLMCommon, LLMLocalClient |
| LLMLocal | LLMLocalClient, LLMLocalModels, LLMLocalMLX |

- 依存方向は下位 → 上位のみ（循環依存禁止）
- LLMLocalClient への依存は全モジュール共通

### ファイル構成ルール

- 1 ファイル 1 型（Protocol/struct/enum/actor）
- ファイル名 = 型名（`ModelSpec.swift`）
- extension は同一ファイル内、または `TypeName+Category.swift`
- テストファイル名: `TypeNameTests.swift`

---

## コミットメッセージ規約

```
種別(スコープ): 内容

種別:
- feat: 新機能
- fix: バグ修正
- test: テスト追加・修正
- refactor: リファクタリング
- docs: ドキュメント
- chore: ビルド設定等

スコープ:
- client: LLMLocalClient
- models: LLMLocalModels
- mlx: LLMLocalMLX
- umbrella: LLMLocal
- package: Package.swift
```

### 例

```
feat(client): add LLMLocalBackend protocol and core types
feat(mlx): implement MLXBackend actor with streaming generation
test(client): add ModelSpec Codable and Hashable tests
fix(models): correct cache directory path on iOS
chore(package): update mlx-swift-lm dependency to 0.2.0
```

---

## CI 設定（検討事項）

現時点では CI は手動テスト。将来的に以下を検討:

| 項目 | 内容 |
|---|---|
| ビルド | `swift build` on macOS |
| Unit Tests | `swift test --skip LLMLocalMLXTests` |
| Integration Tests | 実機テスト（CI 除外、ローカルのみ） |
| Lint | SwiftFormat / SwiftLint（導入は任意） |
