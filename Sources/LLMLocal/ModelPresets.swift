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

    /// Qwen3 4B Instruct 2507 4-bit quantized.
    ///
    /// Alibaba's instruction-tuned model with strong multilingual
    /// capabilities. Fits within iPhone 16 Pro memory (~2.3GB).
    public static let qwen3_4B = ModelSpec(
        id: "qwen3-4b-instruct-2507-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 4B Instruct 2507",
        description: "Alibaba's instruction-tuned model optimized for multilingual tasks"
    )

    /// Qwen3 4B Japanese fine-tuned 4-bit quantized.
    ///
    /// Fine-tuned on Japanese instruction data (dolly-15k-ja) using LoRA,
    /// then fused and quantized to 4-bit. Optimized for Japanese on-device inference.
    public static let qwen3_4B_ja = ModelSpec(
        id: "qwen3-4b-ja-4bit",
        base: .huggingFace(id: "taniguchi-kyoichi/Qwen3-4B-Instruct-2507-ja-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 4B 日本語",
        description: "Japanese fine-tuned Qwen3 4B for on-device inference"
    )
}
