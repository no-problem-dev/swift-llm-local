import SwiftUI
import DesignSystem

struct SettingsView: View {
    @Environment(SettingsState.self) private var settingsState

    var body: some View {
        @Bindable var settings = settingsState

        NavigationStack {
            Form {
                SystemPromptSection(systemPrompt: $settings.systemPrompt)
                GenerationConfigSection()
                ToolSettingsSection()
                ThemeSelectorView()
                MemoryInfoView()

                Section("情報") {
                    LabeledContent("バージョン", value: "0.1.0")
                    LabeledContent("パッケージ", value: "swift-llm-local")
                }
            }
            .navigationTitle("設定")
        }
    }
}
