import Foundation
@testable import Dochi

@MainActor
final class MockDeviceService: DeviceServiceProtocol {
    var currentDevice: DeviceInfo?
    var workspaceDevices: [DeviceInfo] = []
    var onlinePeers: [DeviceInfo] = []
    var registerCalled = false
    var heartbeatStarted = false

    func registerDevice() async throws {
        registerCalled = true
        currentDevice = DeviceInfo(
            id: UUID(),
            workspaceId: UUID(),
            userId: UUID(),
            deviceName: "Test Mac",
            platform: "macOS",
            isOnline: true,
            lastSeenAt: Date(),
            createdAt: Date(),
            capabilities: ["tts", "stt", "mcp", "screen", "speaker", "mic"]
        )
    }

    func startHeartbeat() {
        heartbeatStarted = true
    }

    func stopHeartbeat() {
        heartbeatStarted = false
    }

    func fetchWorkspaceDevices() async throws -> [DeviceInfo] {
        workspaceDevices
    }

    func fetchOnlinePeers() async throws -> [DeviceInfo] {
        onlinePeers
    }

    func subscribeToPeerChanges() {}
    func unsubscribeFromPeerChanges() {}

    func updateDeviceName(_ name: String) async throws {
        currentDevice?.deviceName = name
    }

    func removeDevice(id: UUID) async throws {
        workspaceDevices.removeAll { $0.id == id }
    }
}
