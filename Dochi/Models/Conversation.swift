import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var userId: String?
    var summary: String?

    init(id: UUID = UUID(), title: String, messages: [Message], createdAt: Date = Date(), updatedAt: Date = Date(), userId: String? = nil, summary: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, userId, summary
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
    }
}
