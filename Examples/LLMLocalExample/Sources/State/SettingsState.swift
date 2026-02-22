import SwiftUI
import LLMLocal

@Observable
@MainActor
final class SettingsState {
    var temperature: Double { didSet { save() } }
    var maxTokens: Double { didSet { save() } }
    var topP: Double { didSet { save() } }
    var systemPrompt: String { didSet { save() } }

    init() {
        let ud = UserDefaults.standard
        temperature = ud.object(forKey: "llmlocal.temperature") as? Double ?? 0.7
        maxTokens = ud.object(forKey: "llmlocal.maxTokens") as? Double ?? 1024
        topP = ud.object(forKey: "llmlocal.topP") as? Double ?? 0.9
        systemPrompt = ud.string(forKey: "llmlocal.systemPrompt")
            ?? "日本語で簡潔に回答する。質問に直接答え、不要な前置きや繰り返しを避ける。"
    }

    var config: GenerationConfig {
        GenerationConfig(
            maxTokens: Int(maxTokens),
            temperature: Float(temperature),
            topP: Float(topP)
        )
    }

    private func save() {
        let ud = UserDefaults.standard
        ud.set(temperature, forKey: "llmlocal.temperature")
        ud.set(maxTokens, forKey: "llmlocal.maxTokens")
        ud.set(topP, forKey: "llmlocal.topP")
        ud.set(systemPrompt, forKey: "llmlocal.systemPrompt")
    }
}
