import Foundation

struct UserProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var aliases: [String]
    var description: String?
    let createdAt: Date

    init(id: UUID = UUID(), name: String, aliases: [String] = [], description: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.description = description
        self.createdAt = createdAt
    }
}
