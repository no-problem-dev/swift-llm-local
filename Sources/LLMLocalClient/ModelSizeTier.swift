/// モデルの推定メモリ使用量に基づくサイズ分類
public enum ModelSizeTier: String, CaseIterable, Sendable, Comparable {
    /// 1GB 未満
    case tiny
    /// 1〜3GB
    case small
    /// 3〜8GB
    case medium
    /// 8〜20GB
    case large
    /// 20GB 以上
    case extraLarge

    /// UI 表示用の名前
    public var displayName: String {
        switch self {
        case .tiny: "Tiny (< 1 GB)"
        case .small: "Small (1–3 GB)"
        case .medium: "Medium (3–8 GB)"
        case .large: "Large (8–20 GB)"
        case .extraLarge: "Extra Large (20 GB+)"
        }
    }

    public static func < (lhs: ModelSizeTier, rhs: ModelSizeTier) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

extension ModelSpec {
    /// 推定メモリ使用量に基づくサイズティア
    public var sizeTier: ModelSizeTier {
        let gb = Double(estimatedMemoryBytes) / (1024 * 1024 * 1024)
        switch gb {
        case ..<1.0: return .tiny
        case 1.0..<3.0: return .small
        case 3.0..<8.0: return .medium
        case 8.0..<20.0: return .large
        default: return .extraLarge
        }
    }
}
