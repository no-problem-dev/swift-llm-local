import SwiftUI
import DesignSystem

struct ToolCallBubble: View {
    let message: ChatMessage

    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: spacing.xs) {
                Label(
                    title: { Text(headerText).typography(.labelLarge) },
                    icon: { Image(systemName: iconName).font(.caption) }
                )
                .foregroundStyle(headerColor)

                Text(message.content)
                    .typography(.bodySmall)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(contentColor)
                    .lineLimit(6)
            }
            .padding(spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: spacing.xxl)
        }
    }

    private var isToolCall: Bool {
        message.role == .toolCall
    }

    private var iconName: String {
        isToolCall ? "wrench.and.screwdriver" : "checkmark.circle"
    }

    private var headerText: String {
        if let name = message.toolName {
            return isToolCall ? "Tool: \(name)" : "\(name) result"
        }
        return isToolCall ? "Tool Call" : "Result"
    }

    private var headerColor: Color {
        isToolCall ? colors.onPrimaryContainer : colors.onSecondaryContainer
    }

    private var contentColor: Color {
        isToolCall
            ? colors.onPrimaryContainer.opacity(0.8)
            : colors.onSecondaryContainer.opacity(0.8)
    }

    private var backgroundColor: Color {
        isToolCall ? colors.primaryContainer : colors.secondaryContainer
    }
}
