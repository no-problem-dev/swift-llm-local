import SwiftUI
import LLMLocal
import DesignSystem

@main
struct LLMLocalExampleApp: App {
    @State private var themeProvider = ThemeProvider()
    @State private var chatState: ChatState
    @State private var modelState: ModelState
    @State private var settingsState = SettingsState()
    @State private var toolState = ToolState(tools: [
        CalculatorTool(),
        DateTimeTool(),
        DiceRollTool(),
    ])

    init() {
        let services = ServiceFactory.makeServices()
        _chatState = State(initialValue: ChatState(service: services.llmService))
        _modelState = State(initialValue: ModelState(
            service: services.llmService,
            modelRegistry: services.modelRegistry,
            memoryMonitor: services.memoryMonitor
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(chatState)
                .environment(modelState)
                .environment(settingsState)
                .environment(toolState)
                .theme(themeProvider)
                .task {
                    await chatState.startMemoryMonitoring()
                    await modelState.refreshCache()
                    await modelState.refreshMemoryInfo()
                }
        }
    }
}
