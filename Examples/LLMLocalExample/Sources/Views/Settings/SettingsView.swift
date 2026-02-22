import SwiftUI
import DesignSystem

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                GenerationConfigSection()
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
