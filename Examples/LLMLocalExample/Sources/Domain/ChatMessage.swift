import Foundation
import LLMLocal

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let content: String
    let stats: GenerationStats?
    let toolName: String?
    let timestamp: Date

    enum Role: Sendable {
        case user
        case assistant
        case toolCall
        case toolResult
    }

    init(role: Role, content: String, stats: GenerationStats? = nil, toolName: String? = nil) {
        self.role = role
        self.content = content
        self.stats = stats
        self.toolName = toolName
        self.timestamp = Date()
    }
}
