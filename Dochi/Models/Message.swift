import Foundation

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

struct Message: Codable, Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var toolCalls: [CodableToolCall]?
    var toolCallId: String?
    var imageURLs: [URL]?

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), toolCalls: [CodableToolCall]? = nil, toolCallId: String? = nil, imageURLs: [URL]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.imageURLs = imageURLs
    }
}
