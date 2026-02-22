---
title: "Package Manifest Design"
created: 2026-02-22
status: draft
references:
  - ./01_architecture.md
---

# Package Manifest Design

## Package.swift

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-llm-local",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        // アンブレラ（全モジュール統合 + LLMLocalService）
        .library(name: "LLMLocal", targets: ["LLMLocal"]),
        // Protocol のみ（アプリの抽象層で使用）
        .library(name: "LLMLocalClient", targets: ["LLMLocalClient"]),
        // MLX バックエンド（アプリの DI 構成で使用）
        .library(name: "LLMLocalMLX", targets: ["LLMLocalMLX"]),
    ],
    dependencies: [
        // MLX LLM 推論
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "0.1.0"),
        // ドキュメント生成
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // MARK: - Layer 0: Protocol + 共通型（外部依存なし）
        .target(
            name: "LLMLocalClient",
            dependencies: []
        ),

        // MARK: - Layer 1: モデル管理
        .target(
            name: "LLMLocalModels",
            dependencies: ["LLMLocalClient"]
        ),

        // MARK: - Layer 2: MLX バックエンド
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
```

## 依存バージョン管理

| 依存先 | バージョン指定 | 備考 |
|---|---|---|
| mlx-swift-lm | `from: "0.1.0"` | MLXLLM, MLXLMCommon を提供。実際のバージョンは Phase 1 開始前に確認 |
| swift-docc-plugin | `from: "1.4.0"` | ドキュメント生成（no-problem-dev 標準） |

## 注意事項

### mlx-swift-lm のパッケージ URL
- mlx-swift-lm は mlx-swift-examples から分離された比較的新しいリポジトリ
- Package URL とプロダクト名は Phase 1 開始前に最新のリポジトリで確認すること
- `MLXLLM` と `MLXLMCommon` のプロダクト名が正確かも要確認

### iOS シミュレータでの制約
- MLX は Metal バックエンドに依存するため、iOS シミュレータでは動作しない
- `LLMLocalMLXTests` は実機専用（CI では除外）
- `LLMLocalClientTests` と `LLMLocalModelsTests` は CI で実行可能
