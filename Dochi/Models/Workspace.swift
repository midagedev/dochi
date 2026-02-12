import Foundation

struct Workspace: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var inviteCode: String?
    let ownerId: UUID
    let createdAt: Date

    init(id: UUID = UUID(), name: String, inviteCode: String? = nil, ownerId: UUID, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.ownerId = ownerId
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }
}

struct WorkspaceMember: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let userId: UUID
    let role: String  // "owner" | "member"
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case userId = "user_id"
        case role
        case joinedAt = "joined_at"
    }
}
