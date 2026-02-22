import LLMLocal

enum ModelCategory: String, CaseIterable, Sendable {
    case japanese = "日本語特化"
    case multilingual = "多言語（日本語対応）"
    case lightweight = "軽量・テスト用"
    case large = "大型（12GB+ RAM）"
}

struct CatalogEntry: Sendable {
    let spec: ModelSpec
    let category: ModelCategory
    let sizeHint: String
}

enum ModelCatalog {
    static let all: [CatalogEntry] = [
        // MARK: - 日本語特化モデル

        CatalogEntry(
            spec: ModelSpec(
                id: "llm-jp-3-1.8b-instruct",
                base: .huggingFace(id: "mlx-community/llm-jp-3-1.8b-instruct"),
                contextLength: 4096,
                displayName: "LLM-jp 3 1.8B",
                description: "国立情報学研究所の日本語モデル。軽量で日本語に特化"
            ),
            category: .japanese,
            sizeHint: "~3.5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "elyza-jp-8b-4bit",
                base: .huggingFace(id: "mlx-community/Llama-3-ELYZA-JP-8B-4bit"),
                contextLength: 8192,
                displayName: "ELYZA JP 8B",
                description: "ELYZA の日本語 Llama 3。日本語タスクに高い性能"
            ),
            category: .japanese,
            sizeHint: "~4.5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "swallow-8b-instruct-v0.2-4bit",
                base: .huggingFace(id: "mlx-community/Llama-3.1-Swallow-8B-Instruct-v0.2-4bit"),
                contextLength: 8192,
                displayName: "Swallow 8B v0.2",
                description: "東工大の日本語 Llama。自然な日本語生成"
            ),
            category: .japanese,
            sizeHint: "~4.5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "llm-jp-3-13b-instruct-4bit",
                base: .huggingFace(id: "mlx-community/llm-jp-3-13b-instruct-4bit"),
                contextLength: 4096,
                displayName: "LLM-jp 3 13B",
                description: "国立情報学研究所の大型日本語モデル。高品質な回答"
            ),
            category: .japanese,
            sizeHint: "~7.5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "llm-jp-3.1-13b-instruct4-4bit",
                base: .huggingFace(id: "mlx-community/llm-jp-3.1-13b-instruct4-4bit"),
                contextLength: 4096,
                displayName: "LLM-jp 3.1 13B",
                description: "LLM-jp 最新版。改良された日本語性能"
            ),
            category: .japanese,
            sizeHint: "~7.5GB"
        ),

        CatalogEntry(
            spec: ModelSpec(
                id: "qwen3-4b-ja-4bit",
                base: .huggingFace(id: "taniguchi-kyoichi/Qwen3-4B-Instruct-2507-ja-4bit"),
                contextLength: 4096,
                displayName: "Qwen3 4B 日本語",
                description: "Qwen3-4B を日本語データでファインチューニング。iPhone 向け最適化"
            ),
            category: .japanese,
            sizeHint: "~2.3GB"
        ),

        // MARK: - 多言語（日本語対応良好）

        CatalogEntry(
            spec: ModelSpec(
                id: "gemma-2-2b-it-4bit",
                base: .huggingFace(id: "mlx-community/gemma-2-2b-it-4bit"),
                contextLength: 8192,
                displayName: "Gemma 2 2B",
                description: "Google の軽量モデル。日本語も対応"
            ),
            category: .multilingual,
            sizeHint: "~1.5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "qwen3-4b-instruct-2507-4bit",
                base: .huggingFace(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit"),
                contextLength: 4096,
                displayName: "Qwen3 4B Instruct 2507",
                description: "Alibaba の最新 Instruct モデル。日本語・コード生成に強い"
            ),
            category: .multilingual,
            sizeHint: "~2.3GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "qwen3-8b-4bit",
                base: .huggingFace(id: "mlx-community/Qwen3-8B-4bit"),
                contextLength: 4096,
                displayName: "Qwen3 8B",
                description: "Alibaba の高性能モデル。日本語対応が特に良好"
            ),
            category: .multilingual,
            sizeHint: "~5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "gemma-2-9b-it-4bit",
                base: .huggingFace(id: "mlx-community/gemma-2-9b-it-4bit"),
                contextLength: 8192,
                displayName: "Gemma 2 9B",
                description: "Google の高品質モデル。多言語対応"
            ),
            category: .multilingual,
            sizeHint: "~5.5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "phi-4-mini-instruct-4bit",
                base: .huggingFace(id: "mlx-community/phi-4-mini-instruct-4bit"),
                contextLength: 4096,
                displayName: "Phi-4 Mini",
                description: "Microsoft の小型高性能モデル。推論能力が高い"
            ),
            category: .multilingual,
            sizeHint: "~2.3GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "llama-3.1-8b-instruct-4bit",
                base: .huggingFace(id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"),
                contextLength: 8192,
                displayName: "Llama 3.1 8B",
                description: "Meta の定番 8B。幅広いタスクに対応"
            ),
            category: .multilingual,
            sizeHint: "~4.5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "mistral-7b-instruct-v03-4bit",
                base: .huggingFace(id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit"),
                contextLength: 8192,
                displayName: "Mistral 7B v0.3",
                description: "Mistral AI の定番モデル"
            ),
            category: .multilingual,
            sizeHint: "~4.1GB"
        ),

        // MARK: - 軽量・テスト用

        CatalogEntry(
            spec: ModelSpec(
                id: "smollm2-135m-instruct-4bit",
                base: .huggingFace(id: "mlx-community/SmolLM2-135M-Instruct-4bit"),
                contextLength: 2048,
                displayName: "SmolLM2 135M",
                description: "超軽量。動作確認やテスト向け"
            ),
            category: .lightweight,
            sizeHint: "~100MB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "smollm2-360m-instruct-4bit",
                base: .huggingFace(id: "mlx-community/SmolLM2-360M-Instruct-4bit"),
                contextLength: 2048,
                displayName: "SmolLM2 360M",
                description: "軽量モデル。簡単な質問応答向け"
            ),
            category: .lightweight,
            sizeHint: "~250MB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "llama-3.2-1b-instruct-4bit",
                base: .huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
                contextLength: 8192,
                displayName: "Llama 3.2 1B",
                description: "Meta の軽量モデル。バランスの良い性能"
            ),
            category: .lightweight,
            sizeHint: "~700MB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "qwen3-1.7b-4bit",
                base: .huggingFace(id: "mlx-community/Qwen3-1.7B-4bit"),
                contextLength: 4096,
                displayName: "Qwen3 1.7B",
                description: "Alibaba の軽量モデル。多言語対応"
            ),
            category: .lightweight,
            sizeHint: "~1.2GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "llama-3.2-3b-instruct-4bit",
                base: .huggingFace(id: "mlx-community/Llama-3.2-3B-Instruct-4bit"),
                contextLength: 8192,
                displayName: "Llama 3.2 3B",
                description: "Meta の 3B モデル。実用的な性能"
            ),
            category: .lightweight,
            sizeHint: "~2GB"
        ),

        // MARK: - 大型モデル（12GB+ RAM 推奨）

        CatalogEntry(
            spec: ModelSpec(
                id: "gpt-oss-20b-4bit",
                base: .huggingFace(id: "mlx-community/gpt-oss-20b-MXFP4-Q4"),
                contextLength: 8192,
                displayName: "GPT-OSS 20B",
                description: "OpenAI のオープンソースモデル。高い日本語性能"
            ),
            category: .large,
            sizeHint: "~11GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "qwen3-14b-4bit",
                base: .huggingFace(id: "mlx-community/Qwen3-14B-4bit"),
                contextLength: 4096,
                displayName: "Qwen3 14B",
                description: "Alibaba の大型モデル。日本語性能も高い"
            ),
            category: .large,
            sizeHint: "~8.5GB"
        ),
        CatalogEntry(
            spec: ModelSpec(
                id: "gemma-3-12b-it-4bit",
                base: .huggingFace(id: "mlx-community/gemma-3-12b-it-4bit"),
                contextLength: 8192,
                displayName: "Gemma 3 12B",
                description: "Google の最新 12B モデル"
            ),
            category: .large,
            sizeHint: "~7.5GB"
        ),
    ]

    static func models(for category: ModelCategory) -> [CatalogEntry] {
        all.filter { $0.category == category }
    }

    static var specs: [ModelSpec] {
        all.map(\.spec)
    }

    static let defaultModel = all.first { $0.spec.id == "gemma-2-2b-it-4bit" }!.spec
}
