import Foundation
import LLMClient

/// Everything needed to identify a model, find its weights, and generate with it sensibly.
///
/// A spec is a description, not a handle: creating one downloads nothing and loads nothing. It is
/// what callers pass to a backend, a switcher, or the download inventory, and it is the only thing
/// those layers know about a model.
///
/// Identity is read two different ways, which matters when specs are edited at runtime. The
/// switcher and the registry key on ``id``, so two specs sharing an id are the same model to them.
/// A backend compares the whole value, so changing any field — even ``recommendedGeneration`` —
/// makes the spec unequal to the resident one and forces a reload on the next call.
public struct ModelSpec: Sendable, Hashable, Codable {
    /// Stable identifier for this model, used as the key by the registry, switcher, and inventory.
    public let id: String

    /// Where the base weights come from.
    public let base: ModelSource

    /// LoRA/QLoRA adapter applied on top of the base weights, or `nil` for the base model alone.
    ///
    /// Loading a spec with an adapter requires the backend to have an ``AdapterResolving`` instance;
    /// without one the load fails with ``LLMLocalError/adapterMergeFailed(reason:)`` rather than
    /// quietly running the base model.
    public let adapter: AdapterSource?

    /// Context window the model was trained for, in tokens.
    ///
    /// This is advisory metadata copied from the model's own configuration. Nothing in this package
    /// truncates or rejects a prompt against it — the runtime limits that actually bite are
    /// ``GenerationConfig/maxKVSize`` and device memory.
    public let contextLength: Int

    /// Name to show in a picker or a title.
    public let displayName: String

    /// One-line description for the same UI as the display name.
    public let description: String

    /// Rough memory the model occupies while generating, in bytes.
    ///
    /// It covers the quantized weights plus KV cache and runtime overhead, so it is larger than the
    /// download size and only close enough for admission decisions: comparing it against available
    /// memory before loading, and sorting models into ``ModelSizeTier``.
    public let estimatedMemoryBytes: UInt64

    /// What the model is good at — tool calling, languages, modalities, quantization.
    ///
    /// Used to filter candidates before a load, most importantly to avoid handing tools to a model
    /// whose output format cannot be parsed back into tool calls.
    public let profile: ModelProfile?

    /// Sampling, KV cache, and thinking settings this model actually works well with.
    ///
    /// It carries the model card's recommended sampling and any speed-first choices for agent use,
    /// so callers should start from this value and override only what the call needs, such as
    /// ``GenerationConfig/maxTokens``. Starting from ``GenerationConfig/default`` instead silently
    /// discards the per-model tuning.
    public let recommendedGeneration: GenerationConfig

    /// Describes a model without fetching or loading anything.
    ///
    /// - Parameters:
    ///   - id: Stable identifier for this model.
    ///   - base: Where the base weights come from.
    ///   - adapter: LoRA/QLoRA adapter to apply, or `nil` for the base model alone.
    ///   - contextLength: Context window the model was trained for, in tokens.
    ///   - displayName: Name to show in a picker or a title.
    ///   - description: One-line description for the same UI.
    ///   - estimatedMemoryBytes: Rough memory occupied while generating, in bytes.
    ///   - profile: Capability profile used to filter candidates, or `nil` when unknown.
    ///   - recommendedGeneration: Settings this model works well with.
    public init(
        id: String,
        base: ModelSource,
        adapter: AdapterSource? = nil,
        contextLength: Int,
        displayName: String,
        description: String,
        estimatedMemoryBytes: UInt64,
        profile: ModelProfile? = nil,
        recommendedGeneration: GenerationConfig = .default
    ) {
        self.id = id
        self.base = base
        self.adapter = adapter
        self.contextLength = contextLength
        self.displayName = displayName
        self.description = description
        self.estimatedMemoryBytes = estimatedMemoryBytes
        self.profile = profile
        self.recommendedGeneration = recommendedGeneration
    }
}

extension ModelSpec {
    /// Estimated memory footprint formatted for display, such as "2.3 GB".
    ///
    /// Uses the memory count style, so the number is what the model will occupy while running, not
    /// what it takes on disk — compare with `DownloadedModel.formattedSize` for the latter.
    public var formattedMemorySize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(estimatedMemoryBytes))
    }
}
