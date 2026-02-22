---
title: "AI Instruction Template"
created: 2026-02-22
status: draft
references:
  - ./01_phase_wave.md
  - ./02_reference_matrix.md
---

# AI Instruction Template

## 指示構成テンプレート

AI にタスク実行を指示する際、以下のテンプレートで参照仕様を構成する。

### テンプレート

```markdown
## タスク概要
{Wave ID}: {Wave 名称}

## 実装対象
- モジュール: {対象モジュール名}
- ファイル: {作成/変更するファイルパス}

## 参照仕様（必ず読み込むこと）
1. {参照マトリクスから該当 FF の参照先をパス#節で列挙}
2. ...

## 実装手順
1. {01_phase_wave.md の該当 Wave の「実施内容」を参照}
2. ...

## 完了条件
- {01_phase_wave.md の該当 Wave の「完了条件」を転記}

## テスト
- {03_test_strategy.md の該当テストケースを参照}
```

### 使用例: Wave 1-2（LLMLocalClient モジュール）

```markdown
## タスク概要
Wave 1-2: LLMLocalClient モジュール（Protocol + 型定義）

## 実装対象
- モジュール: LLMLocalClient
- ファイル:
  - Sources/LLMLocalClient/LLMLocalBackend.swift
  - Sources/LLMLocalClient/ModelSpec.swift
  - Sources/LLMLocalClient/ModelSource.swift
  - Sources/LLMLocalClient/AdapterSource.swift
  - Sources/LLMLocalClient/GenerationConfig.swift
  - Sources/LLMLocalClient/GenerationStats.swift
  - Sources/LLMLocalClient/LLMLocalError.swift
  - Tests/LLMLocalClientTests/ModelSpecTests.swift
  - Tests/LLMLocalClientTests/GenerationConfigTests.swift

## 参照仕様（必ず読み込むこと）
1. specs/02_requirements/01_functional_requirements.md#FR-01
2. specs/03_design_spec/01_architecture.md#LLMLocalBackend
3. specs/03_design_spec/01_architecture.md#ModelSpec
4. specs/03_design_spec/01_architecture.md#ModelSource
5. specs/03_design_spec/01_architecture.md#AdapterSource
6. specs/03_design_spec/01_architecture.md#GenerationConfig
7. specs/03_design_spec/01_architecture.md#GenerationStats
8. specs/03_design_spec/01_architecture.md#エラー設計

## 実装手順
1. LLMLocalBackend protocol を定義（Sendable 準拠）
2. ModelSpec, ModelSource, AdapterSource, GenerationConfig, GenerationStats を定義
3. LLMLocalError enum を定義
4. TDD: テストを先に書き、実装を後から書く

## 完了条件
- LLMLocalClient モジュールが swift build でコンパイル成功
- 全型が Sendable 準拠
- Unit Tests が全パス

## テスト
- specs/04_implementation_plan/03_test_strategy.md#LLMLocalClientTests（Wave 1-2）
```

---

## コンパクション条件

各 Wave 完了時にコンテキストを圧縮する。以下の条件で `/compact` を実行する。

### 実行タイミング

| タイミング | 条件 |
|---|---|
| Wave 完了時 | 該当 Wave の全ファイル作成 + テストパス後 |
| コンテキスト膨張時 | 参照仕様の読み込みで出力が長くなった場合 |

### 保持する情報

| 保持対象 | 内容 |
|---|---|
| 現在の Wave | Wave ID と進捗状況 |
| 完了済み Wave | Wave ID 一覧と結果（成功/検討事項） |
| 検証結果 | Wave 1-1 の mlx-swift-lm API 検証結果 |
| Design Spec 差分 | 検証結果に基づく Design Spec の変更点 |
| 検討事項 | 未解決の検討事項一覧 |

### 破棄する情報

| 破棄対象 | 理由 |
|---|---|
| ファイル読み込み内容 | 参照パスがあれば再読み込み可能 |
| 中間的な試行錯誤 | 最終結果のみ保持 |
| テストの実行ログ | 結果（Pass/Fail）のみ保持 |

---

## Wave 間の引き継ぎフォーマット

Wave 完了時に以下を記録し、次 Wave に引き継ぐ。

```markdown
## Wave {ID} 完了サマリー

### 成果物
- {作成/変更したファイル一覧}

### テスト結果
- Unit Tests: {Pass/Fail}
- カバレッジ: {%}

### 検討事項
- {未解決の課題}

### 次 Wave への依存
- {次 Wave が必要とする情報}
```
