import Foundation
import Supabase
import os

@MainActor
final class DeviceService: ObservableObject, DeviceServiceProtocol {
    @Published private(set) var currentDevice: DeviceInfo?
    @Published private(set) var workspaceDevices: [DeviceInfo] = []

    private let supabaseService: SupabaseService
    private let keychainService: KeychainServiceProtocol
    private var heartbeatTask: Task<Void, Never>?

    private enum KeychainKeys {
        static let deviceId = "device_id"
    }

    private static let heartbeatInterval: TimeInterval = 30

    init(supabaseService: SupabaseService, keychainService: KeychainServiceProtocol = KeychainService()) {
        self.supabaseService = supabaseService
        self.keychainService = keychainService
    }

    // MARK: - Device Registration

    func registerDevice() async throws {
        guard let client = supabaseService.client,
              case .signedIn(let userId, _) = supabaseService.authState,
              let workspaceId = supabaseService.selectedWorkspace?.id else {
            return
        }

        let deviceId = getOrCreateDeviceId()
        let deviceName = Host.current().localizedName ?? "Mac"

        // Check if already registered
        let existing: [DeviceInfo] = try await client
            .from("devices")
            .select()
            .eq("id", value: deviceId)
            .eq("workspace_id", value: workspaceId)
            .execute()
            .value

        if let device = existing.first {
            // Update existing device
            let updated: DeviceInfo = try await client
                .from("devices")
                .update(DeviceUpdate(
                    is_online: true,
                    last_seen_at: Date()
                ))
                .eq("id", value: deviceId)
                .select()
                .single()
                .execute()
                .value
            currentDevice = updated
            Log.cloud.info("디바이스 재등록: \(device.deviceName, privacy: .public)")
        } else {
            // Insert new device
            let device: DeviceInfo = try await client
                .from("devices")
                .insert(DeviceInsert(
                    id: deviceId,
                    workspace_id: workspaceId,
                    user_id: userId,
                    device_name: deviceName,
                    platform: "macOS",
                    is_online: true,
                    last_seen_at: Date()
                ))
                .select()
                .single()
                .execute()
                .value
            currentDevice = device
            Log.cloud.info("디바이스 등록: \(deviceName, privacy: .public)")
        }
    }

    // MARK: - Heartbeat

    func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(DeviceService.heartbeatInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.sendHeartbeat()
            }
        }
        Log.cloud.debug("하트비트 시작")
    }

    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        // Mark offline
        if let deviceId = currentDevice?.id, let client = supabaseService.client {
            Task { @MainActor in
                do {
                    try await client
                        .from("devices")
                        .update(DeviceUpdate(is_online: false, last_seen_at: Date()))
                        .eq("id", value: deviceId)
                        .execute()
                } catch {
                    Log.cloud.warning("오프라인 마킹 실패: \(error, privacy: .public)")
                }
            }
        }
        Log.cloud.debug("하트비트 중지")
    }

    private func sendHeartbeat() async {
        guard let client = supabaseService.client,
              let deviceId = currentDevice?.id else { return }
        do {
            try await client
                .from("devices")
                .update(DeviceUpdate(is_online: true, last_seen_at: Date()))
                .eq("id", value: deviceId)
                .execute()
        } catch {
            Log.cloud.warning("하트비트 실패: \(error, privacy: .public)")
        }
    }

    // MARK: - Device List

    func fetchWorkspaceDevices() async throws -> [DeviceInfo] {
        guard let client = supabaseService.client,
              let workspaceId = supabaseService.selectedWorkspace?.id else {
            return []
        }

        let devices: [DeviceInfo] = try await client
            .from("devices")
            .select()
            .eq("workspace_id", value: workspaceId)
            .order("last_seen_at", ascending: false)
            .execute()
            .value

        workspaceDevices = devices
        return devices
    }

    // MARK: - Device Management

    func updateDeviceName(_ name: String) async throws {
        guard let client = supabaseService.client,
              let deviceId = currentDevice?.id else { return }

        struct NameUpdate: Encodable {
            let device_name: String
        }

        try await client
            .from("devices")
            .update(NameUpdate(device_name: name))
            .eq("id", value: deviceId)
            .execute()

        currentDevice?.deviceName = name
        Log.cloud.info("디바이스 이름 변경: \(name, privacy: .public)")
    }

    func removeDevice(id: UUID) async throws {
        guard let client = supabaseService.client else { return }
        try await client
            .from("devices")
            .delete()
            .eq("id", value: id)
            .execute()

        workspaceDevices.removeAll { $0.id == id }
        if currentDevice?.id == id {
            currentDevice = nil
            stopHeartbeat()
        }
        Log.cloud.info("디바이스 제거: \(id, privacy: .public)")
    }

    // MARK: - Helpers

    private func getOrCreateDeviceId() -> UUID {
        if let idString = keychainService.load(account: KeychainKeys.deviceId),
           let id = UUID(uuidString: idString) {
            return id
        }
        let newId = UUID()
        keychainService.save(account: KeychainKeys.deviceId, value: newId.uuidString)
        return newId
    }
}

// MARK: - DTOs

private struct DeviceInsert: Encodable {
    let id: UUID
    let workspace_id: UUID
    let user_id: UUID
    let device_name: String
    let platform: String
    let is_online: Bool
    let last_seen_at: Date
}

private struct DeviceUpdate: Encodable {
    let is_online: Bool
    let last_seen_at: Date
}
