import Foundation
import LLMLocal

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let content: String
    let stats: GenerationStats?
    let timestamp: Date

    enum Role: Sendable {
        case user
        case assistant
    }

    init(role: Role, content: String, stats: GenerationStats? = nil) {
        self.role = role
        self.content = content
        self.stats = stats
        self.timestamp = Date()
    }
}
