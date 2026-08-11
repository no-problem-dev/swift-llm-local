/// Coarse size bucket derived from a model's estimated memory footprint.
///
/// Buckets exist for grouping and filtering a model list, not for deciding whether a model will
/// actually run: the boundaries encode memory alone and say nothing about a device class. Compare
/// ``ModelSpec/estimatedMemoryBytes`` against the memory the process can actually claim to answer
/// that. The tiers are ordered smallest to largest, so they sort and compare directly.
public enum ModelSizeTier: String, CaseIterable, Sendable, Comparable {
    /// Under 1 GiB.
    case tiny
    /// 1 GiB up to but not including 3 GiB.
    case small
    /// 3 GiB up to but not including 8 GiB.
    case medium
    /// 8 GiB up to but not including 20 GiB.
    case large
    /// 20 GiB and above.
    case extraLarge

    /// Tier name with its size range, ready to show in a list header or a filter control.
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
    /// Size bucket this model falls into, from its estimated memory footprint.
    ///
    /// Computed from ``estimatedMemoryBytes`` in gibibytes, so a model advertised as "8 GB" that is
    /// counted in decimal units lands one tier lower than its marketing name suggests.
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
