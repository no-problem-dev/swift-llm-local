# 変更履歴

このプロジェクトの全ての重要な変更はこのファイルに記録されます。

フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいており、
このプロジェクトは [セマンティックバージョニング](https://semver.org/lang/ja/spec/v2.0.0.html) に準拠しています。

## [未リリース]

なし

## [2.1.1] - 2026-06-08

### 変更
- **Qwen3.5 プリセットの量子化を見直し**: 小型モデルは 4bit の劣化が大きいため、
  mlx-community 標準の **6bit ライン**へ統一（品質/サイズのスイートスポット）。
  - `qwen3_5_2B`: `Qwen3.5-2B-4bit` → `Qwen3.5-2B-6bit`（+0.5GB で品質向上）
  - `qwen3_5_4B`: `Qwen3.5-4B-OptiQ-4bit`（素性不明・4.0GB）→ `Qwen3.5-4B-6bit`
    （4.1GB・ほぼ同サイズで標準量子化・高品質）。OptiQ は同サイズで 4bit 品質の
    悪手だった

## [2.1.0] - 2026-06-08

### 追加
- **`GenerationConfig` に MLX の全ツマミを公開**: `topK` / `minP` / `repetitionPenalty` /
  `repetitionContextSize`（サンプリング）、`kvBits` / `maxKVSize` / `kvGroupSize`
  （KV キャッシュ量子化＝長コンテキストのメモリ削減）、`prefillStepSize`、
  `enableThinking`（思考モード抑制）。すべて `GenerateParameters` / チャットテンプレートへ伝搬
- **思考モード制御 `enableThinking`**: `false` で空の `<think></think>` を注入し思考生成を
  スキップ。Qwen3.5 4B など思考デフォルト ON のモデルのレイテンシを大幅に削減
- **`ModelSpec.recommendedGeneration`**: モデルごとの推奨生成設定。`LocalAgentClient` は
  これを基準にし、呼び出し側の `maxTokens` / `temperature` だけ上書きする。
  プリセットに家族別の推奨値を設定（Qwen: topP 0.8/topK 20/思考 OFF、LFM2: 低温・min_p・
  繰り返しペナルティ、Mistral: 低温）

### 変更
- `GenerationConfig` が `Hashable` / `Codable` に準拠（`ModelSpec` への埋め込みのため）

## [2.0.2] - 2026-06-08

### 修正
- **iOS でのモデルダウンロード失敗を修正**: swift-huggingface のキャッシュ経路
  （`#hubDownloader()` = `downloadSnapshot(returnCachePath: true)`）は、iOS
  サンドボックスの `Caches/huggingface/hub` 上で LFS 大ファイル（`model.safetensors`
  等）のパス解決に失敗し `cachedPathResolutionFailed` を投げていた。
  明示 destination 方式の `DestinationHubDownloader` を新設し MLXBackend の既定に。
  Application Support 配下（バックアップ除外）へ配置し、スナップショット完備を
  検出して再ダウンロードを回避する
- **`LLMLocalError` を `LocalizedError` 準拠に**: 未準拠だと `localizedDescription` が
  "...LLMLocalError error N." となり `reason` 等の associated value が握り潰されていた。
  各ケースを人間可読な文言に展開

## [2.0.1] - 2026-06-08

### 変更
- リモート消費（`url` + バージョン指定）を可能に:
  - swift-llm-client をパス依存から `url` + `from: 3.4.2` に変更
  - mlx-swift-lm を revision 固定からタグ `from: 3.31.3` に変更
    （swift-llm-client 3.4.2 の swift-syntax 緩和により versioned グラフが成立）
  - 2.0.0 はパス依存/revision 依存を含むためリモートからは解決不能（ローカル専用）

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

[未リリース]: https://github.com/no-problem-dev/swift-llm-local/compare/2.1.1...HEAD
[2.1.1]: https://github.com/no-problem-dev/swift-llm-local/compare/2.1.0...2.1.1
[2.1.0]: https://github.com/no-problem-dev/swift-llm-local/compare/2.0.2...2.1.0
[2.0.2]: https://github.com/no-problem-dev/swift-llm-local/compare/2.0.1...2.0.2
[2.0.0]: https://github.com/no-problem-dev/swift-llm-local/compare/1.7.2...2.0.0
[1.0.0]: https://github.com/no-problem-dev/swift-llm-local/releases/tag/v1.0.0
