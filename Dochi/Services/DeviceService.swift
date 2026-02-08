import Foundation
import Supabase
import os

@MainActor
final class DeviceService: ObservableObject, DeviceServiceProtocol {
    @Published private(set) var currentDevice: DeviceInfo?
    @Published private(set) var workspaceDevices: [DeviceInfo] = []
    @Published private(set) var onlinePeers: [DeviceInfo] = []

    /// 피어 상태가 변경되었을 때 호출 (온라인/오프라인)
    var onPeerStatusChanged: (([DeviceInfo]) -> Void)?

    private let supabaseService: SupabaseService
    private let keychainService: KeychainServiceProtocol
    private var heartbeatTask: Task<Void, Never>?
    private var peerDiscoveryTask: Task<Void, Never>?

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
        let caps = detectCapabilities()

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
                .update(DeviceRegistrationUpdate(
                    is_online: true,
                    last_seen_at: Date(),
                    capabilities: caps
                ))
                .eq("id", value: deviceId)
                .select()
                .single()
                .execute()
                .value
            currentDevice = updated
            Log.cloud.info("디바이스 재등록: \(device.deviceName, privacy: .public) [\(caps.joined(separator: ", "), privacy: .public)]")
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
                    last_seen_at: Date(),
                    capabilities: caps
                ))
                .select()
                .single()
                .execute()
                .value
            currentDevice = device
            Log.cloud.info("디바이스 등록: \(deviceName, privacy: .public) [\(caps.joined(separator: ", "), privacy: .public)]")
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

    // MARK: - Peer Discovery

    /// 같은 워크스페이스의 온라인 피어 목록 조회 (자신 제외)
    func fetchOnlinePeers() async throws -> [DeviceInfo] {
        guard let client = supabaseService.client,
              let workspaceId = supabaseService.selectedWorkspace?.id,
              let selfId = currentDevice?.id else {
            return []
        }

        let peers: [DeviceInfo] = try await client
            .from("devices")
            .select()
            .eq("workspace_id", value: workspaceId)
            .eq("is_online", value: true)
            .neq("id", value: selfId)
            .order("last_seen_at", ascending: false)
            .execute()
            .value

        onlinePeers = peers
        return peers
    }

    /// 특정 기능을 가진 온라인 피어 필터링
    func findPeers(withCapability capability: DeviceCapability) -> [DeviceInfo] {
        onlinePeers.filter { $0.capabilities.contains(capability.rawValue) }
    }

    /// Realtime으로 피어 온라인/오프라인 상태 변경 감지
    func subscribeToPeerChanges() {
        guard let client = supabaseService.client,
              let workspaceId = supabaseService.selectedWorkspace?.id else { return }
        unsubscribeFromPeerChanges()

        peerDiscoveryTask = Task { [weak self] in
            let channel = client.realtimeV2.channel("peers-\(workspaceId.uuidString)")

            let changes = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "devices",
                filter: .eq("workspace_id", value: workspaceId)
            )

            do {
                try await channel.subscribeWithError()
                Log.cloud.info("피어 상태 Realtime 구독 시작")
            } catch {
                Log.cloud.warning("피어 상태 Realtime 구독 실패: \(error, privacy: .public)")
                return
            }

            for await update in changes {
                guard !Task.isCancelled else { break }
                await self?.handlePeerStatusUpdate(update)
            }
        }
    }

    func unsubscribeFromPeerChanges() {
        peerDiscoveryTask?.cancel()
        peerDiscoveryTask = nil
    }

    private func handlePeerStatusUpdate(_ update: UpdateAction) {
        do {
            let device = try update.decodeRecord(as: DeviceInfo.self, decoder: PostgrestClient.Configuration.jsonDecoder)
            // 자기 자신은 무시
            guard device.id != currentDevice?.id else { return }

            // 온라인 피어 목록 업데이트
            if device.isOnline {
                if let index = onlinePeers.firstIndex(where: { $0.id == device.id }) {
                    onlinePeers[index] = device
                } else {
                    onlinePeers.append(device)
                    Log.cloud.info("피어 온라인: \(device.deviceName, privacy: .public)")
                }
            } else {
                if onlinePeers.contains(where: { $0.id == device.id }) {
                    onlinePeers.removeAll { $0.id == device.id }
                    Log.cloud.info("피어 오프라인: \(device.deviceName, privacy: .public)")
                }
            }

            // 워크스페이스 디바이스 목록도 업데이트
            if let index = workspaceDevices.firstIndex(where: { $0.id == device.id }) {
                workspaceDevices[index] = device
            }

            onPeerStatusChanged?(onlinePeers)
        } catch {
            Log.cloud.warning("피어 상태 디코딩 실패: \(error, privacy: .public)")
        }
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

    /// macOS 디바이스의 기능 목록 감지
    // TODO: iOS/watchOS 클라이언트 추가 시 런타임 기능 탐지로 전환 필요
    private func detectCapabilities() -> [String] {
        var caps: [String] = []
        // macOS는 기본적으로 모든 기능 지원
        caps.append(DeviceCapability.screen.rawValue)
        caps.append(DeviceCapability.tts.rawValue)
        caps.append(DeviceCapability.stt.rawValue)
        caps.append(DeviceCapability.mcp.rawValue)
        caps.append(DeviceCapability.speaker.rawValue)
        caps.append(DeviceCapability.mic.rawValue)
        return caps
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
    let capabilities: [String]
}

private struct DeviceUpdate: Encodable {
    let is_online: Bool
    let last_seen_at: Date
}

private struct DeviceRegistrationUpdate: Encodable {
    let is_online: Bool
    let last_seen_at: Date
    let capabilities: [String]
}
