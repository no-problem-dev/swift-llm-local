# ``LLMLocalClient``

Backend protocol and shared value types, with no dependency on MLX or on the network.

## Overview

This is the bottom of the package. It declares ``LLMLocalBackend`` and the types that cross every
layer — ``ModelSpec``, ``GenerationConfig``, ``GenerationStats``, ``LLMLocalError`` — and depends
only on `swift-llm-client`.

Import it when you want to write against the abstraction rather than against MLX. Two cases make
that worth doing: library targets that would otherwise pull an inference engine into their
dependency graph, and tests, which need a backend that returns canned tokens instead of one that
requires Apple Silicon and gigabytes on disk.

```swift
import LLMLocalClient

func warmUp(backend: any LLMLocalBackend) async throws {
    let spec = ModelSpec(
        id: "my-model",
        base: .huggingFace(id: "org/my-model"),
        contextLength: 8192,
        displayName: "My Model",
        description: "Custom fine-tune",
        estimatedMemoryBytes: 2_000_000_000
    )
    try await backend.loadModel(spec)
}
```

`estimatedMemoryBytes` on a ``ModelSpec`` is not decoration. It is the number the memory checks
compare against the device, and getting it wrong means loading a model the process cannot hold.

The module re-exports `LLMClient` and `LLMTool`, so `ToolDefinition`, `LLMMessage`, and `JSONSchema`
come with it and do not need a second import.

### Reasoning models emit text you must not show

Models with a thinking mode wrap their scratchpad in `<think>` tags. It is generated, it costs time
and context, and it is not part of the answer. ``ThinkTagParser`` removes it from a token stream,
including when a tag is split across two chunks.

## Topics

### Backend protocol

- ``LLMLocalBackend``
- ``AdapterResolving``

### Model definition

- ``ModelSpec``
- ``ModelSource``
- ``AdapterSource``

### Generation

- ``GenerationConfig``
- ``GenerationOutput``
- ``GenerationStats``
- ``GenerationInfo``
- ``ThinkTagParser``

### Downloads

- ``DownloadProgress``
- ``DownloadedModel``
- ``ModelSizeTier``

### Errors

- ``LLMLocalError``
