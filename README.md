English | [日本語](README.ja.md)

# LLMLocal

On-device LLM inference Swift package for iOS / macOS

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018.0+%20%7C%20macOS%2015.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Features

- **On-device Inference** - Privacy-preserving AI without cloud API dependency
- **MLX Backend** - High-performance inference engine optimized for Apple Silicon
- **Agent Integration** - `LocalAgentClient` conforms to swift-llm-client's `AgentCapableClient`, so local LLMs can run in the same agent loop as cloud providers
- **Tool Calling** - Native function calling. Per-model capability is tracked via `ModelProfile.toolCallSupport`, and tool requests to unsupported models fail explicitly
- **Model Management** - Download tracking, resume, and local caching
- **LoRA Support** - Load adapters from GitHub Releases / HuggingFace / local files
- **Memory Monitoring** - Automatic model unloading based on device memory
- **Multi-model Switching** - LRU-based automatic model swapping

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-local.git", .upToNextMajor(from: "2.2.6"))
]
```

### Module Structure

Import only the modules you need:

| Module | Purpose |
|--------|---------|
| `LLMLocal` | Umbrella (all modules + LLMLocalService + LocalAgentClient) |
| `LLMLocalClient` | Protocol layer only (for app abstraction) |
| `LLMLocalMLX` | MLX backend (for app DI configuration) |

## Quick Start

```swift
import LLMLocal

// 1. Create service
let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry(cacheDirectory: cacheDirectory)
)

// 2. Generate with preset model (streaming)
for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "How do I build a list in SwiftUI?"
) {
    print(token, terminator: "")
}
```

### Customizing Generation Parameters

```swift
// maxTokens: nil (default) generates until the context limit
let config = GenerationConfig(
    maxTokens: 512,
    temperature: 0.7,
    topP: 0.9
)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "Write a short creative story",
    config: config
) {
    print(token, terminator: "")
}
```

### Using as an Agent Client

```swift
import LLMLocal

let client = LocalAgentClient(service: service)

// Inject into the same agent loop as cloud providers,
// as an AgentCapableClient from swift-llm-client
let response = try await client.executeAgentStep(
    messages: [.user("What's the weather in Tokyo?")],
    model: ModelPresets.qwen3_4B,
    systemPrompt: "You are a helpful assistant",
    tools: tools,
    toolChoice: .auto,
    responseSchema: nil,
    thinkingMode: .disabled,
    reasoningEffort: nil,
    maxTokens: nil,
    cachePolicy: .implicit
)
```

Tool calling capability is model-dependent. Passing tools to a model whose
`ModelProfile.toolCallSupport` is `.unsupported` (DeepSeek R1 distills, Gemma 3, etc.)
throws `LLMLocalError.toolCallsUnsupported`.

### Using LoRA Adapters

```swift
let modelWithAdapter = ModelSpec(
    id: "qwen-with-lora",
    base: .huggingFace(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit"),
    adapter: .huggingFace(id: "your-org/your-adapter"),
    contextLength: 262_144,
    displayName: "Fine-tuned Qwen",
    description: "Domain-specific fine-tuned model",
    estimatedMemoryBytes: 2_400_000_000
)
```

### Custom Downloaders

Supports mlx-swift-lm 3.x `Downloader` / `TokenizerLoader` injection.
The default is the Hugging Face Hub, but you can inject custom retrieval
strategies such as S3 or in-app bundles.

```swift
let backend = MLXBackend(
    downloader: myCustomDownloader,   // defaults to Hugging Face Hub
    tokenizerLoader: nil              // defaults to swift-transformers AutoTokenizer
)
```

## Architecture

Four-layer structure for separation of concerns:

```
Layer 0: LLMLocalClient      Protocols + shared types
Layer 1: LLMLocalModels       Model management
Layer 2: LLMLocalMLX          MLX concrete implementation
Umbrella: LLMLocal            Service + agent adapter + re-exports
```

## Documentation

See the DocC documentation for detailed guides and API reference.

| Guide | Contents |
|-------|----------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/) | All public APIs |

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+
- Xcode 16.0+

## Dependencies

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 3.5.1) - LLM client abstraction
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (3.x) - MLX inference framework
- [swift-huggingface](https://github.com/huggingface/swift-huggingface) - Hugging Face Hub client
- [swift-transformers](https://github.com/huggingface/swift-transformers) - Tokenizers

## License

MIT License - See [LICENSE](LICENSE) for details

## Links

- [Full Documentation](https://no-problem-dev.github.io/swift-llm-local/documentation/llmlocal/)
- [Report Issues](https://github.com/no-problem-dev/swift-llm-local/issues)
- [Discussions](https://github.com/no-problem-dev/swift-llm-local/discussions)
- [Release Process](RELEASE_PROCESS.md)
