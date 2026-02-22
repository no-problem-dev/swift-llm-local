import Foundation

/// Describes a model configuration including its source, optional adapter, and metadata.
public struct ModelSpec: Sendable, Hashable, Codable {
    /// Unique identifier for this model specification.
    public let id: String

    /// Where the base model weights are located.
    public let base: ModelSource

    /// Optional LoRA/QLoRA adapter to apply on top of the base model.
    public let adapter: AdapterSource?

    /// Maximum context length in tokens.
    public let contextLength: Int

    /// Human-readable display name.
    public let displayName: String

    /// Human-readable description of the model.
    public let description: String

    /// Creates a new model specification.
    /// - Parameters:
    ///   - id: Unique identifier for this model specification.
    ///   - base: Where the base model weights are located.
    ///   - adapter: Optional LoRA/QLoRA adapter. Defaults to `nil`.
    ///   - contextLength: Maximum context length in tokens.
    ///   - displayName: Human-readable display name.
    ///   - description: Human-readable description of the model.
    public init(
        id: String,
        base: ModelSource,
        adapter: AdapterSource? = nil,
        contextLength: Int,
        displayName: String,
        description: String
    ) {
        self.id = id
        self.base = base
        self.adapter = adapter
        self.contextLength = contextLength
        self.displayName = displayName
        self.description = description
    }
}
