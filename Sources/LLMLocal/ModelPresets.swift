import LLMLocalClient

// swiftlint:disable type_body_length

/// MLX コミュニティの推奨モデルプリセット
///
/// 各プリセットは mlx-community（Hugging Face）の特定の量子化モデルを対象とした
/// 事前設定済みの ``ModelSpec`` です。ファミリー別に整理されています。
public enum ModelPresets {

    // MARK: - Qwen Family (Alibaba)

    /// Qwen3 0.6B 4bit — 超軽量・基本タスク向け
    public static let qwen3_0_6B = ModelSpec(
        id: "qwen3-0.6b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-0.6B-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 0.6B",
        description: "超軽量モデル。基本的な質問応答やテスト向け",
        estimatedMemoryBytes: 350 * mb
    )

    /// Qwen3 1.7B 4bit — 軽量・多言語対応
    public static let qwen3_1_7B = ModelSpec(
        id: "qwen3-1.7b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-1.7B-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 1.7B",
        description: "軽量かつ多言語対応。日本語もサポート",
        estimatedMemoryBytes: 1000 * mb
    )

    /// Qwen3 4B Instruct 2507 4bit — バランス型・多言語
    public static let qwen3_4B = ModelSpec(
        id: "qwen3-4b-instruct-2507-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 4B",
        description: "多言語対応のバランス型モデル。日本語・コード生成に強い",
        estimatedMemoryBytes: 2300 * mb
    )

    /// Qwen3 4B 日本語ファインチューニング済み 4bit
    public static let qwen3_4B_ja = ModelSpec(
        id: "qwen3-4b-ja-4bit",
        base: .huggingFace(id: "taniguchi-kyoichi/Qwen3-4B-Instruct-2507-ja-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 4B 日本語",
        description: "日本語データでファインチューニング済み。日本語推論に最適化",
        estimatedMemoryBytes: 2300 * mb
    )

    /// Qwen3 8B 4bit — 高品質・多言語
    public static let qwen3_8B = ModelSpec(
        id: "qwen3-8b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-8B-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 8B",
        description: "高品質な多言語モデル。日本語対応が特に良好",
        estimatedMemoryBytes: 4700 * mb
    )

    /// Qwen 2.5 14B Instruct 4bit — 大型・高品質
    public static let qwen2_5_14B = ModelSpec(
        id: "qwen2.5-14b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Qwen2.5-14B-Instruct-4bit"),
        contextLength: 4096,
        displayName: "Qwen 2.5 14B",
        description: "高品質な大型モデル。複雑なタスクに対応",
        estimatedMemoryBytes: 8500 * mb
    )

    /// Qwen3 MoE 30B-A3B 4bit — MoE 高品質（3B アクティブ）
    public static let qwen3_moe_30B = ModelSpec(
        id: "qwen3-30b-a3b-4bit",
        base: .huggingFace(id: "mlx-community/Qwen3-30B-A3B-4bit"),
        contextLength: 4096,
        displayName: "Qwen3 MoE 30B-A3B",
        description: "Mixture-of-Experts。30B パラメータ中 3B をアクティブに使用",
        estimatedMemoryBytes: 18_000 * mb
    )

    /// Qwen 2.5 32B Instruct 4bit — Mac 向けフラッグシップ
    public static let qwen2_5_32B = ModelSpec(
        id: "qwen2.5-32b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Qwen2.5-32B-Instruct-4bit"),
        contextLength: 4096,
        displayName: "Qwen 2.5 32B",
        description: "Mac 向けフラッグシップ。32GB+ RAM 推奨",
        estimatedMemoryBytes: 19_000 * mb
    )

    /// Qwen 2.5 72B Instruct 4bit — 最大級
    public static let qwen2_5_72B = ModelSpec(
        id: "qwen2.5-72b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Qwen2.5-72B-Instruct-4bit"),
        contextLength: 4096,
        displayName: "Qwen 2.5 72B",
        description: "最大級モデル。64GB+ RAM の Mac 専用",
        estimatedMemoryBytes: 42_000 * mb
    )

    // MARK: - Gemma Family (Google)

    /// Gemma 3 1B QAT 4bit — 超軽量・高品質 QAT
    public static let gemma3_1B_qat = ModelSpec(
        id: "gemma-3-1b-it-qat-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3-1b-it-qat-4bit"),
        contextLength: 8192,
        displayName: "Gemma 3 1B QAT",
        description: "Google の超軽量モデル。QAT で品質を維持した 4bit 量子化",
        estimatedMemoryBytes: 800 * mb
    )

    /// Gemma 2 2B Instruct 4bit — 軽量・汎用
    public static let gemma2_2B = ModelSpec(
        id: "gemma-2-2b-it-4bit",
        base: .huggingFace(id: "mlx-community/gemma-2-2b-it-4bit"),
        contextLength: 8192,
        displayName: "Gemma 2 2B",
        description: "Google の軽量汎用モデル。幅広いタスクに対応",
        estimatedMemoryBytes: 1400 * mb
    )

    /// Gemma 3n E2B 4bit — モバイル特化（2B 相当）
    public static let gemma3n_e2b = ModelSpec(
        id: "gemma-3n-e2b-it-lm-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3n-E2B-it-lm-4bit"),
        contextLength: 8192,
        displayName: "Gemma 3n E2B",
        description: "モバイル特化の Nano バリアント。2B 相当の効率的な推論",
        estimatedMemoryBytes: 1200 * mb
    )

    /// Gemma 3n E4B 4bit — モバイル特化（4B 相当）
    public static let gemma3n_e4b = ModelSpec(
        id: "gemma-3n-e4b-it-lm-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3n-E4B-it-lm-4bit"),
        contextLength: 8192,
        displayName: "Gemma 3n E4B",
        description: "モバイル特化の Nano バリアント。4B 相当の効率的な推論",
        estimatedMemoryBytes: 2300 * mb
    )

    /// Gemma 3 4B QAT 4bit — VLM 対応
    public static let gemma3_4B_qat = ModelSpec(
        id: "gemma-3-4b-it-qat-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3-4b-it-qat-4bit"),
        contextLength: 8192,
        displayName: "Gemma 3 4B QAT",
        description: "Google の QAT 最適化 4B モデル。高品質な推論",
        estimatedMemoryBytes: 2500 * mb
    )

    /// Gemma 2 9B Instruct 4bit — 高品質
    public static let gemma2_9B = ModelSpec(
        id: "gemma-2-9b-it-4bit",
        base: .huggingFace(id: "mlx-community/gemma-2-9b-it-4bit"),
        contextLength: 8192,
        displayName: "Gemma 2 9B",
        description: "Google の高品質 9B モデル。多言語対応",
        estimatedMemoryBytes: 5300 * mb
    )

    /// Gemma 3 12B QAT 4bit — 大型・高品質
    public static let gemma3_12B_qat = ModelSpec(
        id: "gemma-3-12b-it-qat-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3-12b-it-qat-4bit"),
        contextLength: 8192,
        displayName: "Gemma 3 12B QAT",
        description: "Google の最新 12B モデル。QAT で高品質を維持",
        estimatedMemoryBytes: 7000 * mb
    )

    /// Gemma 3 27B QAT 4bit — Google 最大級
    public static let gemma3_27B_qat = ModelSpec(
        id: "gemma-3-27b-it-qat-4bit",
        base: .huggingFace(id: "mlx-community/gemma-3-27b-it-qat-4bit"),
        contextLength: 8192,
        displayName: "Gemma 3 27B QAT",
        description: "Google 最大のオープンモデル。全タスクで高品質",
        estimatedMemoryBytes: 16_000 * mb
    )

    // MARK: - Llama Family (Meta)

    /// Llama 3.2 1B Instruct 4bit — 軽量・バランス型
    public static let llama3_2_1B = ModelSpec(
        id: "llama-3.2-1b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
        contextLength: 8192,
        displayName: "Llama 3.2 1B",
        description: "Meta の軽量モデル。バランスの良い性能",
        estimatedMemoryBytes: 700 * mb
    )

    /// Llama 3.2 3B Instruct 4bit — 実用的
    public static let llama3_2_3B = ModelSpec(
        id: "llama-3.2-3b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Llama-3.2-3B-Instruct-4bit"),
        contextLength: 8192,
        displayName: "Llama 3.2 3B",
        description: "Meta の 3B モデル。実用的なオンデバイス性能",
        estimatedMemoryBytes: 1800 * mb
    )

    /// Llama 3.1 8B Instruct 4bit — 定番
    public static let llama3_1_8B = ModelSpec(
        id: "llama-3.1-8b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"),
        contextLength: 8192,
        displayName: "Llama 3.1 8B",
        description: "Meta の定番 8B モデル。幅広いタスクに対応",
        estimatedMemoryBytes: 4500 * mb
    )

    /// Llama 3.3 70B Instruct 4bit — フロンティア
    public static let llama3_3_70B = ModelSpec(
        id: "llama-3.3-70b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Llama-3.3-70B-Instruct-4bit"),
        contextLength: 8192,
        displayName: "Llama 3.3 70B",
        description: "Meta のフロンティアモデル。64GB+ RAM の Mac 専用",
        estimatedMemoryBytes: 40_000 * mb
    )

    // MARK: - Mistral Family

    /// Mistral 7B Instruct v0.3 4bit — 汎用
    public static let mistral7B = ModelSpec(
        id: "mistral-7b-instruct-v03-4bit",
        base: .huggingFace(id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit"),
        contextLength: 8192,
        displayName: "Mistral 7B v0.3",
        description: "Mistral AI の定番汎用モデル",
        estimatedMemoryBytes: 4100 * mb
    )

    /// Mistral Small 24B Instruct 4bit — 高品質
    public static let mistralSmall24B = ModelSpec(
        id: "mistral-small-24b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Mistral-Small-24B-Instruct-2501-4bit"),
        contextLength: 8192,
        displayName: "Mistral Small 24B",
        description: "Mistral AI の効率的な 24B モデル",
        estimatedMemoryBytes: 14_000 * mb
    )

    // MARK: - DeepSeek Family

    /// DeepSeek R1 Distill Qwen 1.5B 4bit — 軽量推論特化
    public static let deepseekR1_1_5B = ModelSpec(
        id: "deepseek-r1-distill-qwen-1.5b-4bit",
        base: .huggingFace(id: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit"),
        contextLength: 4096,
        displayName: "DeepSeek R1 1.5B",
        description: "推論能力を蒸留した軽量モデル",
        estimatedMemoryBytes: 900 * mb
    )

    /// DeepSeek R1 Distill Qwen 7B 4bit — 推論特化
    public static let deepseekR1_7B = ModelSpec(
        id: "deepseek-r1-distill-qwen-7b-4bit",
        base: .huggingFace(id: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit"),
        contextLength: 4096,
        displayName: "DeepSeek R1 7B",
        description: "推論能力に優れた 7B モデル",
        estimatedMemoryBytes: 4100 * mb
    )

    /// DeepSeek R1 Distill Qwen 14B 4bit — 高品質推論
    public static let deepseekR1_14B = ModelSpec(
        id: "deepseek-r1-distill-qwen-14b-4bit",
        base: .huggingFace(id: "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"),
        contextLength: 4096,
        displayName: "DeepSeek R1 14B",
        description: "高品質な推論特化モデル",
        estimatedMemoryBytes: 8500 * mb
    )

    /// DeepSeek R1 Distill Llama 70B 4bit — 最大級推論
    public static let deepseekR1_70B = ModelSpec(
        id: "deepseek-r1-distill-llama-70b-4bit",
        base: .huggingFace(id: "mlx-community/DeepSeek-R1-Distill-Llama-70B-4bit"),
        contextLength: 4096,
        displayName: "DeepSeek R1 70B",
        description: "最大級の推論特化モデル。64GB+ RAM の Mac 専用",
        estimatedMemoryBytes: 40_000 * mb
    )

    // MARK: - Phi Family (Microsoft)

    /// Phi-3.5 Mini Instruct 4bit — 小型・推論特化
    public static let phi3_5_mini = ModelSpec(
        id: "phi-3.5-mini-instruct-4bit",
        base: .huggingFace(id: "mlx-community/Phi-3.5-mini-instruct-4bit"),
        contextLength: 4096,
        displayName: "Phi-3.5 Mini",
        description: "Microsoft の小型モデル。推論能力が高い",
        estimatedMemoryBytes: 2300 * mb
    )

    /// Phi-4 Mini Instruct 4bit — 最新・高推論
    public static let phi4_mini = ModelSpec(
        id: "phi-4-mini-instruct-4bit",
        base: .huggingFace(id: "mlx-community/phi-4-mini-instruct-4bit"),
        contextLength: 4096,
        displayName: "Phi-4 Mini",
        description: "Microsoft の最新小型モデル。改良された推論能力",
        estimatedMemoryBytes: 2300 * mb
    )

    // MARK: - SmolLM Family (Hugging Face)

    /// SmolLM2 135M Instruct 4bit — 超軽量・テスト向け
    public static let smolLM_135M = ModelSpec(
        id: "smollm2-135m-instruct-4bit",
        base: .huggingFace(id: "mlx-community/SmolLM2-135M-Instruct-4bit"),
        contextLength: 2048,
        displayName: "SmolLM2 135M",
        description: "超軽量モデル。動作確認やテスト向け",
        estimatedMemoryBytes: 100 * mb
    )

    /// SmolLM3 3B 4bit — 軽量効率型
    public static let smolLM3_3B = ModelSpec(
        id: "smollm3-3b-4bit",
        base: .huggingFace(id: "mlx-community/SmolLM3-3B-4bit"),
        contextLength: 4096,
        displayName: "SmolLM3 3B",
        description: "Hugging Face の効率的な 3B モデル",
        estimatedMemoryBytes: 1800 * mb
    )

    // MARK: - Other Models

    /// LFM2 1.2B 4bit — 超高速推論
    public static let lfm2_1_2B = ModelSpec(
        id: "lfm2-1.2b-4bit",
        base: .huggingFace(id: "mlx-community/LFM2-1.2B-4bit"),
        contextLength: 4096,
        displayName: "LFM2 1.2B",
        description: "Liquid AI の高速推論モデル。トークン生成が特に高速",
        estimatedMemoryBytes: 700 * mb
    )

    /// Granite 3.3 2B Instruct 4bit — エンタープライズ軽量
    public static let granite3_3_2B = ModelSpec(
        id: "granite-3.3-2b-instruct-4bit",
        base: .huggingFace(id: "mlx-community/granite-3.3-2b-instruct-4bit"),
        contextLength: 4096,
        displayName: "Granite 3.3 2B",
        description: "IBM のエンタープライズ向け軽量モデル",
        estimatedMemoryBytes: 1200 * mb
    )

    /// GPT-OSS 20B MXFP4-Q8 — OpenAI オープンソース
    public static let gptOSS_20B = ModelSpec(
        id: "gpt-oss-20b-mxfp4-q8",
        base: .huggingFace(id: "mlx-community/gpt-oss-20b-MXFP4-Q8"),
        contextLength: 8192,
        displayName: "GPT-OSS 20B",
        description: "OpenAI のオープンソースモデル。高い日本語性能",
        estimatedMemoryBytes: 12_000 * mb
    )

    // MARK: - All Models

    /// 全モデルプリセット一覧（推定メモリ昇順）
    public static let all: [ModelSpec] = [
        // Tiny (< 1GB)
        smolLM_135M,
        qwen3_0_6B,
        lfm2_1_2B,
        llama3_2_1B,
        gemma3_1B_qat,
        deepseekR1_1_5B,
        // Small (1-3GB)
        qwen3_1_7B,
        gemma3n_e2b,
        granite3_3_2B,
        gemma2_2B,
        llama3_2_3B,
        smolLM3_3B,
        phi3_5_mini,
        phi4_mini,
        qwen3_4B,
        qwen3_4B_ja,
        gemma3n_e4b,
        gemma3_4B_qat,
        // Medium (3-8GB)
        mistral7B,
        deepseekR1_7B,
        llama3_1_8B,
        qwen3_8B,
        gemma2_9B,
        gemma3_12B_qat,
        // Large (8-20GB)
        deepseekR1_14B,
        qwen2_5_14B,
        gptOSS_20B,
        mistralSmall24B,
        gemma3_27B_qat,
        qwen3_moe_30B,
        qwen2_5_32B,
        // Extra Large (20GB+)
        deepseekR1_70B,
        llama3_3_70B,
        qwen2_5_72B,
    ]

    // MARK: - Private Helpers

    /// 1 MB をバイト数で表す定数
    private static let mb: UInt64 = 1024 * 1024
}

// swiftlint:enable type_body_length
