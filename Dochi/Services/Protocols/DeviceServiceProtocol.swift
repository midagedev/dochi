import Foundation

struct DeviceInfo: Identifiable, Codable {
    let id: UUID
    let workspaceId: UUID
    let userId: UUID
    var deviceName: String
    let platform: String
    var isOnline: Bool
    var lastSeenAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case userId = "user_id"
        case deviceName = "device_name"
        case platform
        case isOnline = "is_online"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
    }
}

@MainActor
protocol DeviceServiceProtocol: AnyObject {
    var currentDevice: DeviceInfo? { get }
    var workspaceDevices: [DeviceInfo] { get }

    func registerDevice() async throws
    func startHeartbeat()
    func stopHeartbeat()
    func fetchWorkspaceDevices() async throws -> [DeviceInfo]
    func updateDeviceName(_ name: String) async throws
    func removeDevice(id: UUID) async throws
}
