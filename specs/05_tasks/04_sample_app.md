---
title: "Sample App Tasks"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
  - ../04_implementation_plan/06_sample_app.md
---

# Sample App Tasks

## Wave SA-1: 基盤

### S1: Create project scaffold

- description:
  - ディレクトリ構造、project.yml、Makefile、.gitignore、Assets.xcassets を作成
  - `xcodegen generate` でプロジェクト生成確認

- files:
  - create: Examples/LLMLocalExample/project.yml
  - create: Examples/LLMLocalExample/Makefile
  - create: Examples/LLMLocalExample/.gitignore
  - create: Examples/LLMLocalExample/App/Resources/Assets.xcassets/

- verification:
  - [x] xcodegen generate 成功

---

### S2: Create Domain and DI layer

- description:
  - ChatMessage ドメインモデルと ServiceFactory を作成

- files:
  - create: Examples/LLMLocalExample/Sources/Domain/ChatMessage.swift
  - create: Examples/LLMLocalExample/Sources/DI/ServiceFactory.swift

- verification:
  - [x] ファイル作成完了

---

### S3: Create State layer

- description:
  - ChatState, ModelState, SettingsState の 3 つの @Observable State クラスを作成

- files:
  - create: Examples/LLMLocalExample/Sources/State/ChatState.swift
  - create: Examples/LLMLocalExample/Sources/State/ModelState.swift
  - create: Examples/LLMLocalExample/Sources/State/SettingsState.swift

- verification:
  - [x] ファイル作成完了

---

## Wave SA-2: App Shell + Views

### S4: Create App entry point and all Views

- description:
  - LLMLocalExampleApp.swift、ContentView、Chat/Models/Settings の全 View を作成

- files:
  - create: Examples/LLMLocalExample/App/Sources/LLMLocalExampleApp.swift
  - create: Examples/LLMLocalExample/Sources/Views/ContentView.swift
  - create: Examples/LLMLocalExample/Sources/Views/Chat/*.swift (5 files)
  - create: Examples/LLMLocalExample/Sources/Views/Models/*.swift (3 files)
  - create: Examples/LLMLocalExample/Sources/Views/Settings/*.swift (4 files)

- verification:
  - [x] ファイル作成完了

---

## Wave SA-3: Build Verification

### S5: Build verification

- description:
  - xcodegen generate + xcodebuild でビルド成功を確認
  - コンパイルエラーがあれば修正

- deps:
  - S1, S2, S3, S4

- verification:
  - [ ] `xcodegen generate` 成功
  - [ ] `xcodebuild build` 成功（iOS Simulator）
  - [ ] strict concurrency エラーなし
