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
    var isExecutingTool: Bool = false
    var executingToolName: String?
    var streamingContent: String = ""
    var error: String?
    var lastStats: GenerationStats?

    private var generationTask: Task<Void, Never>?

    init(service: LLMLocalService) {
        self.service = service
    }

    func send(model: ModelSpec, config: GenerationConfig, toolState: ToolState, systemPrompt: String) {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        inputText = ""
        error = nil

        messages.append(ChatMessage(role: .user, content: prompt))

        isGenerating = true
        isLoadingModel = true
        streamingContent = ""

        let enabledTools = toolState.enabledTools

        generationTask = Task {
            await service.setSystemPrompt(systemPrompt.isEmpty ? nil : systemPrompt)

            if enabledTools.isEmpty {
                await generateSimple(model: model, prompt: prompt, config: config)
            } else {
                await generateWithToolLoop(
                    model: model,
                    prompt: prompt,
                    config: config,
                    toolState: toolState
                )
            }
            isGenerating = false
            isLoadingModel = false
            isExecutingTool = false
            executingToolName = nil
        }
    }

    // MARK: - Simple Generation (no tools)

    private func generateSimple(model: ModelSpec, prompt: String, config: GenerationConfig) async {
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
            finalizeOnError(error)
        }
    }

    // MARK: - Multi-turn Tool Loop

    private func generateWithToolLoop(
        model: ModelSpec,
        prompt: String,
        config: GenerationConfig,
        toolState: ToolState
    ) async {
        let maxTurns = 5
        var currentPrompt = prompt
        let tools = toolState.enabledToolDefinitions

        for turn in 0..<maxTurns {
            do {
                let stream = await service.generateWithTools(
                    model: model,
                    prompt: currentPrompt,
                    tools: tools,
                    config: config
                )
                if turn == 0 {
                    isLoadingModel = false
                }

                // Consume stream
                streamingContent = ""
                var pendingToolCalls: [ToolCall] = []

                for try await output in stream {
                    switch output {
                    case .text(let token):
                        streamingContent += token
                    case .toolCall(let request):
                        pendingToolCalls.append(request)
                    }
                }

                // No tool calls → finalize as assistant message and exit
                if pendingToolCalls.isEmpty {
                    let stats = await service.lastGenerationStats
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: streamingContent,
                        stats: stats
                    ))
                    lastStats = stats
                    streamingContent = ""
                    return
                }

                // Has tool calls → process them
                if !streamingContent.isEmpty {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: streamingContent
                    ))
                    streamingContent = ""
                }

                // Execute each tool call
                var toolResultsPrompt = ""
                for call in pendingToolCalls {
                    let argsJSON = String(data: call.arguments, encoding: .utf8) ?? "{}"
                    messages.append(ChatMessage(
                        role: .toolCall,
                        content: argsJSON,
                        toolName: call.name
                    ))

                    isExecutingTool = true
                    executingToolName = call.name

                    let result: String
                    if let tool = toolState.tool(named: call.name) {
                        do {
                            result = try await tool.execute(arguments: argsJSON)
                        } catch {
                            result = "Error: \(error.localizedDescription)"
                        }
                    } else {
                        result = "Error: Unknown tool '\(call.name)'"
                    }

                    messages.append(ChatMessage(
                        role: .toolResult,
                        content: result,
                        toolName: call.name
                    ))

                    toolResultsPrompt += """
                    <tool_response>
                    {"name": "\(call.name)", "content": "\(result.replacingOccurrences(of: "\"", with: "\\\""))"}
                    </tool_response>

                    """
                }

                isExecutingTool = false
                executingToolName = nil

                // Continue loop with tool results as next prompt
                currentPrompt = toolResultsPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

            } catch {
                finalizeOnError(error)
                return
            }
        }

        // Max turns reached — add a note
        if streamingContent.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: "(ツールの最大呼び出し回数に達しました)"
            ))
        }
    }

    // MARK: - Error Handling

    private func finalizeOnError(_ error: Error) {
        if !streamingContent.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: streamingContent
            ))
            streamingContent = ""
        }
        self.error = error.localizedDescription
    }

    // MARK: - Actions

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
        isExecutingTool = false
        executingToolName = nil
    }

    func startMemoryMonitoring() async {
        await service.startMemoryMonitoring()
    }

    func clearMessages() {
        messages.removeAll()
        lastStats = nil
        error = nil
    }

    func formatSession(model: ModelSpec, config: GenerationConfig, systemPrompt: String) -> String {
        var lines: [String] = []
        lines.append("## Session Info")
        lines.append("Model: \(model.id)")
        lines.append("Temperature: \(config.temperature), MaxTokens: \(config.maxTokens), TopP: \(config.topP)")
        if !systemPrompt.isEmpty {
            lines.append("\n## System Prompt")
            lines.append(systemPrompt)
        }
        lines.append("\n## Conversation")
        for msg in messages {
            switch msg.role {
            case .user:
                lines.append("\n### User\n\(msg.content)")
            case .assistant:
                lines.append("\n### Assistant\n\(msg.content)")
            case .toolCall:
                lines.append("\n### Tool Call (\(msg.toolName ?? "unknown"))\n\(msg.content)")
            case .toolResult:
                lines.append("\n### Tool Result (\(msg.toolName ?? "unknown"))\n\(msg.content)")
            }
            if let stats = msg.stats {
                lines.append("(tokens: \(stats.tokenCount), speed: \(String(format: "%.1f", stats.tokensPerSecond)) tok/s)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
