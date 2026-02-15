import SwiftUI

struct DeviceSettingsView: View {
    var devicePolicyService: DevicePolicyServiceProtocol
    var settings: AppSettings
    var supabaseService: SupabaseServiceProtocol?

    @State private var editingName: String = ""
    @State private var isEditingName: Bool = false

    private var currentDevice: DeviceInfo? {
        devicePolicyService.currentDevice
    }

    private var otherDevices: [DeviceInfo] {
        devicePolicyService.registeredDevices.filter { !$0.isCurrentDevice }
    }

    private var onlineDevices: [DeviceInfo] {
        devicePolicyService.registeredDevices.filter { $0.isOnline || $0.isCurrentDevice }
    }

    var body: some View {
        Form {
            // Section 1: This Device
            Section {
                if let device = currentDevice {
                    if isEditingName {
                        HStack {
                            TextField("디바이스 이름", text: $editingName)
                                .textFieldStyle(.roundedBorder)
                            Button("저장") {
                                devicePolicyService.renameDevice(id: device.id, name: editingName)
                                isEditingName = false
                            }
                            .buttonStyle(.bordered)
                            Button("취소") {
                                isEditingName = false
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        HStack {
                            Text("이름")
                            Spacer()
                            Text(device.name)
                                .foregroundStyle(.secondary)
                            Button {
                                editingName = device.name
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("유형")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: device.deviceType.iconName)
                                .font(.caption)
                            Text(device.deviceType.displayName)
                        }
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("플랫폼")
                        Spacer()
                        Text(device.platform.displayName)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("기능")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            capabilityBadge("음성", enabled: device.capabilities.supportsVoice)
                            capabilityBadge("TTS", enabled: device.capabilities.supportsTTS)
                            capabilityBadge("알림", enabled: device.capabilities.supportsNotifications)
                            capabilityBadge("도구", enabled: device.capabilities.supportsTools)
                        }
                    }
                } else {
                    Text("디바이스 정보를 로드하는 중...")
                        .foregroundStyle(.secondary)
                }
            } header: {
                SettingsSectionHeader(
                    title: "이 디바이스",
                    helpContent: "현재 디바이스의 정보와 기능을 표시합니다. 이름을 편집하여 다른 디바이스에서 쉽게 구별할 수 있습니다."
                )
            }

            // Section 2: Other Devices
            Section {
                if otherDevices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 24))
                            .foregroundStyle(.quaternary)
                        Text("다른 디바이스가 없습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("다른 기기에서 도치를 실행하면 자동으로 등록됩니다")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ForEach(otherDevices) { device in
                        HStack {
                            Image(systemName: device.deviceType.iconName)
                                .font(.system(size: 14))
                                .foregroundStyle(device.isOnline ? .green : .secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.system(size: 12, weight: .medium))
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(device.isOnline ? Color.green : Color.gray)
                                        .frame(width: 6, height: 6)
                                    Text(device.statusText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button {
                                devicePolicyService.removeDevice(id: device.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("디바이스 제거")
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: "다른 디바이스",
                    helpContent: "등록된 다른 디바이스 목록입니다. 온라인 상태의 디바이스는 초록색으로 표시됩니다. 120초 이내에 활동이 없으면 오프라인으로 전환됩니다."
                )
            }

            // Section 3: Response Policy
            Section {
                Picker("응답 정책", selection: Binding(
                    get: { devicePolicyService.currentPolicy },
                    set: { devicePolicyService.setPolicy($0) }
                )) {
                    ForEach(DeviceSelectionPolicy.allCases, id: \.self) { policy in
                        HStack {
                            Image(systemName: policy.iconName)
                            Text(policy.displayName)
                        }
                        .tag(policy)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(devicePolicyService.currentPolicy.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Priority-based: drag-reorderable list
                if devicePolicyService.currentPolicy == .priorityBased {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("우선순위 (위가 높음)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        List {
                            ForEach(devicePolicyService.registeredDevices.sorted(by: { $0.priority < $1.priority })) { device in
                                HStack(spacing: 8) {
                                    Image(systemName: device.deviceType.iconName)
                                        .font(.caption)
                                        .foregroundStyle(device.isOnline || device.isCurrentDevice ? .primary : .secondary)
                                    Text(device.name)
                                        .font(.system(size: 12))
                                    Spacer()
                                    if device.isCurrentDevice {
                                        Text("이 디바이스")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                    Text("\(device.priority + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onMove { source, destination in
                                var sorted = devicePolicyService.registeredDevices.sorted { $0.priority < $1.priority }
                                sorted.move(fromOffsets: source, toOffset: destination)
                                devicePolicyService.reorderPriority(deviceIds: sorted.map(\.id))
                            }
                        }
                        .frame(height: max(80, CGFloat(devicePolicyService.registeredDevices.count * 28 + 16)))
                        .listStyle(.bordered)
                    }
                }

                // Manual: device picker (online only)
                if devicePolicyService.currentPolicy == .manual {
                    if onlineDevices.isEmpty {
                        Text("온라인 디바이스가 없습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("응답 디바이스", selection: Binding(
                            get: {
                                settings.manualResponderDeviceId
                            },
                            set: { newValue in
                                if let id = UUID(uuidString: newValue) {
                                    devicePolicyService.setManualDevice(id: id)
                                }
                            }
                        )) {
                            ForEach(onlineDevices) { device in
                                HStack {
                                    Image(systemName: device.deviceType.iconName)
                                    Text(device.name)
                                    if device.isCurrentDevice {
                                        Text("(이 디바이스)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(device.id.uuidString)
                            }
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: "응답 정책",
                    helpContent: "여러 디바이스가 연결되어 있을 때 어떤 디바이스가 LLM 응답을 처리할지 결정하는 정책입니다. 우선순위, 최근 활성, 수동 선택 중 선택할 수 있습니다."
                )
            }

            // Section 4: Advanced
            Section {
                Toggle("Supabase 동기화", isOn: Binding(
                    get: { settings.deviceCloudSyncEnabled },
                    set: { settings.deviceCloudSyncEnabled = $0 }
                ))
                .disabled(supabaseService?.authState.isSignedIn != true)

                if supabaseService?.authState.isSignedIn != true {
                    Text("Supabase 로그인이 필요합니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("하트비트 주기")
                    Spacer()
                    Text("30초")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("오프라인 판정")
                    Spacer()
                    Text("120초")
                        .foregroundStyle(.secondary)
                }
            } header: {
                SettingsSectionHeader(
                    title: "고급",
                    helpContent: "디바이스 동기화 및 네트워크 관련 고급 설정입니다. Supabase 동기화를 활성화하면 클라우드를 통해 디바이스 목록을 다른 기기와 공유합니다."
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func capabilityBadge(_ label: String, enabled: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 9))
                .foregroundStyle(enabled ? .green : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(enabled ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(enabled ? Color.green.opacity(0.08) : Color.secondary.opacity(0.05))
        )
    }
}
