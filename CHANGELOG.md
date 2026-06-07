# 変更履歴

このプロジェクトの全ての重要な変更はこのファイルに記録されます。

フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいており、
このプロジェクトは [セマンティックバージョニング](https://semver.org/lang/ja/spec/v2.0.0.html) に準拠しています。

## [未リリース]

なし

## [2.0.0] - 2026-06-08

swift-llm-client 3.4.1 / mlx-swift-lm 3.x への全面追従。エージェント委譲
（`AgentCapableClient` としての利用）を主用途として再設計した breaking リリース。

### 破壊的変更
- **mlx-swift-lm 3.x 追従**: モデル取得が `Downloader` / `TokenizerLoader` 注入型に。
  `MLXBackend.init` に `downloader:` / `tokenizerLoader:` パラメータを追加
  （デフォルトは Hugging Face Hub + swift-transformers `AutoTokenizer`）。
  依存に `swift-huggingface` / `swift-transformers` を追加
- **swift-llm-client 3.4.1 conformance**: `LocalAgentClient` の全メソッドが
  `SystemPrompt?` / `thinkingMode` / `reasoningEffort` / `cachePolicy` を受け取る現行
  プロトコルシグネチャに更新。`cachePolicy` / `reasoningEffort` / `thinkingMode` は
  ローカル推論に対応概念がないため受領して無視（graceful degradation）
- **`GenerationConfig.maxTokens` が `Int?` に**: `nil` = コンテキスト上限まで生成。
  デフォルトは従来の 1024 から `nil` に変更
- **`GenerationOutput` に `.info(GenerationInfo)` を追加**: 生成完了時に実測トークン数
  （prompt / generation）がストリームの最後に流れる
- **ツールコール非対応モデルへのツール付きリクエストはエラーに**:
  `LLMLocalError.toolCallsUnsupported(modelId:)` を新設。ツールを黙って捨てる挙動
  （`LLMLocalBackend` デフォルト実装・`LLMLocalService`）を廃止し、
  `ModelProfile.toolCallSupport == .unsupported` のモデルを明示的に拒否
- **モデルプリセット改訂（38 → 37）**: 全プリセットのツールコール可否を一次情報
  （chat template の tools 分岐 × mlx-swift-lm の `ToolCallFormat` パーサ対応）で検証
  - 削除: `smolLM_135M`（リポジトリ消滅）、`mistral7B` / `mistralSmall24B`（パーサ非対応、
    Ministral 3 へ置換）、`lfm2_1_2B`（mlx-community 版テンプレート欠損、LFM2.5 へ置換）、
    `gemma2_2B` / `gemma2_9B` / `gemma3n_e2b` / `gemma3n_e4b`（後継世代で代替）、
    `phi3_5_mini`、`deepseekR1_70B`
  - toolCallSupport 修正: Gemma 3 全種・Granite・GPT-OSS・Phi-4 mini → `.unsupported`
    （テンプレート非対応またはパーサ不在）、SmolLM3 3B → `.good`（実は対応）
  - `contextLength` をモデル本来の最大値（max_position_embeddings）に変更。
    実行時のメモリ予算は `GenerationConfig` 側で管理する設計に
  - Qwen3.5 系の推定メモリをビジョンタワー込みの実測値に修正

### 追加
- 新プリセット: `lfm2_5_1_2B` / `lfm2_5_1_2B_ja`（日本語特化）/ `ministral3_3B` /
  `ministral3_8B` / `gemma4_e2b` / `gemma4_e4b` / `qwen3_6_27B` / `qwen3_6_35B_moe` /
  `glm4_7_flash`
- `GenerationInfo`: 実測トークン統計（promptTokenCount / generationTokenCount /
  tokensPerSecond）。`LocalAgentClient` の `TokenUsage` と `LLMLocalService` の
  `GenerationStats` が実測値ベースに
- `LocalAgentClient` に `maxTokens` / `temperature` の貫通（従来は 1024 / 0.7 固定）
- `LocalAgentClient.generateWithUsage` が Markdown コードフェンス付き JSON を処理
- `LocalAgentClientTests`: プロトコル制約付きジェネリクス経由のディスパッチ検証
  （witness 不成立による無限再帰・ストリーミング dead code 化の回帰防止）

### 修正
- `StructuredLLMClient.generateWithUsage` の witness 不成立による無限再帰を解消
  （`systemPrompt: String?` → `SystemPrompt?`）
- `streamAgentStep` のローカルストリーミング実装が protocol witness から外れて
  dead code 化していた問題を解消

## [1.0.0] - 2026-02-23

### 追加
- 初回リリース
- **LLMLocal** - アンブレラモジュール（全モジュール + LLMLocalService）
- **LLMLocalClient** - プロトコル層（バックエンド抽象化・共有型）
- **LLMLocalMLX** - MLX バックエンド実装

[未リリース]: https://github.com/no-problem-dev/swift-llm-local/compare/2.0.0...HEAD
[2.0.0]: https://github.com/no-problem-dev/swift-llm-local/compare/1.7.2...2.0.0
[1.0.0]: https://github.com/no-problem-dev/swift-llm-local/releases/tag/v1.0.0
