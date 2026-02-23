import LLMLocalClient

/// 一般的なユースケース向けの推奨モデルプリセット
///
/// 各プリセットは MLX コミュニティの特定の量子化モデルを対象とした
/// 事前設定済みの ``ModelSpec`` です。
public enum ModelPresets {

    /// Gemma 2 2B Instruct 4bit 量子化。
    ///
    /// Google の軽量な命令チューニング済みモデル。
    /// 低メモリ要件でのオンデバイス推論に適しています。
    public static let gemma2B = ModelSpec(
        id: "gemma-2-2b-it-4bit",
        base: .huggingFace(id: "mlx-community/gemma-2-2b-it-4bit"),
        adapter: nil,
        contextLength: 8192,
        displayName: "Gemma 2 2B",
        description: "Google's lightweight instruction-tuned model"
    )

    /// Qwen3 4B Instruct 2507 4bit 量子化。
    ///
    /// Alibaba の命令チューニング済みモデル。強力な多言語対応能力を持ち、
    /// iPhone 16 Pro のメモリ内に収まります（約2.3GB）。
    public static let qwen3_4B = ModelSpec(
        id: "qwen3-4b-instruct-2507-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 4B Instruct 2507",
        description: "Alibaba's instruction-tuned model optimized for multilingual tasks"
    )

    /// Qwen3 4B 日本語ファインチューニング済み 4bit 量子化。
    ///
    /// 日本語命令データ（dolly-15k-ja）で LoRA を使用してファインチューニングし、
    /// 融合後 4bit に量子化。日本語のオンデバイス推論に最適化されています。
    public static let qwen3_4B_ja = ModelSpec(
        id: "qwen3-4b-ja-4bit",
        base: .huggingFace(id: "taniguchi-kyoichi/Qwen3-4B-Instruct-2507-ja-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 4B 日本語",
        description: "Japanese fine-tuned Qwen3 4B for on-device inference"
    )
}
