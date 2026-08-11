# Getting Started

Building the service, picking a model that fits the device, and streaming the first tokens.

## Build the service

``LLMLocalService`` is an `actor` that ties an inference backend to a model registry. Constructing
it is cheap and touches neither disk nor GPU; the expensive work happens on the first generate.

```swift
import LLMLocal

let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry()
)
```

Pass a `MemoryMonitor` to have models unloaded when the process comes under memory pressure. On iOS
this is the difference between an eviction you chose and a termination you did not — the system
does not warn twice.

```swift
let monitor = MemoryMonitor()
let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry(),
    memoryMonitor: monitor
)
await service.startMemoryMonitoring()
```

## Pick a model that fits

``ModelPresets`` carries specs for the common open models. Check `estimatedMemoryBytes` against the
device before loading: a model larger than the process can hold does not fail gracefully, it gets
the app killed.

```swift
let small   = ModelPresets.qwen3_0_6B   // ~350 MB — viable on any supported device
let balanced = ModelPresets.qwen3_4B    // ~2.4 GB — needs a recent, high-memory device

let all = ModelPresets.all              // every preset, ascending by memory
```

`isModelCompatible(_:)` answers the same question against the actual device rather than your guess.

## Generate

`generate(model:prompt:config:)` loads the model if it is not resident and returns a stream of
token strings. If the weights are not on disk yet, this call downloads them from the Hugging Face
Hub first — gigabytes, on whatever network the user is on. Show a progress UI for the first run.

```swift
let stream = await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "How do I run async work in SwiftUI?"
)

for try await token in stream {
    print(token, terminator: "")
}
```

> Important: this path is stateful. It reuses an internal chat session, so consecutive calls
> accumulate history — right for a chat UI, wrong for independent one-shot prompts. Call
> `resetChatSession()` between them, or use `generateFromMessages(model:messages:systemPrompt:config:tools:)`,
> which takes the conversation explicitly and accumulates nothing.

Sampling is controlled with `GenerationConfig`.

```swift
let config = GenerationConfig(
    maxTokens: 512,
    temperature: 0.7,
    topP: 0.9
)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "Write a four-line poem about rain.",
    config: config
) {
    print(token, terminator: "")
}
```

## Tool calling

`generateFromMessages` yields a `GenerationOutput` per element rather than a bare string, which is
what lets you interleave tool execution with text.

```swift
let stream = await service.generateFromMessages(
    model: ModelPresets.qwen3_4B,
    messages: [.user("What is the weather in Tokyo?")],
    systemPrompt: "You are a helpful assistant.",
    tools: [weatherTool]
)

for try await output in stream {
    switch output {
    case .text(let text):  print(text, terminator: "")
    case .toolCall(let call): try await executeTool(call)
    case .info(let stats): print("\n\(stats.tokensPerSecond) tok/s")
    }
}
```

Tool calling is a property of the model, not of this package. It is driven by the model's chat
template, so a model that was never trained for it will produce prose that looks like a tool call
instead of one. `ModelProfile.toolCallSupport` records which presets are usable, and passing tools
to a model marked `.unsupported` throws rather than silently degrading.

This path reports measured token statistics. The plain `generate` path approximates
`tokensPerSecond` from chunk counts, because the backend does not stream real counters through it.

## Manage what is on disk

Installed models are determined by looking at the filesystem, not by an in-memory registry, so the
answer stays correct across app launches.

```swift
if await service.isDownloaded(ModelPresets.qwen3_4B) {
    // weights are local; loading will not hit the network
}

let downloaded = await service.downloadedModels(among: ModelPresets.all)
let bytes = await service.totalDownloadedSize(among: ModelPresets.all)

try await service.deleteDownload(ModelPresets.qwen3_4B)
```

Models are large enough that users will notice them in Settings. Give them a way to delete one.
