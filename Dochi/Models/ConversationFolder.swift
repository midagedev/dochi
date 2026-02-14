import Foundation

struct ConversationFolder: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var icon: String  // SF Symbol (default: "folder")
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, icon: String = "folder", sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
