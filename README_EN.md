English | [日本語](README.md)

# LLMLocal

On-device LLM inference Swift package for iOS / macOS

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018.0+%20%7C%20macOS%2015.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Features

- **On-device Inference** - Privacy-preserving AI without cloud API dependency
- **MLX Backend** - High-performance inference engine optimized for Apple Silicon
- **Model Management** - Download tracking, resume, and local caching
- **LoRA Support** - Load adapters from GitHub Releases / HuggingFace / local files
- **Memory Monitoring** - Automatic model unloading based on device memory
- **Multi-model Switching** - LRU-based automatic model swapping

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-local.git", .upToNextMajor(from: "1.0.0"))
]
```

### Module Structure

Import only the modules you need:

| Module | Purpose |
|--------|---------|
| `LLMLocal` | Umbrella (all modules + LLMLocalService) |
| `LLMLocalClient` | Protocol layer only (for app abstraction, no external dependencies) |
| `LLMLocalMLX` | MLX backend (for app DI configuration) |

## Quick Start

```swift
import LLMLocal

// 1. Create service
let service = LLMLocalService(
    backend: MLXBackend(),
    modelManager: ModelManager()
)

// 2. Generate with preset model (streaming)
for try await token in service.generate(
    model: ModelPresets.gemma2B,
    prompt: "Explain how to create a list in SwiftUI"
) {
    print(token, terminator: "")
}
```

### Custom Generation Parameters

```swift
let config = GenerationConfig(
    maxTokens: 512,
    temperature: 0.7,
    topP: 0.9
)

for try await token in service.generate(
    model: ModelPresets.gemma2B,
    prompt: "Write a creative short story",
    config: config
) {
    print(token, terminator: "")
}
```

### Using LoRA Adapters

```swift
let modelWithAdapter = ModelSpec(
    id: "gemma-with-lora",
    base: .huggingFace(id: "mlx-community/gemma-2-2b-it-4bit"),
    adapter: .huggingFace(id: "your-org/your-adapter"),
    contextLength: 4096,
    displayName: "Fine-tuned Gemma",
    description: "Domain-specific fine-tuned model"
)
```

## Architecture

4-layer architecture for separation of concerns:

```
Layer 0: LLMLocalClient      Protocol + shared types (no external dependencies)
Layer 1: LLMLocalModels       Model management
Layer 2: LLMLocalMLX          MLX concrete implementation
Umbrella: LLMLocal            Service + re-exports
```

## Documentation

See the DocC documentation for detailed guides and API reference.

| Guide | Description |
|-------|-------------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/) | Full public API |

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+
- Xcode 16.0+

## Dependencies

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 1.0.0) - LLM client abstraction
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (>= 2.30.0) - MLX inference framework

## License

MIT License - See [LICENSE](LICENSE) for details

## Links

- [Full Documentation](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/)
- [Report Issues](https://github.com/no-problem-dev/swift-llm-local/issues)
- [Discussions](https://github.com/no-problem-dev/swift-llm-local/discussions)
- [Release Process](RELEASE_PROCESS.md)
