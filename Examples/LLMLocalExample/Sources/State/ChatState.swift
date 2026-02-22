import SwiftUI
import LLMLocal

@Observable
@MainActor
final class ChatState {
    private let service: LLMLocalService

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isGenerating: Bool = false
    var isLoadingModel: Bool = false
    var streamingContent: String = ""
    var error: String?
    var lastStats: GenerationStats?

    private var generationTask: Task<Void, Never>?

    init(service: LLMLocalService) {
        self.service = service
    }

    func send(model: ModelSpec, config: GenerationConfig) {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        inputText = ""
        error = nil

        messages.append(ChatMessage(role: .user, content: prompt))

        isGenerating = true
        isLoadingModel = true
        streamingContent = ""

        generationTask = Task {
            do {
                let stream = await service.generate(
                    model: model,
                    prompt: prompt,
                    config: config
                )
                isLoadingModel = false
                for try await token in stream {
                    streamingContent += token
                }
                let stats = await service.lastGenerationStats
                messages.append(ChatMessage(
                    role: .assistant,
                    content: streamingContent,
                    stats: stats
                ))
                lastStats = stats
                streamingContent = ""
            } catch {
                if !streamingContent.isEmpty {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: streamingContent
                    ))
                    streamingContent = ""
                }
                self.error = error.localizedDescription
            }
            isGenerating = false
            isLoadingModel = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        if !streamingContent.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: streamingContent
            ))
            streamingContent = ""
        }
        isGenerating = false
        isLoadingModel = false
    }

    func startMemoryMonitoring() async {
        await service.startMemoryMonitoring()
    }

    func clearMessages() {
        messages.removeAll()
        lastStats = nil
        error = nil
    }
}
