import LLMClient
import LLMLocalClient

// swiftlint:disable type_body_length file_length

/// Ready-made specifications for MLX community model builds, grouped by family.
///
/// Every entry names one specific quantization of one specific Hugging Face repository, which is
/// what makes the catalogue useful rather than decorative: the same model at 4-bit and at 6-bit is
/// a different download, a different resident footprint, and a different quality ceiling. First use
/// of a preset pulls gigabytes from Hugging Face into app storage; after that the recurring cost is
/// RAM, because the weights stay resident for as long as the model is loaded.
///
/// ## Reading the memory figures
///
/// Each spec's estimated memory is roughly the quantized weights plus room for the KV cache and
/// runtime. It decides whether a device can run the model at all. On iOS the app is killed by
/// jetsam before physical RAM is exhausted, so the practical ceiling on a phone is a fraction of
/// the RAM figure on the box: presets under about 2 GB are the ones that behave on current iPhones,
/// entries in the 4 GB to 8 GB range assume a Mac or an iPad with headroom, and anything at 12 GB
/// and above is Mac-only — the 17 GB to 22 GB entries want 32 GB of unified memory and the 40 GB
/// entries want 64 GB. Check a candidate against the device with the memory queries on
/// ``LLMLocalService`` rather than reading the numbers by eye.
///
/// ## How the tool-call levels were decided
///
/// The level on each profile is the product of two independent things (verified 2026-06):
/// 1. whether the chat template has a tools branch at all, which is what makes tool definitions
///    visible to the model, and
/// 2. whether the model's output format can be parsed by the tool-call parsers in mlx-swift-lm.
///
/// A model can satisfy the first and fail the second, and is then unsupported in practice: the
/// GPT-OSS harmony channel format and Granite's `<|tool_call|>` markup are both emitted willingly
/// and cannot be read back. Even at the highest level, on-device tool calling is generated text
/// matched against a template rather than a provider-side function-calling API — expect it to be
/// less dependable than a hosted provider, increasingly so at smaller sizes and heavier
/// quantization.
///
/// ## Context length
///
/// Each spec's context length is the model's own maximum, taken from the repository config. It is a
/// limit, not a budget: the KV cache for a long context competes with the weights for the same RAM,
/// so what is actually usable comes from the generation config and the device's memory.
public enum ModelPresets {

    // MARK: - Qwen Family (Alibaba)

    /// Smallest preset at roughly 350 MB, 4-bit — reliable at tool calls, thin on knowledge.
    public static let qwen3_0_6B = ModelSpec(
        id: "qwen3-0.6b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-0.6B-4bit"),
        contextLength: 40_960,
        displayName: "Qwen3 0.6B",
        description: "超軽量モデル。基本的な質問応答やテスト向け",
        estimatedMemoryBytes: 350 * mb,
        profile: ModelProfile(
            summary: "超軽量。テスト・プロトタイプ向け",
            modelFamily: "Qwen",
            parameterCount: "0.6B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: qwenAgentic
    )

    /// 4-bit at roughly 1 GB — the smallest preset with usable Japanese and solid tool calls.
    public static let qwen3_1_7B = ModelSpec(
        id: "qwen3-1.7b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-1.7B-4bit"),
        contextLength: 40_960,
        displayName: "Qwen3 1.7B",
        description: "軽量かつ多言語対応。日本語もサポート",
        estimatedMemoryBytes: 1000 * mb,
        profile: ModelProfile(
            summary: "軽量・多言語対応のバランス型",
            modelFamily: "Qwen",
            parameterCount: "1.7B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    /// Distillation-aware 4-bit at roughly 2.4 GB — plain 4-bit size, less quantization damage.
    ///
    /// Strong at Japanese and code for its footprint, with a 262k context.
    public static let qwen3_4B = ModelSpec(
        id: "qwen3-4b-instruct-2507-4bit-dwq",
        base: .huggingFace(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510"),
        contextLength: 262_144,
        displayName: "Qwen3 4B",
        description: "多言語対応のバランス型モデル。日本語・コード生成に強い",
        estimatedMemoryBytes: 2400 * mb,
        profile: ModelProfile(
            summary: "バランス型。日本語・コード生成に強い",
            modelFamily: "Qwen",
            parameterCount: "4B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit-DWQ",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    /// The 4B base fine-tuned on Japanese, 4-bit at roughly 2.3 GB — best Japanese at this size.
    public static let qwen3_4B_ja = ModelSpec(
        id: "qwen3-4b-ja-4bit",
        base: .huggingFace(id: "taniguchi-kyoichi/Qwen3-4B-Instruct-2507-ja-4bit"),
        contextLength: 262_144,
        displayName: "Qwen3 4B 日本語",
        description: "日本語データでファインチューニング済み。日本語推論に最適化",
        estimatedMemoryBytes: 2300 * mb,
        profile: ModelProfile(
            summary: "日本語 FT 済み。日本語推論に最適化",
            modelFamily: "Qwen",
            parameterCount: "4B",
            toolCallSupport: .excellent,
            japaneseSupport: .excellent,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    /// 4-bit at roughly 4.7 GB — Mac-comfortable quality, with a 40k context rather than 262k.
    public static let qwen3_8B = ModelSpec(
        id: "qwen3-8b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-8B-4bit"),
        contextLength: 40_960,
        displayName: "Qwen3 8B",
        description: "高品質な多言語モデル。日本語対応が特に良好",
        estimatedMemoryBytes: 4700 * mb,
        profile: ModelProfile(
            summary: "高品質な多言語モデル。日本語が良好",
            modelFamily: "Qwen",
            parameterCount: "8B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    // MARK: - Qwen3.5 Family (Alibaba)

    /// Smallest multimodal preset — 4-bit at roughly 700 MB with native image input.
    public static let qwen3_5_0_8B = ModelSpec(
        id: "qwen3.5-0.8b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3.5-0.8B-4bit"),
        contextLength: 262_144,
        displayName: "Qwen3.5 0.8B",
        description: "Qwen3.5 の超軽量モデル。ネイティブマルチモーダル対応",
        estimatedMemoryBytes: 700 * mb,
        profile: ModelProfile(
            summary: "超軽量マルチモーダル。テスト・プロトタイプ向け",
            modelFamily: "Qwen",
            parameterCount: "0.8B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .vision, .code],
            quantization: "4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: qwenAgentic
    )

    /// 6-bit at roughly 2.2 GB with image input — the largest multimodal preset made for a phone.
    ///
    /// Quantized at 6-bit rather than 4-bit because small models lose the most to aggressive
    /// quantization, and the size difference at this scale is small.
    public static let qwen3_5_2B = ModelSpec(
        id: "qwen3.5-2b-6bit",
        base: .huggingFace(id: "mlx-community/Qwen3.5-2B-6bit"),
        contextLength: 262_144,
        displayName: "Qwen3.5 2B",
        description: "軽量マルチモーダル。オンデバイス推論に最適",
        estimatedMemoryBytes: 2200 * mb,
        profile: ModelProfile(
            summary: "軽量マルチモーダル。オンデバイス推論向け",
            modelFamily: "Qwen",
            parameterCount: "2B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .vision, .code],
            quantization: "6bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: qwenAgentic
    )

    /// Standard 6-bit at roughly 4.1 GB with image input — near 4-bit size at better quality.
    public static let qwen3_5_4B = ModelSpec(
        id: "qwen3.5-4b-6bit",
        base: .huggingFace(id: "mlx-community/Qwen3.5-4B-6bit"),
        contextLength: 262_144,
        displayName: "Qwen3.5 4B",
        description: "バランス型マルチモーダル。軽量エージェント向け",
        estimatedMemoryBytes: 4100 * mb,
        profile: ModelProfile(
            summary: "バランス型マルチモーダル。軽量エージェント向け",
            modelFamily: "Qwen",
            parameterCount: "4B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .vision, .code],
            quantization: "6bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    /// 4-bit at roughly 6.4 GB with image input — the best quality that still fits a 16 GB Mac.
    public static let qwen3_5_9B = ModelSpec(
        id: "qwen3.5-9b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3.5-9B-4bit"),
        contextLength: 262_144,
        displayName: "Qwen3.5 9B",
        description: "高品質マルチモーダル。GPT-OSS-120B 超えの報告あり",
        estimatedMemoryBytes: 6400 * mb,
        profile: ModelProfile(
            summary: "高品質マルチモーダル。小型ながら高性能",
            modelFamily: "Qwen",
            parameterCount: "9B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .vision, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    // MARK: - Qwen3.6 Family (Alibaba)

    /// Dense 4-bit at roughly 17 GB — strong at agent work, and needs a 32 GB Mac.
    public static let qwen3_6_27B = ModelSpec(
        id: "qwen3.6-27b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3.6-27B-4bit"),
        contextLength: 262_144,
        displayName: "Qwen3.6 27B",
        description: "前世代フラッグシップ超えの dense モデル。32GB+ RAM の Mac 推奨",
        estimatedMemoryBytes: 17_000 * mb,
        profile: ModelProfile(
            summary: "高品質 dense。エージェントタスクに強い",
            modelFamily: "Qwen",
            parameterCount: "27B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    /// Mixture-of-experts 4-bit at roughly 22 GB with 3B active per token — 32 GB Mac.
    ///
    /// Only the active experts are computed each step, so it generates far faster than its resident
    /// size suggests; the whole 22 GB still has to be in memory.
    public static let qwen3_6_35B_moe = ModelSpec(
        id: "qwen3.6-35b-a3b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3.6-35B-A3B-4bit"),
        contextLength: 262_144,
        displayName: "Qwen3.6 35B-A3B",
        description: "agentic タスク特化の MoE。3B アクティブで高速。32GB+ RAM の Mac 推奨",
        estimatedMemoryBytes: 22_000 * mb,
        profile: ModelProfile(
            summary: "agentic 特化 MoE。3B アクティブで効率的",
            modelFamily: "Qwen",
            parameterCount: "35B-A3B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    // MARK: - Qwen 2.5 / MoE (Alibaba)

    /// Previous-generation 4-bit at roughly 8.5 GB with a 32k context.
    public static let qwen2_5_14B = ModelSpec(
        id: "qwen2.5-14b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Qwen2.5-14B-Instruct-4bit"),
        contextLength: 32_768,
        displayName: "Qwen 2.5 14B",
        description: "高品質な大型モデル。複雑なタスクに対応",
        estimatedMemoryBytes: 8500 * mb,
        profile: ModelProfile(
            summary: "大型・高品質。複雑なタスクに対応",
            modelFamily: "Qwen",
            parameterCount: "14B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    /// Mixture-of-experts 4-bit at roughly 18 GB with 3B active per token — 30B quality, 3B speed.
    public static let qwen3_moe_30B = ModelSpec(
        id: "qwen3-30b-a3b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-30B-A3B-4bit"),
        contextLength: 40_960,
        displayName: "Qwen3 MoE 30B-A3B",
        description: "Mixture-of-Experts。30B パラメータ中 3B をアクティブに使用",
        estimatedMemoryBytes: 18_000 * mb,
        profile: ModelProfile(
            summary: "MoE アーキテクチャ。3B アクティブで効率的",
            modelFamily: "Qwen",
            parameterCount: "30B-A3B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    /// Dense 4-bit at roughly 19 GB with a 32k context — needs a 32 GB Mac.
    public static let qwen2_5_32B = ModelSpec(
        id: "qwen2.5-32b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Qwen2.5-32B-Instruct-4bit"),
        contextLength: 32_768,
        displayName: "Qwen 2.5 32B",
        description: "Mac 向けフラッグシップ。32GB+ RAM 推奨",
        estimatedMemoryBytes: 19_000 * mb,
        profile: ModelProfile(
            summary: "Mac 向けフラッグシップ。高品質",
            modelFamily: "Qwen",
            parameterCount: "32B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: qwenAgentic
    )

    /// Largest preset here — 4-bit at roughly 42 GB, so a 64 GB Mac, and slow even there.
    public static let qwen2_5_72B = ModelSpec(
        id: "qwen2.5-72b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Qwen2.5-72B-Instruct-4bit"),
        contextLength: 32_768,
        displayName: "Qwen 2.5 72B",
        description: "最大級モデル。64GB+ RAM の Mac 専用",
        estimatedMemoryBytes: 42_000 * mb,
        profile: ModelProfile(
            summary: "最大級。64GB+ RAM の Mac 専用",
            modelFamily: "Qwen",
            parameterCount: "72B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .slow
        ),
        recommendedGeneration: qwenAgentic
    )

    // MARK: - Gemma Family (Google)
    //
    // Tool calling fails twice over on Gemma 2/3/3n: their chat templates have no tools branch, so
    // the model never sees the definitions, and the Gemma parser in mlx-swift-lm only covers
    // Gemma 1. Gemma 4 does have native function calling, but its output parser ships only on the
    // main branch of mlx-swift-lm and not in 3.31.3, so those entries are marked basic.

    /// Quantization-aware 4-bit at roughly 800 MB — keeps more quality than post-hoc 4-bit.
    ///
    /// Cannot call tools, and Japanese is basic.
    public static let gemma3_1B_qat = ModelSpec(
        id: "gemma-3-1b-it-qat-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3-1b-it-qat-4bit"),
        contextLength: 32_768,
        displayName: "Gemma 3 1B QAT",
        description: "Google の超軽量モデル。QAT で品質を維持した 4bit 量子化。ツールコール非対応",
        estimatedMemoryBytes: 800 * mb,
        profile: ModelProfile(
            summary: "超軽量・QAT で品質維持",
            modelFamily: "Gemma",
            parameterCount: "1B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "QAT-4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: gemmaAgentic
    )

    /// Quantization-aware 4-bit at roughly 2.5 GB with a 131k context; no tool calling.
    public static let gemma3_4B_qat = ModelSpec(
        id: "gemma-3-4b-it-qat-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3-4b-it-qat-4bit"),
        contextLength: 131_072,
        displayName: "Gemma 3 4B QAT",
        description: "Google の QAT 最適化 4B モデル。高品質な推論。ツールコール非対応",
        estimatedMemoryBytes: 2500 * mb,
        profile: ModelProfile(
            summary: "QAT 最適化。高品質な推論",
            modelFamily: "Gemma",
            parameterCount: "4B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "QAT-4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: gemmaAgentic
    )

    /// Quantization-aware 4-bit at roughly 7 GB; no tool calling.
    public static let gemma3_12B_qat = ModelSpec(
        id: "gemma-3-12b-it-qat-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3-12b-it-qat-4bit"),
        contextLength: 131_072,
        displayName: "Gemma 3 12B QAT",
        description: "Google の 12B モデル。QAT で高品質を維持。ツールコール非対応",
        estimatedMemoryBytes: 7000 * mb,
        profile: ModelProfile(
            summary: "12B QAT。高品質を維持",
            modelFamily: "Gemma",
            parameterCount: "12B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "QAT-4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: gemmaAgentic
    )

    /// Largest Gemma 3 — quantization-aware 4-bit at roughly 16 GB with image input, no tool calls.
    public static let gemma3_27B_qat = ModelSpec(
        id: "gemma-3-27b-it-qat-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3-27b-it-qat-4bit"),
        contextLength: 131_072,
        displayName: "Gemma 3 27B QAT",
        description: "Gemma 3 最大のオープンモデル。全タスクで高品質。ツールコール非対応",
        estimatedMemoryBytes: 16_000 * mb,
        profile: ModelProfile(
            summary: "Gemma 3 最大級。全タスクで高品質",
            modelFamily: "Gemma",
            parameterCount: "27B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text, .vision],
            quantization: "QAT-4bit",
            inferenceSpeed: .slow
        ),
        recommendedGeneration: gemmaAgentic
    )

    /// Mobile-oriented Gemma 4, 4-bit at roughly 3.9 GB — 2B-equivalent compute, better Japanese.
    ///
    /// It has native function calling, but this stack has no parser for the format it answers in.
    public static let gemma4_e2b = ModelSpec(
        id: "gemma-4-e2b-it-4bit",
        base: .huggingFace(id: "mlx-community/gemma-4-e2b-it-4bit"),
        contextLength: 131_072,
        displayName: "Gemma 4 E2B",
        description: "Gemma 4 のモバイル特化バリアント。2B 相当の効率的な推論。"
            + "ネイティブ function calling 対応だが mlx-swift-lm のパーサ収録待ち",
        estimatedMemoryBytes: 3900 * mb,
        profile: ModelProfile(
            summary: "Gemma 4 モバイル特化。2B 相当",
            modelFamily: "Gemma",
            parameterCount: "E2B",
            toolCallSupport: .basic,
            japaneseSupport: .good,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: gemmaAgentic
    )

    /// Mobile-oriented Gemma 4, 4-bit at roughly 5.7 GB — 4B-equivalent compute.
    ///
    /// It has native function calling, but this stack has no parser for the format it answers in.
    public static let gemma4_e4b = ModelSpec(
        id: "gemma-4-e4b-it-4bit",
        base: .huggingFace(id: "mlx-community/gemma-4-e4b-it-4bit"),
        contextLength: 131_072,
        displayName: "Gemma 4 E4B",
        description: "Gemma 4 のモバイル特化バリアント。4B 相当の効率的な推論。"
            + "ネイティブ function calling 対応だが mlx-swift-lm のパーサ収録待ち",
        estimatedMemoryBytes: 5700 * mb,
        profile: ModelProfile(
            summary: "Gemma 4 モバイル特化。4B 相当",
            modelFamily: "Gemma",
            parameterCount: "E4B",
            toolCallSupport: .basic,
            japaneseSupport: .good,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: gemmaAgentic
    )

    // MARK: - Llama Family (Meta)

    /// 4-bit at roughly 700 MB with a 131k context — workable tool calls, weak Japanese.
    public static let llama3_2_1B = ModelSpec(
        id: "llama-3.2-1b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
        contextLength: 131_072,
        displayName: "Llama 3.2 1B",
        description: "Meta の軽量モデル。バランスの良い性能",
        estimatedMemoryBytes: 700 * mb,
        profile: ModelProfile(
            summary: "軽量バランス型",
            modelFamily: "Llama",
            parameterCount: "1B",
            toolCallSupport: .good,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: llamaAgentic
    )

    /// 4-bit at roughly 1.8 GB — the largest Llama that is realistic on a phone.
    public static let llama3_2_3B = ModelSpec(
        id: "llama-3.2-3b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Llama-3.2-3B-Instruct-4bit"),
        contextLength: 131_072,
        displayName: "Llama 3.2 3B",
        description: "Meta の 3B モデル。実用的なオンデバイス性能",
        estimatedMemoryBytes: 1800 * mb,
        profile: ModelProfile(
            summary: "実用的なオンデバイスモデル",
            modelFamily: "Llama",
            parameterCount: "3B",
            toolCallSupport: .good,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: llamaAgentic
    )

    /// 4-bit at roughly 4.5 GB — broad, English-centric coverage with a 131k context.
    public static let llama3_1_8B = ModelSpec(
        id: "llama-3.1-8b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"),
        contextLength: 131_072,
        displayName: "Llama 3.1 8B",
        description: "Meta の定番 8B モデル。幅広いタスクに対応",
        estimatedMemoryBytes: 4500 * mb,
        profile: ModelProfile(
            summary: "定番 8B。幅広いタスクに対応",
            modelFamily: "Llama",
            parameterCount: "8B",
            toolCallSupport: .good,
            japaneseSupport: .basic,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: llamaAgentic
    )

    /// 4-bit at roughly 40 GB — a 64 GB Mac and nothing smaller.
    public static let llama3_3_70B = ModelSpec(
        id: "llama-3.3-70b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Llama-3.3-70B-Instruct-4bit"),
        contextLength: 131_072,
        displayName: "Llama 3.3 70B",
        description: "Meta のフロンティアモデル。64GB+ RAM の Mac 専用",
        estimatedMemoryBytes: 40_000 * mb,
        profile: ModelProfile(
            summary: "フロンティア級。64GB+ RAM 必須",
            modelFamily: "Llama",
            parameterCount: "70B",
            toolCallSupport: .good,
            japaneseSupport: .basic,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .slow
        ),
        recommendedGeneration: llamaAgentic
    )

    // MARK: - Mistral Family

    /// Small agent model with native function calling — 6-bit at roughly 3.7 GB.
    ///
    /// Quantized at 6-bit rather than 4-bit because on a function-calling model the damage shows up
    /// directly as wrong or malformed tool arguments.
    public static let ministral3_3B = ModelSpec(
        id: "ministral-3-3b-instruct-2512-6bit",
        base: .huggingFace(id: "mlx-community/Ministral-3-3B-Instruct-2512-6bit"),
        contextLength: 262_144,
        displayName: "Ministral 3 3B",
        description: "Mistral AI の小型エージェントモデル。ネイティブ function calling 対応",
        estimatedMemoryBytes: 3700 * mb,
        profile: ModelProfile(
            summary: "小型エージェントモデル。FC ネイティブ対応",
            modelFamily: "Mistral",
            parameterCount: "3B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "6bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: mistralAgentic
    )

    /// 4-bit at roughly 6 GB with native function calling and a 262k context.
    public static let ministral3_8B = ModelSpec(
        id: "ministral-3-8b-instruct-2512-4bit",
        base: .huggingFace(id: "mlx-community/Ministral-3-8B-Instruct-2512-4bit"),
        contextLength: 262_144,
        displayName: "Ministral 3 8B",
        description: "Mistral AI の 8B エージェントモデル。ネイティブ function calling 対応",
        estimatedMemoryBytes: 6000 * mb,
        profile: ModelProfile(
            summary: "高品質エージェントモデル。FC ネイティブ対応",
            modelFamily: "Mistral",
            parameterCount: "8B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: mistralAgentic
    )

    // MARK: - DeepSeek Family

    /// Reasoning distillation, 4-bit at roughly 900 MB — always thinks, cannot call tools.
    public static let deepseekR1_1_5B = ModelSpec(
        id: "deepseek-r1-distill-qwen-1.5b-4bit",
        base: .huggingFace(id: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit"),
        contextLength: 131_072,
        displayName: "DeepSeek R1 1.5B",
        description: "推論能力を蒸留した軽量モデル",
        estimatedMemoryBytes: 900 * mb,
        profile: ModelProfile(
            summary: "推論特化の蒸留モデル",
            modelFamily: "DeepSeek",
            parameterCount: "1.5B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: deepseekReasoning
    )

    /// Reasoning distillation, 4-bit at roughly 4.1 GB; no tool calling.
    public static let deepseekR1_7B = ModelSpec(
        id: "deepseek-r1-distill-qwen-7b-4bit",
        base: .huggingFace(id: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit"),
        contextLength: 131_072,
        displayName: "DeepSeek R1 7B",
        description: "推論能力に優れた 7B モデル",
        estimatedMemoryBytes: 4100 * mb,
        profile: ModelProfile(
            summary: "推論特化 7B",
            modelFamily: "DeepSeek",
            parameterCount: "7B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: deepseekReasoning
    )

    /// Reasoning distillation, 4-bit at roughly 8.5 GB; no tool calling.
    public static let deepseekR1_14B = ModelSpec(
        id: "deepseek-r1-distill-qwen-14b-4bit",
        base: .huggingFace(id: "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"),
        contextLength: 131_072,
        displayName: "DeepSeek R1 14B",
        description: "高品質な推論特化モデル",
        estimatedMemoryBytes: 8500 * mb,
        profile: ModelProfile(
            summary: "高品質な推論特化",
            modelFamily: "DeepSeek",
            parameterCount: "14B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: deepseekReasoning
    )

    // MARK: - Phi Family (Microsoft)

    /// 4-bit at roughly 2.3 GB — strong reasoning for the size, but no tool calling.
    ///
    /// The chat template does render tools, so the model will attempt calls; they arrive in the
    /// `<|tool_call|>` functools markup, which mlx-swift-lm has no parser for, so nothing can be
    /// recovered from them.
    public static let phi4_mini = ModelSpec(
        id: "phi-4-mini-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Phi-4-mini-instruct-4bit"),
        contextLength: 131_072,
        displayName: "Phi-4 Mini",
        description: "Microsoft の小型モデル。改良された推論能力。ツールコール非対応",
        estimatedMemoryBytes: 2300 * mb,
        profile: ModelProfile(
            summary: "小型・推論能力が高い",
            modelFamily: "Phi",
            parameterCount: "3.8B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: phiAgentic
    )

    // MARK: - SmolLM Family (Hugging Face)

    /// 4-bit at roughly 1.8 GB with a 64k context — tool calls work, Japanese does not.
    public static let smolLM3_3B = ModelSpec(
        id: "smollm3-3b-4bit",
        base: .huggingFace(id: "mlx-community/SmolLM3-3B-4bit"),
        contextLength: 65_536,
        displayName: "SmolLM3 3B",
        description: "Hugging Face の効率的な 3B モデル。ツールコール対応",
        estimatedMemoryBytes: 1800 * mb,
        profile: ModelProfile(
            summary: "効率的な 3B モデル",
            modelFamily: "SmolLM",
            parameterCount: "3B",
            toolCallSupport: .good,
            japaneseSupport: .unsupported,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: smolAgentic
    )

    // MARK: - LFM Family (Liquid AI)

    /// 6-bit at roughly 1 GB — built for tool use, and the fastest generation of the small presets.
    public static let lfm2_5_1_2B = ModelSpec(
        id: "lfm2.5-1.2b-instruct-6bit",
        base: .huggingFace(id: "mlx-community/LFM2.5-1.2B-Instruct-6bit"),
        contextLength: 128_000,
        displayName: "LFM2.5 1.2B",
        description: "Liquid AI のツール特化 SLM。トークン生成が特に高速",
        estimatedMemoryBytes: 1000 * mb,
        profile: ModelProfile(
            summary: "ツール特化の超高速 SLM",
            modelFamily: "LFM",
            parameterCount: "1.2B",
            toolCallSupport: .excellent,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "6bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: lfmAgentic
    )

    /// Mixture-of-experts 4-bit at roughly 4.9 GB with 1B active — small-model speed, 8B knowledge.
    public static let lfm2_5_8B_a1b = ModelSpec(
        id: "lfm2.5-8b-a1b-4bit",
        base: .huggingFace(id: "mlx-community/LFM2.5-8B-A1B-MLX-4bit"),
        contextLength: 128_000,
        displayName: "LFM2.5 8B-A1B",
        description: "Liquid AI の MoE。1B アクティブで高速ながら 8B 級の知識・ツール性能",
        estimatedMemoryBytes: 4900 * mb,
        profile: ModelProfile(
            summary: "MoE。1.2B 速度で 8B 級品質",
            modelFamily: "LFM",
            parameterCount: "8B-A1B",
            toolCallSupport: .excellent,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: lfmAgentic
    )

    /// Japanese-specialized 4-bit at roughly 750 MB — the strongest Japanese per byte here.
    ///
    /// Published by Liquid AI as an MLX build rather than converted by the community.
    public static let lfm2_5_1_2B_ja = ModelSpec(
        id: "lfm2.5-1.2b-jp-4bit",
        base: .huggingFace(id: "LiquidAI/LFM2.5-1.2B-JP-202606-MLX-4bit"),
        contextLength: 128_000,
        displayName: "LFM2.5 1.2B 日本語",
        description: "Liquid AI の日本語特化版。日本語の軽量タスクに最適",
        estimatedMemoryBytes: 750 * mb,
        profile: ModelProfile(
            summary: "日本語特化の超高速 SLM",
            modelFamily: "LFM",
            parameterCount: "1.2B",
            toolCallSupport: .good,
            japaneseSupport: .excellent,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .fast
        ),
        recommendedGeneration: lfmAgentic
    )

    // MARK: - GLM Family (Zhipu AI)

    /// Mixture-of-experts 4-bit at roughly 18 GB with 3B active — coding and agent work, 32 GB Mac.
    public static let glm4_7_flash = ModelSpec(
        id: "glm-4.7-flash-4bit",
        base: .huggingFace(id: "mlx-community/GLM-4.7-Flash-4bit"),
        contextLength: 202_752,
        displayName: "GLM-4.7 Flash",
        description: "Zhipu AI の 30B-A3B MoE。コーディング・エージェントに強い。32GB+ RAM の Mac 推奨",
        estimatedMemoryBytes: 18_000 * mb,
        profile: ModelProfile(
            summary: "コーディング/エージェント特化 MoE",
            modelFamily: "GLM",
            parameterCount: "30B-A3B",
            toolCallSupport: .excellent,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: glmAgentic
    )

    // MARK: - Other Models

    /// 4-bit at roughly 1.2 GB — enterprise-oriented, and no tool calling.
    ///
    /// The chat template does render tools, but the model answers with `<|tool_call|>` followed by
    /// a JSON list, a shape mlx-swift-lm has no parser for, so the calls cannot be recovered.
    public static let granite3_3_2B = ModelSpec(
        id: "granite-3.3-2b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/granite-3.3-2b-instruct-4bit"),
        contextLength: 131_072,
        displayName: "Granite 3.3 2B",
        description: "IBM のエンタープライズ向け軽量モデル。ツールコール非対応",
        estimatedMemoryBytes: 1200 * mb,
        profile: ModelProfile(
            summary: "エンタープライズ向け軽量モデル",
            modelFamily: "Granite",
            parameterCount: "2B",
            toolCallSupport: .unsupported,
            japaneseSupport: .basic,
            modalities: [.text],
            quantization: "4bit",
            inferenceSpeed: .medium
        ),
        recommendedGeneration: graniteAgentic
    )

    /// Mixed MXFP4 and Q8 at roughly 12 GB — notably good Japanese, but no tool calling.
    ///
    /// Calls are emitted in the harmony format, addressed to a channel
    /// (`<|channel|>commentary to=functions.x`) rather than as a JSON block, and mlx-swift-lm has no
    /// parser for it, so tools cannot be used with this model.
    public static let gptOSS_20B = ModelSpec(
        id: "gpt-oss-20b-mxfp4-q8",
        base: .huggingFace(id: "mlx-community/gpt-oss-20b-MXFP4-Q8"),
        contextLength: 131_072,
        displayName: "GPT-OSS 20B",
        description: "OpenAI のオープンソースモデル。高い日本語性能。ツールコール非対応",
        estimatedMemoryBytes: 12_000 * mb,
        profile: ModelProfile(
            summary: "OpenAI OSS。高い日本語性能",
            modelFamily: "GPT-OSS",
            parameterCount: "20B",
            toolCallSupport: .unsupported,
            japaneseSupport: .good,
            modalities: [.text, .code],
            quantization: "MXFP4-Q8",
            inferenceSpeed: .slow
        ),
        recommendedGeneration: gptOssReasoning
    )

    // MARK: - All Models

    /// Every preset, ordered by estimated memory from smallest to largest.
    ///
    /// Pass it to the download inventory to learn which models are already on disk, and filter it
    /// against the device's memory budget to build a picker that only offers models this machine
    /// can actually load.
    public static let all: [ModelSpec] = [
        // Tiny (< 1GB)
        qwen3_0_6B,
        llama3_2_1B,
        qwen3_5_0_8B,
        lfm2_5_1_2B_ja,
        gemma3_1B_qat,
        deepseekR1_1_5B,
        lfm2_5_1_2B,
        qwen3_1_7B,
        granite3_3_2B,
        llama3_2_3B,
        smolLM3_3B,
        qwen3_5_2B,
        phi4_mini,
        qwen3_4B_ja,
        qwen3_4B,
        gemma3_4B_qat,
        ministral3_3B,
        gemma4_e2b,
        deepseekR1_7B,
        qwen3_5_4B,
        llama3_1_8B,
        qwen3_8B,
        lfm2_5_8B_a1b,
        gemma4_e4b,
        ministral3_8B,
        qwen3_5_9B,
        gemma3_12B_qat,
        deepseekR1_14B,
        qwen2_5_14B,
        gptOSS_20B,
        gemma3_27B_qat,
        qwen3_6_27B,
        glm4_7_flash,
        qwen3_moe_30B,
        qwen2_5_32B,
        qwen3_6_35B_moe,
        llama3_3_70B,
        qwen2_5_72B,
    ]

    // MARK: - Recommended Generation (per family)
    //
    // Tuned for agent and tool-calling use: thinking off for latency, sampling close to each model
    // card's published recommendation. Callers override only the token limit and the temperature.

    /// Qwen's published sampling (topP 0.8, topK 20) with thinking off.
    ///
    /// Qwen3.5 has thinking on by default; turning it off is what keeps even the 4B responsive on a
    /// device, since every thinking token is generated at the same speed as an answer token.
    private static let qwenAgentic = GenerationConfig(
        temperature: 0.7, topP: 0.8, topK: 20, enableThinking: false
    )

    /// Liquid AI's recommendation for LFM2: low temperature, min-p, and a mild repetition penalty.
    private static let lfmAgentic = GenerationConfig(
        temperature: 0.3, minP: 0.15, repetitionPenalty: 1.05, enableThinking: false
    )

    /// Near-deterministic sampling for Mistral and Ministral, where function calls degrade with heat.
    private static let mistralAgentic = GenerationConfig(
        temperature: 0.15, topP: 1.0, enableThinking: false
    )

    /// Google's published Gemma 3 and 4 sampling (temperature 1.0, topK 64, topP 0.95).
    ///
    /// Gemma has no thinking mode, so the thinking flag has nothing to switch and is left off for
    /// consistency with the other families.
    private static let gemmaAgentic = GenerationConfig(
        temperature: 1.0, topP: 0.95, topK: 64, enableThinking: false
    )

    /// Meta's published generation config for Llama 3.x (temperature 0.6, topP 0.9); no thinking mode.
    private static let llamaAgentic = GenerationConfig(
        temperature: 0.6, topP: 0.9, enableThinking: false
    )

    /// Microsoft's sampling for Phi (temperature 0.8, topP 0.95); Phi-4-mini has no thinking mode.
    private static let phiAgentic = GenerationConfig(
        temperature: 0.8, topP: 0.95, enableThinking: false
    )

    /// Hugging Face's recommended SmolLM3 sampling (temperature 0.6, topP 0.95), thinking off.
    ///
    /// SmolLM3's hybrid thinking is on by default, so agent use asks for the no-think path
    /// explicitly rather than paying for reasoning tokens on every tool decision.
    private static let smolAgentic = GenerationConfig(
        temperature: 0.6, topP: 0.95, enableThinking: false
    )

    /// Zhipu's sampling for GLM (temperature 0.6, topP 0.95) with thinking off.
    private static let glmAgentic = GenerationConfig(
        temperature: 0.6, topP: 0.95, enableThinking: false
    )

    /// IBM Granite: modest temperature for stable output, thinking off.
    private static let graniteAgentic = GenerationConfig(
        temperature: 0.7, topP: 0.95, enableThinking: false
    )

    // MARK: - Recommended Generation (reasoning models)
    //
    // The settings below belong to models whose quality comes from thinking. Switching thinking off
    // guts them, so the flag stays on and only the published sampling is applied. No preset in this
    // catalogue is left on the default generation config, reasoning models included.

    /// DeepSeek-R1's published sampling (temperature 0.6, topP 0.95) with thinking on.
    ///
    /// The R1 chat template has no branch for suppressing thinking, so reasoning tokens are always
    /// generated and always paid for in latency. DeepSeek also recommends running R1 without a
    /// system prompt, which is the caller's decision rather than this configuration's.
    private static let deepseekReasoning = GenerationConfig(
        temperature: 0.6, topP: 0.95, enableThinking: true
    )

    /// GPT-OSS sampling close to the published defaults, with thinking on.
    ///
    /// Harmony controls reasoning depth through a reasoning-effort line in the system message rather
    /// than a template flag, so the thinking flag here has nothing to switch off.
    private static let gptOssReasoning = GenerationConfig(
        temperature: 1.0, topP: 1.0, enableThinking: true
    )

    // MARK: - Private Helpers

    /// One mebibyte in bytes, the unit the memory estimates above are written in.
    private static let mb: UInt64 = 1024 * 1024
}

// swiftlint:enable type_body_length file_length
