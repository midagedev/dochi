import Foundation

struct Conversation: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var userId: String?
    var summary: String?

    init(id: UUID = UUID(), title: String = "새 대화", messages: [Message] = [], createdAt: Date = Date(), updatedAt: Date = Date(), userId: String? = nil, summary: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.summary = summary
    }
}
