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
    var capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case userId = "user_id"
        case deviceName = "device_name"
        case platform
        case isOnline = "is_online"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
        case capabilities
    }
}

/// 디바이스가 지원하는 기능
enum DeviceCapability: String, CaseIterable {
    case tts       // 텍스트 → 음성 변환
    case stt       // 음성 → 텍스트 변환
    case mcp       // MCP 도구 실행
    case screen    // 화면 표시 (GUI)
    case speaker   // 스피커 출력
    case mic       // 마이크 입력
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
