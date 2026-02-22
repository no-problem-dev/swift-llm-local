import SwiftUI
import DesignSystem

struct GenerationConfigSection: View {
    @Environment(SettingsState.self) private var settingsState
    @Environment(\.colorPalette) private var colors

    var body: some View {
        @Bindable var settings = settingsState

        Section("生成設定") {
            VStack(alignment: .leading) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .foregroundStyle(colors.primary)
                        .monospacedDigit()
                }
                Slider(value: $settings.temperature, in: 0...2, step: 0.05)
                    .tint(colors.primary)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("最大トークン数")
                    Spacer()
                    Text("\(Int(settings.maxTokens))")
                        .foregroundStyle(colors.primary)
                        .monospacedDigit()
                }
                Slider(value: $settings.maxTokens, in: 64...4096, step: 64)
                    .tint(colors.primary)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Top P")
                    Spacer()
                    Text(String(format: "%.2f", settings.topP))
                        .foregroundStyle(colors.primary)
                        .monospacedDigit()
                }
                Slider(value: $settings.topP, in: 0...1, step: 0.05)
                    .tint(colors.primary)
            }
        }
    }
}
