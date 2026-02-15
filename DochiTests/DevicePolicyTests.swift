import XCTest
@testable import Dochi

// MARK: - DeviceType Tests

final class DeviceTypeTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(DeviceType.allCases.count, 3)
    }

    func testDisplayNames() {
        XCTAssertEqual(DeviceType.desktop.displayName, "데스크탑")
        XCTAssertEqual(DeviceType.mobile.displayName, "모바일")
        XCTAssertEqual(DeviceType.cli.displayName, "CLI")
    }

    func testIconNames() {
        XCTAssertEqual(DeviceType.desktop.iconName, "desktopcomputer")
        XCTAssertEqual(DeviceType.mobile.iconName, "iphone")
        XCTAssertEqual(DeviceType.cli.iconName, "terminal")
    }

    func testDefaultPriorities() {
        XCTAssertEqual(DeviceType.desktop.defaultPriority, 0)
        XCTAssertEqual(DeviceType.mobile.defaultPriority, 1)
        XCTAssertEqual(DeviceType.cli.defaultPriority, 2)
    }
}

// MARK: - DevicePlatform Tests

final class DevicePlatformTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(DevicePlatform.allCases.count, 3)
    }

    func testDisplayNames() {
        XCTAssertEqual(DevicePlatform.macos.displayName, "macOS")
        XCTAssertEqual(DevicePlatform.ios.displayName, "iOS")
        XCTAssertEqual(DevicePlatform.cli.displayName, "CLI")
    }
}

// MARK: - DeviceCapabilities Tests

final class DeviceCapabilitiesTests: XCTestCase {

    func testDesktopCapabilities() {
        let caps = DeviceCapabilities.desktop
        XCTAssertTrue(caps.supportsVoice)
        XCTAssertTrue(caps.supportsTTS)
        XCTAssertTrue(caps.supportsNotifications)
        XCTAssertTrue(caps.supportsTools)
    }

    func testMobileCapabilities() {
        let caps = DeviceCapabilities.mobile
        XCTAssertTrue(caps.supportsVoice)
        XCTAssertTrue(caps.supportsTTS)
        XCTAssertTrue(caps.supportsNotifications)
        XCTAssertFalse(caps.supportsTools)
    }

    func testCLICapabilities() {
        let caps = DeviceCapabilities.cli
        XCTAssertFalse(caps.supportsVoice)
        XCTAssertFalse(caps.supportsTTS)
        XCTAssertFalse(caps.supportsNotifications)
        XCTAssertTrue(caps.supportsTools)
    }
}

// MARK: - DeviceInfo Tests

final class DeviceInfoTests: XCTestCase {

    func testDefaultInitialization() {
        let device = DeviceInfo(
            name: "Test Mac",
            deviceType: .desktop,
            platform: .macos
        )
        XCTAssertEqual(device.name, "Test Mac")
        XCTAssertEqual(device.deviceType, .desktop)
        XCTAssertEqual(device.platform, .macos)
        XCTAssertEqual(device.priority, 0)  // desktop default
        XCTAssertFalse(device.isCurrentDevice)
        XCTAssertTrue(device.capabilities.supportsVoice)
    }

    func testMobileDefaults() {
        let device = DeviceInfo(
            name: "iPhone",
            deviceType: .mobile,
            platform: .ios
        )
        XCTAssertEqual(device.priority, 1)
        XCTAssertFalse(device.capabilities.supportsTools)
    }

    func testCLIDefaults() {
        let device = DeviceInfo(
            name: "CLI",
            deviceType: .cli,
            platform: .cli
        )
        XCTAssertEqual(device.priority, 2)
        XCTAssertFalse(device.capabilities.supportsVoice)
    }

    func testIsOnlineTrue() {
        let device = DeviceInfo(
            name: "Test",
            deviceType: .desktop,
            platform: .macos,
            lastSeen: Date()
        )
        XCTAssertTrue(device.isOnline)
    }

    func testIsOnlineFalse() {
        let device = DeviceInfo(
            name: "Test",
            deviceType: .desktop,
            platform: .macos,
            lastSeen: Date().addingTimeInterval(-200)
        )
        XCTAssertFalse(device.isOnline)
    }

    func testStatusTextCurrentDevice() {
        let device = DeviceInfo(
            name: "Test",
            deviceType: .desktop,
            platform: .macos,
            isCurrentDevice: true
        )
        XCTAssertEqual(device.statusText, "이 디바이스")
    }

    func testStatusTextOnline() {
        let device = DeviceInfo(
            name: "Test",
            deviceType: .desktop,
            platform: .macos,
            lastSeen: Date()
        )
        XCTAssertEqual(device.statusText, "온라인")
    }

    func testStatusTextOffline() {
        let device = DeviceInfo(
            name: "Test",
            deviceType: .desktop,
            platform: .macos,
            lastSeen: Date().addingTimeInterval(-300)
        )
        // Should contain some relative time text (not "온라인" or "이 디바이스")
        XCTAssertNotEqual(device.statusText, "온라인")
        XCTAssertNotEqual(device.statusText, "이 디바이스")
    }

    func testEquatable() {
        let id = UUID()
        let date = Date()
        let device1 = DeviceInfo(id: id, name: "Test", deviceType: .desktop, platform: .macos, lastSeen: date)
        let device2 = DeviceInfo(id: id, name: "Test", deviceType: .desktop, platform: .macos, lastSeen: date)
        XCTAssertEqual(device1, device2)
    }

    func testCodableRoundtrip() throws {
        let original = DeviceInfo(
            name: "My Mac",
            deviceType: .desktop,
            platform: .macos,
            lastSeen: Date(),
            isCurrentDevice: true,
            priority: 0,
            capabilities: .desktop
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DeviceInfo.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.deviceType, original.deviceType)
        XCTAssertEqual(decoded.platform, original.platform)
        XCTAssertEqual(decoded.isCurrentDevice, original.isCurrentDevice)
        XCTAssertEqual(decoded.priority, original.priority)
        XCTAssertEqual(decoded.capabilities, original.capabilities)
    }
}

// MARK: - DeviceSelectionPolicy Tests

final class DeviceSelectionPolicyTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(DeviceSelectionPolicy.allCases.count, 3)
    }

    func testDisplayNames() {
        XCTAssertEqual(DeviceSelectionPolicy.priorityBased.displayName, "우선순위 기반")
        XCTAssertEqual(DeviceSelectionPolicy.lastActive.displayName, "최근 활성")
        XCTAssertEqual(DeviceSelectionPolicy.manual.displayName, "수동 선택")
    }

    func testDescriptionsNotEmpty() {
        for policy in DeviceSelectionPolicy.allCases {
            XCTAssertFalse(policy.description.isEmpty)
        }
    }

    func testIconNames() {
        XCTAssertEqual(DeviceSelectionPolicy.priorityBased.iconName, "list.number")
        XCTAssertEqual(DeviceSelectionPolicy.lastActive.iconName, "clock.arrow.circlepath")
        XCTAssertEqual(DeviceSelectionPolicy.manual.iconName, "hand.tap")
    }

    func testCodableRoundtrip() throws {
        let original = DeviceSelectionPolicy.lastActive
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeviceSelectionPolicy.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

// MARK: - DeviceNegotiationResult Tests

final class DeviceNegotiationResultTests: XCTestCase {

    func testDisplayTextThisDevice() {
        XCTAssertEqual(DeviceNegotiationResult.thisDevice.displayText, "이 디바이스가 응답")
    }

    func testDisplayTextOtherDevice() {
        let device = DeviceInfo(name: "iPhone", deviceType: .mobile, platform: .ios)
        XCTAssertEqual(DeviceNegotiationResult.otherDevice(device).displayText, "iPhone이(가) 응답")
    }

    func testDisplayTextNoDevice() {
        XCTAssertEqual(DeviceNegotiationResult.noDeviceAvailable.displayText, "응답 가능한 디바이스 없음")
    }

    func testDisplayTextSingleDevice() {
        XCTAssertEqual(DeviceNegotiationResult.singleDevice.displayText, "단일 디바이스")
    }

    func testEquatable() {
        XCTAssertEqual(DeviceNegotiationResult.thisDevice, DeviceNegotiationResult.thisDevice)
        XCTAssertEqual(DeviceNegotiationResult.noDeviceAvailable, DeviceNegotiationResult.noDeviceAvailable)
        XCTAssertNotEqual(DeviceNegotiationResult.thisDevice, DeviceNegotiationResult.singleDevice)
    }
}

// MARK: - MockDevicePolicyService Tests

@MainActor
final class MockDevicePolicyServiceTests: XCTestCase {

    func testEvaluateResponderNoDevices() {
        let mock = MockDevicePolicyService()
        let result = mock.evaluateResponder()
        XCTAssertEqual(result, .noDeviceAvailable)
    }

    func testEvaluateResponderSingleDevice() {
        let mock = MockDevicePolicyService()
        mock.registeredDevices = [
            DeviceInfo(name: "Mac", deviceType: .desktop, platform: .macos, lastSeen: Date(), isCurrentDevice: true)
        ]
        mock.currentDevice = mock.registeredDevices[0]
        let result = mock.evaluateResponder()
        XCTAssertEqual(result, .singleDevice)
    }

    func testEvaluateResponderPriorityBased() {
        let mock = MockDevicePolicyService()
        mock.currentPolicy = .priorityBased
        let currentId = UUID()
        let otherId = UUID()

        mock.registeredDevices = [
            DeviceInfo(id: currentId, name: "Mac", deviceType: .desktop, platform: .macos, lastSeen: Date(), isCurrentDevice: true, priority: 1),
            DeviceInfo(id: otherId, name: "iPhone", deviceType: .mobile, platform: .ios, lastSeen: Date(), isCurrentDevice: false, priority: 0),
        ]
        mock.currentDevice = mock.registeredDevices[0]

        let result = mock.evaluateResponder()
        // iPhone has priority 0 (highest), so it should be chosen
        if case .otherDevice(let device) = result {
            XCTAssertEqual(device.id, otherId)
        } else {
            XCTFail("Expected otherDevice result, got \(result)")
        }
    }

    func testEvaluateResponderLastActive() {
        let mock = MockDevicePolicyService()
        mock.currentPolicy = .lastActive
        let currentId = UUID()
        let otherId = UUID()

        mock.registeredDevices = [
            DeviceInfo(id: currentId, name: "Mac", deviceType: .desktop, platform: .macos, lastSeen: Date().addingTimeInterval(-60), isCurrentDevice: true),
            DeviceInfo(id: otherId, name: "iPhone", deviceType: .mobile, platform: .ios, lastSeen: Date(), isCurrentDevice: false),
        ]
        mock.currentDevice = mock.registeredDevices[0]

        let result = mock.evaluateResponder()
        // iPhone is more recently active
        if case .otherDevice(let device) = result {
            XCTAssertEqual(device.id, otherId)
        } else {
            XCTFail("Expected otherDevice result, got \(result)")
        }
    }

    func testEvaluateResponderManual() {
        let mock = MockDevicePolicyService()
        mock.currentPolicy = .manual
        let currentId = UUID()

        mock.registeredDevices = [
            DeviceInfo(id: currentId, name: "Mac", deviceType: .desktop, platform: .macos, lastSeen: Date(), isCurrentDevice: true),
            DeviceInfo(name: "iPhone", deviceType: .mobile, platform: .ios, lastSeen: Date(), isCurrentDevice: false),
        ]
        mock.currentDevice = mock.registeredDevices[0]
        mock.manualDeviceId = currentId

        let result = mock.evaluateResponder()
        XCTAssertEqual(result, .thisDevice)
    }

    func testShouldThisDeviceRespondTrue() {
        let mock = MockDevicePolicyService()
        mock.registeredDevices = [
            DeviceInfo(name: "Mac", deviceType: .desktop, platform: .macos, lastSeen: Date(), isCurrentDevice: true)
        ]
        mock.currentDevice = mock.registeredDevices[0]
        XCTAssertTrue(mock.shouldThisDeviceRespond())
    }

    func testShouldThisDeviceRespondFalse() {
        let mock = MockDevicePolicyService()
        mock.currentPolicy = .priorityBased
        let currentId = UUID()

        mock.registeredDevices = [
            DeviceInfo(id: currentId, name: "Mac", deviceType: .desktop, platform: .macos, lastSeen: Date(), isCurrentDevice: true, priority: 1),
            DeviceInfo(name: "iPhone", deviceType: .mobile, platform: .ios, lastSeen: Date(), isCurrentDevice: false, priority: 0),
        ]
        mock.currentDevice = mock.registeredDevices[0]
        XCTAssertFalse(mock.shouldThisDeviceRespond())
    }

    func testRemoveDevice() {
        let mock = MockDevicePolicyService()
        let id = UUID()
        mock.registeredDevices = [
            DeviceInfo(id: id, name: "iPhone", deviceType: .mobile, platform: .ios)
        ]
        mock.removeDevice(id: id)
        XCTAssertTrue(mock.registeredDevices.isEmpty)
        XCTAssertEqual(mock.removedIds, [id])
    }

    func testRenameDevice() {
        let mock = MockDevicePolicyService()
        let id = UUID()
        mock.registeredDevices = [
            DeviceInfo(id: id, name: "Old Name", deviceType: .desktop, platform: .macos)
        ]
        mock.renameDevice(id: id, name: "New Name")
        XCTAssertEqual(mock.registeredDevices[0].name, "New Name")
    }

    func testReorderPriority() {
        let mock = MockDevicePolicyService()
        let id1 = UUID()
        let id2 = UUID()
        mock.registeredDevices = [
            DeviceInfo(id: id1, name: "Device 1", deviceType: .desktop, platform: .macos, priority: 0),
            DeviceInfo(id: id2, name: "Device 2", deviceType: .mobile, platform: .ios, priority: 1),
        ]
        // Reverse order
        mock.reorderPriority(deviceIds: [id2, id1])
        XCTAssertEqual(mock.registeredDevices.first(where: { $0.id == id2 })?.priority, 0)
        XCTAssertEqual(mock.registeredDevices.first(where: { $0.id == id1 })?.priority, 1)
    }

    func testSetPolicy() {
        let mock = MockDevicePolicyService()
        mock.setPolicy(.lastActive)
        XCTAssertEqual(mock.currentPolicy, .lastActive)
    }

    func testSetManualDevice() {
        let mock = MockDevicePolicyService()
        let id = UUID()
        mock.setManualDevice(id: id)
        XCTAssertEqual(mock.manualDeviceId, id)
    }
}

// MARK: - DevicePolicyService File Persistence Tests

@MainActor
final class DevicePolicyServicePersistenceTests: XCTestCase {
    var tempDir: URL!
    var storageURL: URL!
    var settings: AppSettings!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storageURL = tempDir.appendingPathComponent("devices.json")
        settings = AppSettings()
        // Reset relevant defaults
        UserDefaults.standard.removeObject(forKey: "deviceSelectionPolicy")
        UserDefaults.standard.removeObject(forKey: "manualResponderDeviceId")
        UserDefaults.standard.removeObject(forKey: "deviceId")
        UserDefaults.standard.removeObject(forKey: "currentDeviceName")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRegisterCurrentDevice() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service.registerCurrentDevice()

        XCTAssertEqual(service.registeredDevices.count, 1)
        XCTAssertNotNil(service.currentDevice)
        XCTAssertTrue(service.currentDevice!.isCurrentDevice)
        XCTAssertFalse(settings.deviceId.isEmpty)
    }

    func testRegisterCurrentDevicePreservesExistingId() async {
        let existingId = UUID()
        settings.deviceId = existingId.uuidString

        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service.registerCurrentDevice()

        XCTAssertEqual(service.currentDevice?.id, existingId)
        XCTAssertEqual(settings.deviceId, existingId.uuidString)
    }

    func testPersistenceRoundtrip() async {
        // Create and register
        let service1 = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service1.registerCurrentDevice()
        let deviceId = service1.currentDevice!.id

        // Create new service instance pointing to same storage
        let service2 = DevicePolicyService(settings: settings, storageURL: storageURL)
        XCTAssertEqual(service2.registeredDevices.count, 1)
        XCTAssertEqual(service2.registeredDevices[0].id, deviceId)
    }

    func testSetPolicyPersistsToSettings() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        service.setPolicy(.lastActive)
        XCTAssertEqual(settings.deviceSelectionPolicy, "lastActive")
    }

    func testSetManualDevicePersistsToSettings() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        let id = UUID()
        service.setManualDevice(id: id)
        XCTAssertEqual(settings.manualResponderDeviceId, id.uuidString)
    }

    func testRemoveDevice() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service.registerCurrentDevice()

        // Add a second device manually
        let otherDevice = DeviceInfo(name: "iPhone", deviceType: .mobile, platform: .ios)
        service.registeredDevices.append(otherDevice)
        XCTAssertEqual(service.registeredDevices.count, 2)

        service.removeDevice(id: otherDevice.id)
        XCTAssertEqual(service.registeredDevices.count, 1)
    }

    func testCannotRemoveCurrentDevice() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service.registerCurrentDevice()
        let currentId = service.currentDevice!.id

        service.removeDevice(id: currentId)
        // Should still have current device
        XCTAssertEqual(service.registeredDevices.count, 1)
    }

    func testRenameDevice() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service.registerCurrentDevice()
        let id = service.currentDevice!.id

        service.renameDevice(id: id, name: "My Custom Name")
        XCTAssertEqual(service.currentDevice?.name, "My Custom Name")
        XCTAssertEqual(settings.currentDeviceName, "My Custom Name")
    }

    func testReorderPriority() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service.registerCurrentDevice()

        let device2 = DeviceInfo(name: "iPhone", deviceType: .mobile, platform: .ios, priority: 1)
        service.registeredDevices.append(device2)

        let currentId = service.currentDevice!.id
        service.reorderPriority(deviceIds: [device2.id, currentId])

        XCTAssertEqual(service.registeredDevices.first(where: { $0.id == device2.id })?.priority, 0)
        XCTAssertEqual(service.registeredDevices.first(where: { $0.id == currentId })?.priority, 1)
    }

    func testDefaultPolicyIsPriorityBased() {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        XCTAssertEqual(service.currentPolicy, .priorityBased)
    }

    func testRestorePolicyFromSettings() {
        settings.deviceSelectionPolicy = "manual"
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        XCTAssertEqual(service.currentPolicy, .manual)
    }
}

// MARK: - DevicePolicyService Evaluation Tests

@MainActor
final class DevicePolicyServiceEvaluationTests: XCTestCase {
    var tempDir: URL!
    var storageURL: URL!
    var settings: AppSettings!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storageURL = tempDir.appendingPathComponent("devices.json")
        settings = AppSettings()
        UserDefaults.standard.removeObject(forKey: "deviceSelectionPolicy")
        UserDefaults.standard.removeObject(forKey: "manualResponderDeviceId")
        UserDefaults.standard.removeObject(forKey: "deviceId")
        UserDefaults.standard.removeObject(forKey: "currentDeviceName")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testEvaluateResponderSingleDevice() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service.registerCurrentDevice()

        let result = service.evaluateResponder()
        XCTAssertEqual(result, .singleDevice)
    }

    func testShouldThisDeviceRespondSingleDevice() async {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        await service.registerCurrentDevice()

        XCTAssertTrue(service.shouldThisDeviceRespond())
    }

    func testEvaluateResponderNoDevices() {
        let service = DevicePolicyService(settings: settings, storageURL: storageURL)
        let result = service.evaluateResponder()
        XCTAssertEqual(result, .noDeviceAvailable)
    }
}

// MARK: - SettingsSection Devices Tests

final class SettingsSectionDevicesTests: XCTestCase {

    func testDevicesSectionExists() {
        XCTAssertNotNil(SettingsSection.devices)
    }

    func testDevicesSectionProperties() {
        let section = SettingsSection.devices
        XCTAssertEqual(section.title, "디바이스")
        XCTAssertEqual(section.icon, "laptopcomputer.and.iphone")
        XCTAssertEqual(section.group, .connection)
        XCTAssertEqual(section.rawValue, "devices")
    }

    func testDevicesSectionSearchKeywords() {
        let section = SettingsSection.devices
        XCTAssertTrue(section.matches(query: "디바이스"))
        XCTAssertTrue(section.matches(query: "device"))
        XCTAssertTrue(section.matches(query: "멀티"))
        XCTAssertTrue(section.matches(query: "우선순위"))
        XCTAssertTrue(section.matches(query: "priority"))
    }
}

// MARK: - CommandPalette Device Items Tests

final class CommandPaletteDeviceItemsTests: XCTestCase {

    func testConnectedDevicesPaletteItem() {
        let item = CommandPaletteRegistry.staticItems.first { $0.id == "connected-devices" }
        XCTAssertNotNil(item, "connected-devices palette item should exist")
        XCTAssertEqual(item?.title, "연결된 디바이스")
        XCTAssertEqual(item?.category, .navigation)
    }

    func testDeviceSettingsPaletteItem() {
        let item = CommandPaletteRegistry.staticItems.first { $0.id == "settings.open.devices" }
        XCTAssertNotNil(item, "settings.open.devices palette item should exist")
        XCTAssertEqual(item?.title, "디바이스 설정")
        XCTAssertEqual(item?.category, .settings)
    }
}
