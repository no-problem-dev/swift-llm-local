import SwiftUI
import LLMLocal
import DesignSystem

@main
struct LLMLocalExampleApp: App {
    @State private var themeProvider = ThemeProvider()
    @State private var chatState: ChatState
    @State private var modelState: ModelState
    @State private var settingsState = SettingsState()

    init() {
        let services = ServiceFactory.makeServices()
        _chatState = State(initialValue: ChatState(service: services.llmService))
        _modelState = State(initialValue: ModelState(
            service: services.llmService,
            modelManager: services.modelManager,
            memoryMonitor: services.memoryMonitor
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(chatState)
                .environment(modelState)
                .environment(settingsState)
                .theme(themeProvider)
                .task {
                    await chatState.startMemoryMonitoring()
                    await modelState.refreshCache()
                    await modelState.refreshMemoryInfo()
                }
        }
    }
}
