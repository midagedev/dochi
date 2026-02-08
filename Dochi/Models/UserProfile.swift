import Foundation

struct UserProfile: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var aliases: [String]
    var description: String
    let createdAt: Date

    /// name + aliases 전체 이름 목록
    var allNames: [String] { [name] + aliases }

    init(id: UUID = UUID(), name: String, aliases: [String] = [], description: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.description = description
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        description = try container.decode(String.self, forKey: .description)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}
