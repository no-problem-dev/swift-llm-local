# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- **BREAKING** — `LocalAgentClient.generateWithUsage` takes a `GenerationOptions` value instead of
  separate `systemPrompt`, `temperature` and `maxTokens` arguments, following swift-llm-client
  4.0.0. The requirement's signature now differs from the convenience method beside it, which is
  what stops a conformance that forgets the requirement from calling the convenience back into
  itself forever. Call sites that pass the arguments individually keep working — llm-client still
  ships those as defaulted convenience overloads.

### Changed

- Raised the swift-llm-client pin to 4.0.0.


Nothing.

## [3.0.0] - 2026-07-19

### Removed
- `StubBackgroundDownloadDelegate` is no longer public. It was only ever for internal use.

### Changed
- Fuller documentation comments, and DocC articles throughout: a rich landing page per module
  with the overview injected into the combined root, plus a Getting Started article.
  Documentation comments and DocC rewritten in Japanese, and the README unified as a Japanese
  and English pair.
- CI workflows synced to the standard SSOT template (tests + release-on-tag; the old
  auto-release is gone). DocC is built as combined documentation across every library.

## [2.2.6] - 2026-06-14

### Fixed
- Handle `MessageContent.document`, following swift-llm-client 3.7.0.

## [2.2.5] - 2026-06-13

### Fixed
- **Gave every preset an explicit family-specific `recommendedGeneration`, closing the gap where thinking mode was missed**:
  presets with no `recommendedGeneration` (Qwen3.6 27B / 30B-A3B / 35B-A3B MoE,
  Qwen2.5 14B/32B/72B, Qwen3 8B/9B and others, 32 in total) used to fall back to
  `GenerationConfig.default` (`enableThinking: true`, generic sampling). Qwen3-family
  chat templates leave `<think>` open and force reasoning on every turn when
  `enable_thinking` is unset, so using these in an agent or orchestrator ran a long
  reasoning pass on every tool call and made them extremely slow. Every model now
  carries an explicit family-specific setting, and thinking is off by default except on
  the models whose core is reasoning (DeepSeek-R1 / GPT-OSS).

### Added
- **Family-specific recommended generation presets** (following the sampling values on the official model cards):
  `gemmaAgentic` (temp 1.0 / topK 64 / topP 0.95), `llamaAgentic` (0.6 / 0.9),
  `phiAgentic` (0.8 / 0.95), `smolAgentic` (0.6 / 0.95, thinking off),
  `glmAgentic` (0.6 / 0.95), `graniteAgentic` (0.7 / 0.95),
  `deepseekReasoning` (0.6 / 0.95, thinking on), `gptOssReasoning` (1.0 / 1.0, thinking on).
- **Regression tests**: `ModelPresetsTests` now permanently verifies "every preset has
  something other than `GenerationConfig.default`" and "everything but the reasoning
  models has `enableThinking == false`".

## [2.2.4] - 2026-06-13

### Fixed
- Followed the agent-step contract's import source to `LLMAgentStep`.

## [2.2.3] - 2026-06-11

### Added
- Inventory API for downloaded models (queries that treat the disk as the truth).

## [2.2.2] - 2026-06-11

### Fixed
- Fixed the prompt KV cache leaking between conversations during concurrent generation on a shared backend.

## [2.2.1] - 2026-06-11

### Fixed
- **Stopped re-injecting past reasoning into multi-turn history**: `<think>…</think>` was
  being fed back into history, against the official guidance for thinking-capable models
  such as the Qwen3 family (history holds only the final output, never the reasoning).
  This removes the wasted context and the quality loss from duplicating what the
  template's thinking section already handles.
- **iOS model compatibility is now judged against process-available memory**
  (`MemoryMonitor.isModelCompatible` / `maxAllowedModelMemory`): on iOS/tvOS/watchOS
  jetsam terminates the app before physical RAM runs out, so the limit is 80% of
  `os_proc_available_memory()`. Previously a 4–5GB model was wrongly judged usable on an
  8GB device, which could crash on real hardware. macOS still uses 80% of total physical memory.
- **Corrected usage reporting when the prompt cache is reused**: even when only the
  suffix is prefilled, `GenerationInfo.promptTokenCount` reports the full prompt length after templating.

### Improved
- **Prompt (KV) cache reuse on the `generateFromMessages` path**: the common prefix of the
  prompt is detected between turns and only the difference (the suffix) is prefilled.
  Even as a conversation grows, as in an agent loop, prefill cost stays limited to the
  delta, which improves perceived on-device latency. When reuse is not possible it falls
  back safely to a new cache and a full prefill (using `MLXLMCommon`'s `trimPromptCache`).

### Added
- **Added the KV quantization start position and the penalty family to `GenerationConfig`** (defaults provided, so backward compatible):
  - `quantizedKVStart`: the token position at which quantization starts when `kvBits` is set
  - `presencePenalty` / `presenceContextSize` / `frequencyPenalty` / `frequencyContextSize`:
    OpenAI-compatible penalties (following `GenerateParameters` in mlx-swift-lm 3.x)

## [2.2.0] - 2026-06-09

### Added
- **`lfm2_5_8B_a1b` preset**: LFM2.5 8B-A1B (MoE, 1B active). 8B-class quality at the
  speed of a 1.2B. `mlx-community/LFM2.5-8B-A1B-MLX-4bit` (4.76GB, just inside the iPhone budget)

### Changed
- **Audited and optimized the quantization variants against Hugging Face primary sources** (2026-06-09, measured on mlx-community):
  - `lfm2_5_1_2B`: 4bit(0.66GB) → **6bit(0.95GB)**. At 1.2B the 4bit degradation is relatively large
  - `qwen3_4B`: `Qwen3-4B-Instruct-2507-4bit` → **`...-4bit-DWQ-2510`** (same 2.3GB, distilled quantization = higher accuracy at no cost)
  - `ministral3_3B`: 4bit(2.75GB) → **6bit(3.61GB)**. On function-calling specialists, quantization damage goes straight to tool-call accuracy
  - `qwen3_5_2B` / `qwen3_5_4B` are left as they are; 6bit is the best fit inside the iPhone budget (8bit exceeds it)
  - Confirmed excluded by the audit: Gemma 4 / Granite 4 have no tool-call output parser
    in mlx-swift-lm 3.31.3 and are disqualified for agent use (loading itself works)

## [2.1.1] - 2026-06-08

### Changed
- **Revisited quantization for the Qwen3.5 presets**: 4bit degrades small models badly, so
  they are unified on mlx-community's standard **6bit line** (the quality/size sweet spot).
  - `qwen3_5_2B`: `Qwen3.5-2B-4bit` → `Qwen3.5-2B-6bit` (+0.5GB for better quality)
  - `qwen3_5_4B`: `Qwen3.5-4B-OptiQ-4bit` (unknown provenance, 4.0GB) → `Qwen3.5-4B-6bit`
    (4.1GB, standard quantization and high quality at nearly the same size). OptiQ was a
    bad trade: 4bit quality at the same size

## [2.1.0] - 2026-06-08

### Added
- **Exposed all of MLX's knobs on `GenerationConfig`**: `topK` / `minP` / `repetitionPenalty` /
  `repetitionContextSize` (sampling), `kvBits` / `maxKVSize` / `kvGroupSize`
  (KV cache quantization = less memory on long contexts), `prefillStepSize`,
  `enableThinking` (suppress thinking mode). All propagate to `GenerateParameters` and the chat template
- **Thinking-mode control `enableThinking`**: `false` injects an empty `<think></think>` to
  skip reasoning generation. Greatly reduces latency on models where thinking is on by default, such as Qwen3.5 4B
- **`ModelSpec.recommendedGeneration`**: per-model recommended generation settings. `LocalAgentClient`
  takes these as the baseline and overrides only the caller's `maxTokens` / `temperature`.
  Family-specific recommended values are set on the presets (Qwen: topP 0.8 / topK 20 / thinking off; LFM2: low temperature, min_p,
  repetition penalty; Mistral: low temperature)

### Changed
- `GenerationConfig` conforms to `Hashable` / `Codable` (so it can be embedded in `ModelSpec`)

## [2.0.2] - 2026-06-08

### Fixed
- **Fixed model download failure on iOS**: swift-huggingface's cache path
  (`#hubDownloader()` = `downloadSnapshot(returnCachePath: true)`) failed to resolve paths
  for large LFS files (`model.safetensors` and the like) under the iOS sandbox's
  `Caches/huggingface/hub` and threw `cachedPathResolutionFailed`.
  A new `DestinationHubDownloader` using an explicit destination is now MLXBackend's default.
  It places files under Application Support (excluded from backup) and detects a complete
  snapshot to avoid re-downloading
- **Made `LLMLocalError` conform to `LocalizedError`**: without it, `localizedDescription`
  came out as "...LLMLocalError error N." and associated values such as `reason` were swallowed.
  Each case is expanded into human-readable text

## [2.0.1] - 2026-06-08

### Changed
- Made remote consumption possible (`url` + version requirement):
  - swift-llm-client changed from a path dependency to `url` + `from: 3.4.2`
  - mlx-swift-lm changed from a pinned revision to the tag `from: 3.31.3`
    (swift-llm-client 3.4.2's swift-syntax relaxation makes a versioned graph resolvable)
  - 2.0.0 contains path and revision dependencies and cannot be resolved remotely (local only)

## [2.0.0] - 2026-06-08

A full move to swift-llm-client 3.4.1 / mlx-swift-lm 3.x. A breaking release redesigned
around agent delegation (use as an `AgentCapableClient`) as the primary use case.

### Breaking Changes
- **Follows mlx-swift-lm 3.x**: model loading is now injection-based via `Downloader` / `TokenizerLoader`.
  `MLXBackend.init` gains `downloader:` / `tokenizerLoader:` parameters
  (defaults are the Hugging Face Hub + swift-transformers `AutoTokenizer`).
  Adds `swift-huggingface` / `swift-transformers` to the dependencies
- **swift-llm-client 3.4.1 conformance**: every `LocalAgentClient` method is updated to the
  current protocol signatures taking `SystemPrompt?` / `thinkingMode` / `reasoningEffort` / `cachePolicy`.
  `cachePolicy` / `reasoningEffort` / `thinkingMode` have no counterpart in local inference,
  so they are accepted and ignored (graceful degradation)
- **`GenerationConfig.maxTokens` is now `Int?`**: `nil` = generate up to the context limit.
  The default changes from 1024 to `nil`
- **Added `.info(GenerationInfo)` to `GenerationOutput`**: measured token counts
  (prompt / generation) arrive at the end of the stream when generation completes
- **Requests with tools against models that do not support tool calls are now an error**:
  adds `LLMLocalError.toolCallsUnsupported(modelId:)`. The behavior of silently dropping tools
  (the `LLMLocalBackend` default implementation and `LLMLocalService`) is removed, and
  models with `ModelProfile.toolCallSupport == .unsupported` are rejected explicitly
- **Model preset revision (38 → 37)**: tool-call capability verified for every preset against
  primary sources (the chat template's tools branch × mlx-swift-lm's `ToolCallFormat` parser coverage)
  - Removed: `smolLM_135M` (repository gone), `mistral7B` / `mistralSmall24B` (no parser support,
    replaced by Ministral 3), `lfm2_1_2B` (template missing in the mlx-community build, replaced by LFM2.5),
    `gemma2_2B` / `gemma2_9B` / `gemma3n_e2b` / `gemma3n_e4b` (superseded by later generations),
    `phi3_5_mini`, `deepseekR1_70B`
  - toolCallSupport corrections: all Gemma 3 variants, Granite, GPT-OSS, Phi-4 mini → `.unsupported`
    (template unsupported or no parser), SmolLM3 3B → `.good` (it does support them)
  - `contextLength` changed to the model's own maximum (max_position_embeddings).
    Runtime memory budget is now managed on the `GenerationConfig` side
  - Corrected the estimated memory of the Qwen3.5 family to measured values including the vision tower

### Added
- New presets: `lfm2_5_1_2B` / `lfm2_5_1_2B_ja` (Japanese-specialized) / `ministral3_3B` /
  `ministral3_8B` / `gemma4_e2b` / `gemma4_e4b` / `qwen3_6_27B` / `qwen3_6_35B_moe` /
  `glm4_7_flash`
- `GenerationInfo`: measured token statistics (promptTokenCount / generationTokenCount /
  tokensPerSecond). `LocalAgentClient`'s `TokenUsage` and `LLMLocalService`'s
  `GenerationStats` are now based on measured values
- `maxTokens` / `temperature` now pass through `LocalAgentClient` (previously fixed at 1024 / 0.7)
- `LocalAgentClient.generateWithUsage` handles JSON wrapped in Markdown code fences
- `LocalAgentClientTests`: verifies dispatch through protocol-constrained generics
  (regression guard against infinite recursion from an unsatisfied witness and streaming turning into dead code)

### Fixed
- Resolved the infinite recursion in `StructuredLLMClient.generateWithUsage` caused by an
  unsatisfied witness (`systemPrompt: String?` → `SystemPrompt?`)
- Fixed the local streaming implementation of `streamAgentStep` falling outside the protocol
  witness and becoming dead code

## [1.0.0] - 2026-02-23

### Added
- Initial release
- **LLMLocal** - umbrella module (all modules + LLMLocalService)
- **LLMLocalClient** - protocol layer (backend abstraction and shared types)
- **LLMLocalMLX** - MLX backend implementation

[Unreleased]: https://github.com/no-problem-dev/swift-llm-local/compare/3.0.0...HEAD
[3.0.0]: https://github.com/no-problem-dev/swift-llm-local/compare/2.2.6...3.0.0
[2.2.6]: https://github.com/no-problem-dev/swift-llm-local/compare/2.2.5...2.2.6
[2.2.0]: https://github.com/no-problem-dev/swift-llm-local/compare/2.1.1...2.2.0
[2.1.1]: https://github.com/no-problem-dev/swift-llm-local/compare/2.1.0...2.1.1
[2.1.0]: https://github.com/no-problem-dev/swift-llm-local/compare/2.0.2...2.1.0
[2.0.2]: https://github.com/no-problem-dev/swift-llm-local/compare/2.0.1...2.0.2
[2.0.0]: https://github.com/no-problem-dev/swift-llm-local/compare/1.7.2...2.0.0
[1.0.0]: https://github.com/no-problem-dev/swift-llm-local/releases/tag/v1.0.0
