import Foundation

struct UserProfile: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var description: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, description: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
    }
}
