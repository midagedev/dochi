import SwiftUI

struct DeviceSettingsView: View {
    @ObservedObject var deviceService: DeviceService
    @State private var devices: [DeviceInfo] = []
    @State private var editingName = false
    @State private var newName = ""

    var body: some View {
        Section("디바이스") {
            if devices.isEmpty {
                Text("등록된 디바이스가 없습니다.")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(devices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(device.isOnline ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(device.deviceName)
                                    .font(.body)
                                if device.id == deviceService.currentDevice?.id {
                                    Text("이 기기")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                            }
                            HStack(spacing: 8) {
                                Text(device.platform)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !device.isOnline {
                                    Text("마지막: \(formatLastSeen(device.lastSeenAt))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        if device.id != deviceService.currentDevice?.id {
                            Button(role: .destructive) {
                                removeDevice(device)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if deviceService.currentDevice != nil {
                Button {
                    newName = deviceService.currentDevice?.deviceName ?? ""
                    editingName = true
                } label: {
                    Label("이 기기 이름 변경", systemImage: "pencil")
                }
            }
        }
        .onAppear { loadDevices() }
        .alert("디바이스 이름 변경", isPresented: $editingName) {
            TextField("이름", text: $newName)
            Button("변경") {
                Task {
                    try? await deviceService.updateDeviceName(newName)
                    loadDevices()
                }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func loadDevices() {
        Task {
            devices = (try? await deviceService.fetchWorkspaceDevices()) ?? []
        }
    }

    private func removeDevice(_ device: DeviceInfo) {
        Task {
            try? await deviceService.removeDevice(id: device.id)
            loadDevices()
        }
    }

    private func formatLastSeen(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
