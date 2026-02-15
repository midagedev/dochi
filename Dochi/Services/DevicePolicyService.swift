import Foundation
import os

@MainActor
@Observable
final class DevicePolicyService: DevicePolicyServiceProtocol {

    // MARK: - Public State

    var registeredDevices: [DeviceInfo] = []
    var currentDevice: DeviceInfo?
    private(set) var currentPolicy: DeviceSelectionPolicy = .priorityBased

    // MARK: - Private

    private let settings: AppSettings
    private let storageURL: URL
    private var heartbeatTask: Task<Void, Never>? {
        didSet { _heartbeatTaskForCleanup = heartbeatTask }
    }
    nonisolated(unsafe) private var _heartbeatTaskForCleanup: Task<Void, Never>?
    private var manualDeviceId: UUID?

    private static let heartbeatInterval: TimeInterval = 30
    private static let onlineThreshold: TimeInterval = 120

    // MARK: - Init

    init(settings: AppSettings, storageURL: URL? = nil) {
        self.settings = settings
        self.storageURL = storageURL ?? {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dochiDir = appSupport.appendingPathComponent("Dochi")
            return dochiDir.appendingPathComponent("devices.json")
        }()

        loadFromDisk()
        restorePolicy()
        restoreManualDeviceId()
    }

    deinit {
        _heartbeatTaskForCleanup?.cancel()
    }

    // MARK: - Register Current Device

    func registerCurrentDevice() async {
        let deviceId: UUID
        if let existingIdStr = settings.deviceId.isEmpty ? nil : settings.deviceId,
           let existingId = UUID(uuidString: existingIdStr) {
            deviceId = existingId
        } else {
            deviceId = UUID()
            settings.deviceId = deviceId.uuidString
        }

        let deviceName = settings.currentDeviceName.isEmpty
            ? Host.current().localizedName ?? "Mac"
            : settings.currentDeviceName

        // Mark all devices as not current
        for i in registeredDevices.indices {
            registeredDevices[i].isCurrentDevice = false
        }

        if let idx = registeredDevices.firstIndex(where: { $0.id == deviceId }) {
            registeredDevices[idx].lastSeen = Date()
            registeredDevices[idx].isCurrentDevice = true
            registeredDevices[idx].name = deviceName
            currentDevice = registeredDevices[idx]
        } else {
            let device = DeviceInfo(
                id: deviceId,
                name: deviceName,
                deviceType: .desktop,
                platform: .macos,
                lastSeen: Date(),
                isCurrentDevice: true
            )
            registeredDevices.append(device)
            currentDevice = device
        }

        saveToDisk()
        startHeartbeat()
    }

    // MARK: - Activity Update

    func updateCurrentDeviceActivity() {
        guard let deviceId = currentDevice?.id,
              let idx = registeredDevices.firstIndex(where: { $0.id == deviceId }) else { return }
        registeredDevices[idx].lastSeen = Date()
        currentDevice = registeredDevices[idx]
        saveToDisk()
    }

    // MARK: - Device Management

    func removeDevice(id: UUID) {
        guard id != currentDevice?.id else {
            Log.app.warning("Cannot remove current device")
            return
        }
        registeredDevices.removeAll { $0.id == id }
        saveToDisk()
        Log.app.info("Device removed: \(id.uuidString)")
    }

    func renameDevice(id: UUID, name: String) {
        guard let idx = registeredDevices.firstIndex(where: { $0.id == id }) else { return }
        registeredDevices[idx].name = name
        if registeredDevices[idx].isCurrentDevice {
            currentDevice = registeredDevices[idx]
            settings.currentDeviceName = name
        }
        saveToDisk()
    }

    func reorderPriority(deviceIds: [UUID]) {
        for (index, id) in deviceIds.enumerated() {
            if let idx = registeredDevices.firstIndex(where: { $0.id == id }) {
                registeredDevices[idx].priority = index
            }
        }
        registeredDevices.sort { $0.priority < $1.priority }
        saveToDisk()
    }

    // MARK: - Policy

    func setPolicy(_ policy: DeviceSelectionPolicy) {
        currentPolicy = policy
        settings.deviceSelectionPolicy = policy.rawValue
        Log.app.info("Device selection policy changed to: \(policy.rawValue)")
    }

    func setManualDevice(id: UUID) {
        manualDeviceId = id
        settings.manualResponderDeviceId = id.uuidString
    }

    // MARK: - Evaluation

    func evaluateResponder() -> DeviceNegotiationResult {
        let onlineDevices = registeredDevices.filter { $0.isOnline || $0.isCurrentDevice }

        guard !onlineDevices.isEmpty else {
            return .noDeviceAvailable
        }

        if onlineDevices.count == 1 {
            return .singleDevice
        }

        switch currentPolicy {
        case .priorityBased:
            let sorted = onlineDevices.sorted { $0.priority < $1.priority }
            guard let winner = sorted.first else { return .noDeviceAvailable }
            if winner.isCurrentDevice {
                return .thisDevice
            }
            return .otherDevice(winner)

        case .lastActive:
            let sorted = onlineDevices.sorted { $0.lastSeen > $1.lastSeen }
            guard let winner = sorted.first else { return .noDeviceAvailable }
            if winner.isCurrentDevice {
                return .thisDevice
            }
            return .otherDevice(winner)

        case .manual:
            if let manualId = manualDeviceId,
               let device = onlineDevices.first(where: { $0.id == manualId }) {
                if device.isCurrentDevice {
                    return .thisDevice
                }
                return .otherDevice(device)
            }
            // Fallback to current device if manual device not found online
            if let current = onlineDevices.first(where: { $0.isCurrentDevice }) {
                return .thisDevice
            }
            return .noDeviceAvailable
        }
    }

    func shouldThisDeviceRespond() -> Bool {
        let result = evaluateResponder()
        switch result {
        case .thisDevice, .singleDevice:
            return true
        case .otherDevice, .noDeviceAvailable:
            return false
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled else { return }
                self?.updateCurrentDeviceActivity()
            }
        }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(registeredDevices)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.storage.error("Failed to save devices: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            registeredDevices = try decoder.decode([DeviceInfo].self, from: data)
        } catch {
            Log.storage.error("Failed to load devices: \(error.localizedDescription)")
        }
    }

    private func restorePolicy() {
        let policyStr = settings.deviceSelectionPolicy
        currentPolicy = DeviceSelectionPolicy(rawValue: policyStr) ?? .priorityBased
    }

    private func restoreManualDeviceId() {
        let idStr = settings.manualResponderDeviceId
        if !idStr.isEmpty {
            manualDeviceId = UUID(uuidString: idStr)
        }
    }
}
