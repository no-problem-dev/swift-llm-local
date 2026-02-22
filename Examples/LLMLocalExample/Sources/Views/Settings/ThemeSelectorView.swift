import SwiftUI
import DesignSystem

struct ThemeSelectorView: View {
    @Environment(ThemeProvider.self) private var themeProvider
    @Environment(\.colorPalette) private var colors

    var body: some View {
        @Bindable var tp = themeProvider

        Section("テーマ") {
            Picker("モード", selection: $tp.themeMode) {
                Text("システム").tag(ThemeMode.system)
                Text("ライト").tag(ThemeMode.light)
                Text("ダーク").tag(ThemeMode.dark)
            }

            ForEach(themeProvider.availableThemes, id: \.id) { theme in
                Button {
                    themeProvider.switchToTheme(id: theme.id)
                } label: {
                    HStack {
                        Text(theme.name)
                            .foregroundStyle(colors.onSurface)
                        Spacer()
                        if themeProvider.currentTheme.id == theme.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(colors.primary)
                        }
                        HStack(spacing: 4) {
                            ForEach(Array(theme.previewColors.prefix(3).enumerated()), id: \.offset) { _, color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
            }
        }
    }
}
