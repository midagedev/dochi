import Foundation
@testable import Dochi

@MainActor
final class MockDeviceService: DeviceServiceProtocol {
    var currentDevice: DeviceInfo?
    var workspaceDevices: [DeviceInfo] = []
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
            createdAt: Date()
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

    func updateDeviceName(_ name: String) async throws {
        currentDevice?.deviceName = name
    }

    func removeDevice(id: UUID) async throws {
        workspaceDevices.removeAll { $0.id == id }
    }
}
