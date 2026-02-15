import SwiftUI

/// Popover showing connected device status and current policy.
struct ConnectedDevicesPopoverView: View {
    var devicePolicyService: DevicePolicyServiceProtocol
    var onOpenSettings: () -> Void

    var body: some View {
        let responderResult = devicePolicyService.evaluateResponder()

        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("연결된 디바이스")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(onlineCount)/\(devicePolicyService.registeredDevices.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Device list
            if devicePolicyService.registeredDevices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 20))
                        .foregroundStyle(.quaternary)
                    Text("등록된 디바이스가 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(sortedDevices) { device in
                    HStack(spacing: 8) {
                        // Status indicator
                        Circle()
                            .fill(statusColor(for: device, responderResult: responderResult))
                            .frame(width: 8, height: 8)

                        Image(systemName: device.deviceType.iconName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                                .font(.system(size: 12, weight: device.isCurrentDevice ? .semibold : .regular))
                                .lineLimit(1)
                            Text(device.statusText)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isPrimaryResponder(device, responderResult: responderResult) {
                            Text("응답")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue)
                                )
                        }
                    }
                }
            }

            Divider()

            // Policy display
            HStack(spacing: 4) {
                Image(systemName: devicePolicyService.currentPolicy.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(devicePolicyService.currentPolicy.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("설정 열기") {
                    onOpenSettings()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Helpers

    private var onlineCount: Int {
        devicePolicyService.registeredDevices.filter { $0.isOnline || $0.isCurrentDevice }.count
    }

    private var sortedDevices: [DeviceInfo] {
        devicePolicyService.registeredDevices.sorted { a, b in
            if a.isCurrentDevice { return true }
            if b.isCurrentDevice { return false }
            if a.isOnline && !b.isOnline { return true }
            if !a.isOnline && b.isOnline { return false }
            return a.priority < b.priority
        }
    }

    private func statusColor(for device: DeviceInfo, responderResult: DeviceNegotiationResult) -> Color {
        if isPrimaryResponder(device, responderResult: responderResult) {
            return .green
        }
        if device.isCurrentDevice || device.isOnline {
            return .blue
        }
        return .gray
    }

    private func isPrimaryResponder(_ device: DeviceInfo, responderResult: DeviceNegotiationResult) -> Bool {
        switch responderResult {
        case .thisDevice:
            return device.isCurrentDevice
        case .otherDevice(let responder):
            return device.id == responder.id
        case .singleDevice:
            return device.isCurrentDevice
        case .noDeviceAvailable:
            return false
        }
    }
}
