English | [日本語](README.ja.md)

# LLMLocal

Run open LLMs entirely on iOS and macOS devices, through Apple MLX. No API key, no network, no per-token cost.

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018.0+%20%7C%20macOS%2015.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Features

- **On-device inference** — prompts and output never leave the device
- **MLX backend** — Apple Silicon inference via `mlx-swift-lm`, with a capped GPU cache and KV-cache reuse across turns
- **Curated model presets** — Qwen, Gemma, Llama, Ministral, and DeepSeek specs with memory estimates you can check against the device before loading
- **Agent integration** — `LocalAgentClient` conforms to `swift-llm-client`'s `AgentCapableClient`, so a local model drops into the same agent loop as a cloud provider
- **Tool calling** — per-model support is recorded in `ModelProfile.toolCallSupport`; passing tools to a model that cannot do it throws instead of degrading silently
- **Memory monitoring** — models are unloaded under pressure, because the alternative on iOS is the OS terminating the app
- **Multi-model switching** — one model is resident at a time, so a second replaces the first rather than joining it
- **LoRA adapters** — loaded from Hugging Face, GitHub Releases, or local files

## Quick Start

```swift
import LLMLocal

let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry(cacheDirectory: cacheDirectory)
)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "How do I build a list in SwiftUI?"
) {
    print(token, terminator: "")
}
```

The first call for a model downloads its weights from the Hugging Face Hub — gigabytes, on the
user's network. Treat the first run as a download, and show progress.

```swift
// maxTokens: nil (the default) generates until the context limit
let config = GenerationConfig(maxTokens: 512, temperature: 0.7, topP: 0.9)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "Write a short story.",
    config: config
) {
    print(token, terminator: "")
}
```

## Documentation

- [API reference](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/) — every public symbol, per module
- [Getting started](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/gettingstarted) — model selection, tool calling, and managing downloads
- [Architecture](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/architecture) — the four layers, and which one to depend on

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-local.git", from: "5.0.0")
]
```

An app depends on `LLMLocal`. A library target or a test should depend on `LLMLocalClient` instead
and take the backend by injection — that compiles without MLX.

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "LLMLocal", package: "swift-llm-local"),
])
```

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+
- Xcode 16.0+
- Apple Silicon for macOS; a device with enough free memory for the chosen model

## License

MIT License — See [LICENSE](LICENSE) for details
