import Foundation
import os

/// Manages device registration and periodic heartbeat pings to Supabase.
/// Sends a heartbeat every 30 seconds to keep the device marked as online.
@MainActor
final class DeviceHeartbeatService {
    private let supabaseService: SupabaseServiceProtocol
    private let settings: AppSettings

    private var heartbeatTask: Task<Void, Never>?
    private(set) var currentDeviceId: UUID?
    private(set) var isRunning = false

    static let heartbeatIntervalSeconds: Int = 30

    init(supabaseService: SupabaseServiceProtocol, settings: AppSettings) {
        self.supabaseService = supabaseService
        self.settings = settings
    }

    /// Register this device and start sending heartbeats.
    func startHeartbeat(workspaceIds: [UUID]) async {
        guard supabaseService.isConfigured, supabaseService.authState.userId != nil else {
            Log.cloud.debug("DeviceHeartbeat: skipping — not configured or not signed in")
            return
        }

        // Register the device
        let deviceName = Host.current().localizedName ?? "Mac"
        do {
            let device = try await supabaseService.registerDevice(
                name: deviceName,
                workspaceIds: workspaceIds
            )
            currentDeviceId = device.id
            settings.deviceId = device.id.uuidString
            Log.cloud.info("Device registered: \(deviceName) (\(device.id))")
        } catch {
            Log.cloud.error("Device registration failed: \(error.localizedDescription)")
            return
        }

        isRunning = true
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatIntervalSeconds))
                guard !Task.isCancelled else { break }
                await self?.sendHeartbeat()
            }
        }
    }

    /// Stop sending heartbeats.
    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        isRunning = false
        Log.cloud.info("DeviceHeartbeat stopped")
    }

    /// Update this device's workspace list.
    func updateWorkspaces(_ workspaceIds: [UUID]) async {
        guard let deviceId = currentDeviceId else { return }
        do {
            try await supabaseService.updateDeviceWorkspaces(
                deviceId: deviceId,
                workspaceIds: workspaceIds
            )
        } catch {
            Log.cloud.error("Failed to update device workspaces: \(error.localizedDescription)")
        }
    }

    private func sendHeartbeat() async {
        guard let deviceId = currentDeviceId else { return }
        do {
            try await supabaseService.updateDeviceHeartbeat(deviceId: deviceId)
        } catch {
            Log.cloud.warning("Device heartbeat failed: \(error.localizedDescription)")
        }
    }
}
