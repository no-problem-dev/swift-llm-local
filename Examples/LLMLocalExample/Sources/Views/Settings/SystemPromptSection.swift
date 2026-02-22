import SwiftUI
import DesignSystem

struct SystemPromptSection: View {
    @Binding var systemPrompt: String
    @Environment(\.colorPalette) private var colors

    var body: some View {
        Section {
            TextEditor(text: $systemPrompt)
                .frame(minHeight: 80)
                .font(.body)
            if !systemPrompt.isEmpty {
                Button("クリア", role: .destructive) {
                    systemPrompt = ""
                }
            }
        } header: {
            Text("システムプロンプト")
        } footer: {
            Text("すべての会話に適用される指示（例: 「日本語で回答してください」）")
        }
    }
}
