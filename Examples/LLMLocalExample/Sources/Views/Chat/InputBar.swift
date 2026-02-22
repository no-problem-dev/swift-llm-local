import SwiftUI
import DesignSystem

struct InputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    var body: some View {
        HStack(spacing: spacing.sm) {
            TextField("メッセージ...", text: $text, axis: .vertical)
                .focused($isFocused)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, spacing.md)
                .padding(.vertical, spacing.sm)
                .background(colors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .disabled(isGenerating)
                .onChange(of: isGenerating) { _, newValue in
                    if newValue {
                        isFocused = false
                    }
                }

            if isGenerating {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(colors.error)
                }
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? colors.onSurfaceVariant
                                : colors.primary
                        )
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, spacing.md)
        .padding(.vertical, spacing.sm)
        .background(colors.surface)
    }
}
