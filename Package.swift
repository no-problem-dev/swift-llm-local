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
        // MLX LLM inference
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.30.0"),
        // Documentation generation
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // MARK: - Layer 0: Protocol + shared types (no external dependencies)
        .target(
            name: "LLMLocalClient",
            dependencies: []
        ),

        // MARK: - Layer 1: Model management
        .target(
            name: "LLMLocalModels",
            dependencies: ["LLMLocalClient"]
        ),

        // MARK: - Layer 2: MLX backend
        .target(
            name: "LLMLocalMLX",
            dependencies: [
                "LLMLocalClient",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ]
        ),

        // MARK: - Umbrella + Service
        .target(
            name: "LLMLocal",
            dependencies: [
                "LLMLocalClient",
                "LLMLocalModels",
                "LLMLocalMLX",
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
            dependencies: ["LLMLocalModels", "LLMLocalClient"],
            path: "Tests/LLMLocalModelsTests"
        ),
        .testTarget(
            name: "LLMLocalMLXTests",
            dependencies: ["LLMLocalMLX", "LLMLocalClient"],
            path: "Tests/LLMLocalMLXTests"
        ),
    ]
)
