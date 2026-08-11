# ``LLMLocal``

Umbrella module for running LLMs entirely on the device, with no cloud API in the generation path.

## Overview

`swift-llm-local` runs open models — Qwen3, Llama, and others — on Apple Silicon through Apple's
MLX framework. Nothing leaves the device, there is no API key, and there is no per-token cost. What
you pay instead is RAM, disk, and battery.

This module is the umbrella. It declares ``LLMLocalService``, ``ModelPresets``, ``ModelSwitcher``,
and ``LocalAgentClient``, and re-exports the protocol layer, the model-management layer, and the
MLX backend, so one import is enough for an app.

```swift
import LLMLocal

let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry()
)

for try await token in await service.generate(
    model: ModelPresets.qwen3_4B,
    prompt: "How do I make a list in SwiftUI?"
) {
    print(token, terminator: "")
}
```

The first call to a model that is not yet on disk downloads it from the Hugging Face Hub — for a 4B
model, on the order of gigabytes. Treat the first run as a download, not a request.

### Model management

`ModelRegistry`, `AdapterRegistry`, and `BackgroundDownloader` arrive through this module rather
than as their own import; the target that declares them is not a package product. Use them to see
what has been installed, to track transfers in flight, and to attach LoRA adapters.

`BackgroundDownloader` tracks state and delegates the transfer itself to a
`BackgroundDownloadDelegate` you supply; it has no default and performs no I/O of its own. Model
weights the package fetches go through `DestinationHubDownloader`, driven from the MLX backend.

### Keeping the app alive

Model weights are resident memory, and on iOS exceeding what the process is allowed does not throw
— the app is terminated. `MLXBackend` keeps one model resident and unloads the previous one before
loading the next, ``ModelSwitcher`` reports which that is by asking the backend, and
`MemoryMonitor` unloads on a system low-memory notification.

Its headroom arithmetic is advisory, though: nothing calls `isModelCompatible(_:)` for you. Check a
model against the device before you load it.

```swift
let monitor = MemoryMonitor()
let service = LLMLocalService(
    backend: MLXBackend(),
    modelRegistry: ModelRegistry(),
    memoryMonitor: monitor
)
await service.startMemoryMonitoring()
```

### Depending on less

A library target that only needs to *call* a model should import `LLMLocalClient` and take
`any LLMLocalBackend` by injection — that compiles without MLX and runs against a stub in tests.
See <doc:Architecture>.

## Topics

### Getting started

- <doc:GettingStarted>
- <doc:Architecture>

### Service

- ``LLMLocalService``

### Models

- ``ModelPresets``
- ``ModelSwitcher``

### Agent integration

- ``LocalAgentClient``
