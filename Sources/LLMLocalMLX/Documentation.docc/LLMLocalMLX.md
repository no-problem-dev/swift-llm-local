# ``LLMLocalMLX``

Apple MLX backend — where the model actually loads, generates, and competes with the rest of the app for memory.

## Overview

``MLXBackend`` is the concrete `LLMLocalBackend`. It wraps `mlx-swift-lm`: downloading weights
from the Hugging Face Hub, loading them onto the GPU, running generation, driving tool calls
through the model's chat template, and reusing the prompt cache between turns.

Most apps reach it through the `LLMLocal` umbrella. Import this module directly at the composition
root — the one place that constructs the backend and hands it to whatever needs it.

```swift
import LLMLocalClient
import LLMLocalMLX

let backend = try MLXBackend(
    gpuCacheLimit: 30 * 1024 * 1024,
    adapterResolver: myAdapterRegistry
)

let spec = ModelSpec(
    id: "qwen3-4b",
    base: .huggingFace(id: "mlx-community/Qwen3-4B-4bit"),
    contextLength: 32768,
    displayName: "Qwen3 4B",
    description: "Balanced open model",
    estimatedMemoryBytes: 2_400_000_000
)
try await backend.loadModel(spec)
```

### Why the GPU cache is capped

MLX keeps a buffer cache that grows to fit what generation asks of it. Left alone it competes with
the app for the same physical memory, and on iOS the resolution is not an error — it is the process
being terminated. `gpuCacheLimit` bounds it, defaulting to 20 MB, and is worth raising only when
you have measured headroom.

``MemoryMonitor`` covers the other side, but only partly automatically: it observes the system
low-memory notification and can unload in response. Its headroom figures — `isModelCompatible(_:)`
and the recommended context length — are advisory, and nothing in `loadModel` consults them. On iOS
the budget is a share of the memory currently available to the process, so it moves during a
session; on macOS it is a share of physical memory.

### Concurrency

`MLXBackend` is an `actor` and keeps exactly one model resident. Loading a different spec unloads
the current one first, which means a *failed* load leaves the backend with no model rather than the
one it had. Loads are not queued: a second load while one is in flight is refused rather than made
to wait.

### Loading is eager

Weights are read in full and materialised before `loadModel` returns — not memory-mapped lazily. On
a cold start that read, rather than the first forward pass, is most of the time to first token.

### Prompt cache reuse

`generateFromMessages` keeps the KV cache across turns, so a long conversation does not reprocess
its whole history on every request. The saving is real and grows with the conversation, but the
cache is memory too, and it grows with context length.

### Injecting how models arrive

`downloader` and `tokenizerLoader` default to the Hugging Face Hub and `swift-transformers`.
Replace them to load weights from S3, an app bundle, or anywhere else — the signature is the
extension point mlx-swift-lm 3.x expects.

## Topics

### Backend

- ``MLXBackend``

### Downloads

- ``DestinationHubDownloader``

### Local model storage

- ``LocalModelInventory``

### Memory

- ``MemoryMonitor``
- ``MemoryProvider``
