import SwiftUI
import SwiftMarkdownView
import SwiftMarkdownViewHighlightJS
import DesignSystem

struct StreamingResponseView: View {
    let content: String
    let isStreaming: Bool

    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarkdownView(content)
                .adaptiveSyntaxHighlighting()

            if isStreaming {
                cursorView
            }
        }
    }

    private var cursorView: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(colors.primary)
            .frame(width: 2, height: 18)
            .opacity(cursorOpacity)
            .animation(
                .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                value: cursorOpacity
            )
    }

    @State private var cursorOpacity: Double = 1.0

    // Note: cursor blink is driven by the animation modifier above;
    // the initial value of 1.0 triggers the repeating animation.
}
