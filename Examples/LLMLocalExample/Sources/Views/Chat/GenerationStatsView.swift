import SwiftUI
import LLMLocal
import DesignSystem

struct GenerationStatsView: View {
    let stats: GenerationStats

    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    var body: some View {
        HStack(spacing: spacing.sm) {
            Label(
                String(format: "%.1f tok/s", stats.tokensPerSecond),
                systemImage: "speedometer"
            )
            Label(
                "\(stats.tokenCount) tokens",
                systemImage: "number"
            )
            Label(
                formattedDuration,
                systemImage: "clock"
            )
        }
        .font(.caption)
        .foregroundStyle(colors.onSurfaceVariant)
    }

    private var formattedDuration: String {
        let seconds = Double(stats.duration.components.seconds)
            + Double(stats.duration.components.attoseconds) / 1e18
        return String(format: "%.1fs", seconds)
    }
}
