import Foundation

struct Device: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var name: String
    let platform: String  // "macos"
    var lastHeartbeat: Date
    var workspaceIds: [UUID]

    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        platform: String = "macos",
        lastHeartbeat: Date = Date(),
        workspaceIds: [UUID] = []
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.platform = platform
        self.lastHeartbeat = lastHeartbeat
        self.workspaceIds = workspaceIds
    }

    var isOnline: Bool {
        Date().timeIntervalSince(lastHeartbeat) < 120
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, platform
        case lastHeartbeat = "last_heartbeat"
        case workspaceIds = "workspace_ids"
    }
}
