// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-llm-local",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        // Umbrella (all modules + LLMLocalService)
        .library(name: "LLMLocal", targets: ["LLMLocal"]),
        // Protocol only (for app abstraction layer)
        .library(name: "LLMLocalClient", targets: ["LLMLocalClient"]),
        // MLX backend (for app DI configuration)
        .library(name: "LLMLocalMLX", targets: ["LLMLocalMLX"]),
    ],
    dependencies: [
        // Canonical LLM types (ToolDefinition, ToolCall, JSONSchema)
        .package(url: "https://github.com/no-problem-dev/swift-llm-client.git", from: "3.5.1"),
        // Persistence abstractions (RegistryStore)
        .package(url: "https://github.com/no-problem-dev/swift-persistence.git", .upToNextMajor(from: "2.0.0")),
        // MLX LLM inference
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        // Hugging Face Hub download / tokenizer (mlx-swift-lm 3.x は Downloader/TokenizerLoader を消費側が注入する設計)
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
        // Documentation generation
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // MARK: - Layer 0: Protocol + shared types
        .target(
            name: "LLMLocalClient",
            dependencies: [
                .product(name: "LLMClient", package: "swift-llm-client"),
                .product(name: "LLMTool", package: "swift-llm-client"),
            ]
        ),

        // MARK: - Layer 1: Model management
        .target(
            name: "LLMLocalModels",
            dependencies: [
                "LLMLocalClient",
                .product(name: "PersistenceCore", package: "swift-persistence"),
                .product(name: "PersistenceFileSystem", package: "swift-persistence"),
            ]
        ),

        // MARK: - Layer 2: MLX backend
        .target(
            name: "LLMLocalMLX",
            dependencies: [
                "LLMLocalClient",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),

        // MARK: - Umbrella + Service
        .target(
            name: "LLMLocal",
            dependencies: [
                "LLMLocalClient",
                "LLMLocalModels",
                "LLMLocalMLX",
                .product(name: "LLMAgentStep", package: "swift-llm-client"),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "LLMLocalClientTests",
            dependencies: ["LLMLocalClient"],
            path: "Tests/LLMLocalClientTests"
        ),
        .testTarget(
            name: "LLMLocalModelsTests",
            dependencies: [
                "LLMLocalModels",
                "LLMLocalClient",
                .product(name: "PersistenceTesting", package: "swift-persistence"),
            ],
            path: "Tests/LLMLocalModelsTests"
        ),
        .testTarget(
            name: "LLMLocalMLXTests",
            dependencies: ["LLMLocalMLX", "LLMLocalClient", "LLMLocal"],
            path: "Tests/LLMLocalMLXTests"
        ),
        .testTarget(
            name: "LLMLocalTests",
            dependencies: ["LLMLocal", "LLMLocalClient"],
            path: "Tests/LLMLocalTests"
        ),
    ]
)
