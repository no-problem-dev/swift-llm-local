import SwiftUI
import LLMLocal

@Observable
@MainActor
final class ToolState {
    let availableTools: [any LocalTool]
    var enabledToolNames: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(enabledToolNames), forKey: "llmlocal.enabledToolNames")
        }
    }

    var enabledTools: [any LocalTool] {
        availableTools.filter { enabledToolNames.contains($0.id) }
    }

    var enabledToolDefinitions: [ToolDefinition] {
        enabledTools.map(\.definition)
    }

    init(tools: [any LocalTool]) {
        self.availableTools = tools
        if let saved = UserDefaults.standard.stringArray(forKey: "llmlocal.enabledToolNames") {
            self.enabledToolNames = Set(saved)
        } else {
            self.enabledToolNames = Set(tools.map(\.id))
        }
    }

    func tool(named name: String) -> (any LocalTool)? {
        availableTools.first { $0.id == name }
    }

    func isEnabled(_ tool: any LocalTool) -> Bool {
        enabledToolNames.contains(tool.id)
    }

    func setEnabled(_ enabled: Bool, for tool: any LocalTool) {
        if enabled {
            enabledToolNames.insert(tool.id)
        } else {
            enabledToolNames.remove(tool.id)
        }
    }
}
