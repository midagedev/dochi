import Foundation

struct Workspace: Identifiable, Codable {
    let id: UUID
    var name: String
    var inviteCode: String? = nil
    let ownerId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }
}

struct WorkspaceMember: Identifiable, Codable {
    let id: UUID
    let workspaceId: UUID
    let userId: UUID
    var role: Role
    let joinedAt: Date

    enum Role: String, Codable {
        case owner
        case member
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case userId = "user_id"
        case role
        case joinedAt = "joined_at"
    }
}
