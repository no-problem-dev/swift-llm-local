import SwiftUI
import DesignSystem

struct MessageBubble: View {
    let message: ChatMessage

    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: spacing.xxl) }

            VStack(alignment: .leading, spacing: spacing.xs) {
                if message.role == .assistant {
                    StreamingResponseView(content: message.content, isStreaming: false)
                } else {
                    Text(message.content)
                        .typography(.bodyLarge)
                        .foregroundStyle(colors.onPrimary)
                }

                if let stats = message.stats {
                    GenerationStatsView(stats: stats)
                }
            }
            .padding(spacing.md)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if message.role == .assistant { Spacer(minLength: spacing.xxl) }
        }
    }

    private var bubbleBackground: Color {
        message.role == .user ? colors.primary : colors.surfaceVariant
    }
}
