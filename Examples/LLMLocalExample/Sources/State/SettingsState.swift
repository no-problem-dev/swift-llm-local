import SwiftUI
import LLMLocal

@Observable
@MainActor
final class SettingsState {
    var temperature: Double = 0.7
    var maxTokens: Double = 1024
    var topP: Double = 0.9

    var config: GenerationConfig {
        GenerationConfig(
            maxTokens: Int(maxTokens),
            temperature: Float(temperature),
            topP: Float(topP)
        )
    }
}
