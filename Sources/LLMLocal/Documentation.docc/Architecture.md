# Architecture

Four layers, and which one your code should depend on.

## Overview

On-device inference drags in a large dependency graph — MLX, the Hugging Face Hub client, and a
tokenizer stack. The layering exists so that code which merely *uses* a local model does not have
to compile the machinery that runs one, and so that tests can substitute a backend without a GPU.

### Layer 0 — `LLMLocalClient`

Protocols and shared value types: `LLMLocalBackend`, `ModelSpec`, `ModelSource`, `AdapterSource`,
`GenerationConfig`, `GenerationStats`, `LLMLocalError`. It depends on `swift-llm-client` and
nothing else — no MLX, no networking.

This is the layer to import from library targets and from tests. Code written against
`any LLMLocalBackend` compiles in seconds and runs against a stub, which matters because the real
backend needs gigabytes on disk and Apple Silicon to do anything at all.

It re-exports `LLMClient` and `LLMTool`, so `ToolDefinition` and `LLMMessage` come with it.

### Layer 1 — `LLMLocalModels`

Everything about model artifacts as *files*: `ModelRegistry`, which records what has been
installed, `AdapterRegistry` for LoRA adapters, and `BackgroundDownloader`.

`BackgroundDownloader` is bookkeeping, not a transfer engine. It tracks which downloads are in
flight and holds resume data in memory, and delegates every actual transfer to a
`BackgroundDownloadDelegate` you must supply — there is no default, because a downloader that moves
no bytes could only ever report success for work nobody did. Whether a download survives app
suspension is therefore a property of that delegate, not of this type. The transfers the package
performs on its own go through `DestinationHubDownloader` in `LLMLocalMLX`.

`LLMLocalModels` is not a package product. You cannot import it directly; its types reach you
re-exported through the umbrella. That is deliberate — model storage is an implementation detail of
the service, and promoting it to a product would freeze it as public API.

### Layer 2 — `LLMLocalMLX`

`MLXBackend`, the concrete implementation of `LLMLocalBackend` on Apple MLX. This is where the
physical constraints live: the GPU cache limit, KV-cache reuse across turns, eager weight loading,
and `MemoryMonitor`.

`MemoryMonitor` does two separate things, and only one of them is automatic. It observes the system
low-memory notification and can unload the resident model in response. Its headroom arithmetic —
`isModelCompatible(_:)` and the recommended context length — is advisory: nothing in the load path
consults it, so a check you do not perform is a check that does not happen.

Import it at the composition root — the one place that constructs the backend and injects it — and
nowhere else.

### Umbrella — `LLMLocal`

`LLMLocalService`, the facade that ties a backend to a model registry, plus `ModelPresets`,
`ModelSwitcher`, and `LocalAgentClient`. It `@_exported import`s the three layers below, so a
single `import LLMLocal` is enough for an app.

`LocalAgentClient` is the bridge outward: it conforms to `swift-llm-client`'s `AgentCapableClient`,
so an on-device model can be dropped into the same agent loop as a cloud provider.

## What is different from a cloud client

The layering answers a different set of problems than a hosted API does.

| Cloud provider | On-device |
|---|---|
| Rate limits and retries | Memory pressure and OS termination |
| Per-token billing | Battery, thermal throttling, and disk space |
| Model always available | Multi-gigabyte download before first use |
| Model version pinned by the vendor | Weights and quantization are your choice, and your storage |
| Reliable tool calling | Tool calling depends on the model and its chat template |

There is no retry policy here because there is no network in the generation path, and no token
budget because nobody is charging. What replaces them is memory discipline. `MLXBackend` keeps
exactly one model resident and unloads the previous one before loading the next, so the danger is
not two models at once — it is one model that is too large for the memory the process is allowed,
which ends in the app being terminated rather than an error being thrown.

## Choosing an import

- An app → `import LLMLocal`.
- A library target or a test → `import LLMLocalClient`, and take the backend by injection.
- The composition root that builds `MLXBackend` → `import LLMLocalMLX`.
