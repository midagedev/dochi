import Foundation

struct ConversationTag: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var color: String  // "red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "gray"
    var createdAt: Date

    init(id: UUID = UUID(), name: String, color: String = "blue", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
    }

    /// 9-color palette for tags.
    static let availableColors = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "gray"]
}
