import Foundation

enum ConversationSource: String, Codable, Sendable {
    case local
    case telegram
}

struct Conversation: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var userId: String?
    var summary: String?
    var source: ConversationSource
    var telegramChatId: Int64?

    init(id: UUID = UUID(), title: String = "새 대화", messages: [Message] = [], createdAt: Date = Date(), updatedAt: Date = Date(), userId: String? = nil, summary: String? = nil, source: ConversationSource = .local, telegramChatId: Int64? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.summary = summary
        self.source = source
        self.telegramChatId = telegramChatId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decode([Message].self, forKey: .messages)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        source = try container.decodeIfPresent(ConversationSource.self, forKey: .source) ?? .local
        telegramChatId = try container.decodeIfPresent(Int64.self, forKey: .telegramChatId)
    }
}
