import SwiftUI
import DesignSystem

struct ToolSettingsSection: View {
    @Environment(ToolState.self) private var toolState

    var body: some View {
        @Bindable var toolState = toolState

        Section {
            ForEach(toolState.availableTools, id: \.id) { tool in
                Toggle(isOn: Binding(
                    get: { toolState.isEnabled(tool) },
                    set: { toolState.setEnabled($0, for: tool) }
                )) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(tool.displayName)
                            Text(tool.definition.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: tool.iconName)
                    }
                }
            }
        } header: {
            Text("ツール")
        } footer: {
            let count = toolState.enabledToolNames.count
            Text("\(count) 個のツールが有効")
        }
    }
}
