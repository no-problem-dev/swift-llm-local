import LLMLocalClient

/// Recommended model presets for common use cases.
///
/// Each preset is a pre-configured ``ModelSpec`` targeting a specific
/// quantized model from the MLX community.
public enum ModelPresets {

    /// Gemma 2 2B Instruct 4-bit quantized.
    ///
    /// Google's lightweight instruction-tuned model, suitable for
    /// on-device inference with low memory requirements.
    public static let gemma2B = ModelSpec(
        id: "gemma-2-2b-it-4bit",
        base: .huggingFace(id: "mlx-community/gemma-2-2b-it-4bit"),
        adapter: nil,
        contextLength: 8192,
        displayName: "Gemma 2 2B",
        description: "Google's lightweight instruction-tuned model"
    )
}
