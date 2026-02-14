import XCTest
@testable import Dochi

@MainActor
final class DeviceRegistrationTests: XCTestCase {

    // MARK: - Device Model

    func testDeviceDefaultValues() {
        let device = Device(userId: UUID(), name: "Test Mac")
        XCTAssertEqual(device.platform, "macos")
        XCTAssertTrue(device.workspaceIds.isEmpty)
        XCTAssertTrue(device.isOnline) // Just created, should be online
    }

    func testDeviceIsOfflineAfterTimeout() {
        let device = Device(
            userId: UUID(),
            name: "Old Mac",
            lastHeartbeat: Date().addingTimeInterval(-300) // 5 minutes ago
        )
        XCTAssertFalse(device.isOnline)
    }

    func testDeviceIsOnlineWithinThreshold() {
        let device = Device(
            userId: UUID(),
            name: "Recent Mac",
            lastHeartbeat: Date().addingTimeInterval(-60) // 1 minute ago
        )
        XCTAssertTrue(device.isOnline)
    }

    func testDeviceCodingKeys() throws {
        let device = Device(
            userId: UUID(),
            name: "Encoded Mac",
            workspaceIds: [UUID()]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(device)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["user_id"])
        XCTAssertNotNil(json["last_heartbeat"])
        XCTAssertNotNil(json["workspace_ids"])
        XCTAssertNil(json["userId"]) // Should use snake_case
    }

    func testDeviceRoundTrip() throws {
        let wsId = UUID()
        let original = Device(
            userId: UUID(),
            name: "Roundtrip Mac",
            workspaceIds: [wsId]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Device.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.userId, original.userId)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.platform, original.platform)
        XCTAssertEqual(decoded.workspaceIds, [wsId])
    }

    // MARK: - MockSupabaseService Device Methods

    func testMockRegisterDevice() async throws {
        let mock = MockSupabaseService()
        let device = try await mock.registerDevice(name: "Test", workspaceIds: [UUID()])
        XCTAssertEqual(device.name, "Test")
        XCTAssertEqual(mock.registeredDevices.count, 1)
    }

    func testMockUpdateHeartbeat() async throws {
        let mock = MockSupabaseService()
        let deviceId = UUID()
        try await mock.updateDeviceHeartbeat(deviceId: deviceId)
        XCTAssertEqual(mock.heartbeatCalls, [deviceId])
    }

    func testMockUpdateWorkspaces() async throws {
        let mock = MockSupabaseService()
        let device = try await mock.registerDevice(name: "Test", workspaceIds: [])
        let wsId = UUID()
        try await mock.updateDeviceWorkspaces(deviceId: device.id, workspaceIds: [wsId])
        let updated = mock.registeredDevices.first(where: { $0.id == device.id })
        XCTAssertEqual(updated?.workspaceIds, [wsId])
    }

    func testMockListDevices() async throws {
        let mock = MockSupabaseService()
        _ = try await mock.registerDevice(name: "A", workspaceIds: [])
        _ = try await mock.registerDevice(name: "B", workspaceIds: [])
        let devices = try await mock.listDevices()
        XCTAssertEqual(devices.count, 2)
    }

    func testMockRemoveDevice() async throws {
        let mock = MockSupabaseService()
        let device = try await mock.registerDevice(name: "ToDelete", workspaceIds: [])
        try await mock.removeDevice(id: device.id)
        XCTAssertTrue(mock.removedDeviceIds.contains(device.id))
        XCTAssertTrue(mock.registeredDevices.isEmpty)
    }

    // MARK: - DeviceHeartbeatService

    func testHeartbeatServiceInit() {
        let mock = MockSupabaseService()
        let settings = AppSettings()
        let service = DeviceHeartbeatService(supabaseService: mock, settings: settings)
        XCTAssertNil(service.currentDeviceId)
        XCTAssertFalse(service.isRunning)
    }

    func testHeartbeatStartRegistersDevice() async {
        let mock = MockSupabaseService()
        let settings = AppSettings()
        let service = DeviceHeartbeatService(supabaseService: mock, settings: settings)

        let wsId = UUID()
        await service.startHeartbeat(workspaceIds: [wsId])

        XCTAssertNotNil(service.currentDeviceId)
        XCTAssertTrue(service.isRunning)
        XCTAssertEqual(mock.registeredDevices.count, 1)
        XCTAssertEqual(mock.registeredDevices.first?.workspaceIds, [wsId])

        service.stopHeartbeat()
        XCTAssertFalse(service.isRunning)
    }

    func testHeartbeatSkipsWhenNotConfigured() async {
        let mock = MockSupabaseService()
        mock.isConfigured = false
        let settings = AppSettings()
        let service = DeviceHeartbeatService(supabaseService: mock, settings: settings)

        await service.startHeartbeat(workspaceIds: [])
        XCTAssertNil(service.currentDeviceId)
        XCTAssertFalse(service.isRunning)
    }

    func testHeartbeatSkipsWhenNotAuthenticated() async {
        let mock = MockSupabaseService()
        mock.authState = .signedOut
        let settings = AppSettings()
        let service = DeviceHeartbeatService(supabaseService: mock, settings: settings)

        await service.startHeartbeat(workspaceIds: [])
        XCTAssertNil(service.currentDeviceId)
        XCTAssertFalse(service.isRunning)
    }

    func testHeartbeatUpdateWorkspaces() async {
        let mock = MockSupabaseService()
        let settings = AppSettings()
        let service = DeviceHeartbeatService(supabaseService: mock, settings: settings)

        await service.startHeartbeat(workspaceIds: [])
        let newWsId = UUID()
        await service.updateWorkspaces([newWsId])

        let device = mock.registeredDevices.first(where: { $0.id == service.currentDeviceId })
        XCTAssertEqual(device?.workspaceIds, [newWsId])

        service.stopHeartbeat()
    }

    func testHeartbeatIntervalIs30Seconds() {
        XCTAssertEqual(DeviceHeartbeatService.heartbeatIntervalSeconds, 30)
    }

    // MARK: - AppSettings deviceId

    func testDeviceIdSetting() {
        let settings = AppSettings()
        XCTAssertEqual(settings.deviceId, UserDefaults.standard.string(forKey: "deviceId") ?? "")
    }
}
