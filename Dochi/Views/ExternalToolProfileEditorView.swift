import SwiftUI

struct ExternalToolProfileEditorView: View {
    let manager: ExternalToolSessionManagerProtocol
    let existingProfile: ExternalToolProfile?
    let onSave: (ExternalToolProfile) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var icon: String = "terminal.fill"
    @State private var command: String = ""
    @State private var arguments: String = ""
    @State private var workingDirectory: String = "~"
    @State private var isRemote: Bool = false
    @State private var sshHost: String = ""
    @State private var sshPort: String = "22"
    @State private var sshUser: String = ""
    @State private var sshKeyPath: String = ""
    @State private var idlePattern: String = ""
    @State private var busyPattern: String = ""
    @State private var waitingPattern: String = ""
    @State private var errorPattern: String = ""
    @State private var selectedPreset: ExternalToolPreset? = nil

    private let iconOptions = ["terminal.fill", "hammer", "wrench", "chevron.left.forwardslash.chevron.right", "cpu"]

    init(manager: ExternalToolSessionManagerProtocol, existingProfile: ExternalToolProfile? = nil, onSave: @escaping (ExternalToolProfile) -> Void, onCancel: @escaping () -> Void) {
        self.manager = manager
        self.existingProfile = existingProfile
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text(existingProfile != nil ? "프로파일 편집" : "외부 AI 도구 프로파일")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Form {
                // Basic section
                Section("기본") {
                    TextField("이름", text: $name)
                    Picker("아이콘", selection: $icon) {
                        ForEach(iconOptions, id: \.self) { iconName in
                            Label(iconName, systemImage: iconName).tag(iconName)
                        }
                    }
                    TextField("실행 명령", text: $command)
                        .font(.system(.body, design: .monospaced))
                    TextField("인자", text: $arguments)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        TextField("작업 디렉토리", text: $workingDirectory)
                            .font(.system(.body, design: .monospaced))
                        Button("선택") {
                            selectDirectory()
                        }
                    }
                }

                // Connection section
                Section("연결") {
                    Picker("연결 방식", selection: $isRemote) {
                        Text("로컬").tag(false)
                        Text("SSH").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if isRemote {
                        TextField("호스트", text: $sshHost)
                            .font(.system(.body, design: .monospaced))
                        TextField("포트", text: $sshPort)
                            .font(.system(.body, design: .monospaced))
                        TextField("사용자", text: $sshUser)
                            .font(.system(.body, design: .monospaced))
                        HStack {
                            TextField("SSH 키 경로", text: $sshKeyPath)
                                .font(.system(.body, design: .monospaced))
                            Button("선택") {
                                selectSSHKey()
                            }
                        }
                    }
                }

                // Health check patterns section
                Section("헬스체크 패턴") {
                    TextField("유휴 패턴", text: $idlePattern)
                        .font(.system(.body, design: .monospaced))
                    TextField("작업 중 패턴", text: $busyPattern)
                        .font(.system(.body, design: .monospaced))
                    TextField("입력 대기 패턴", text: $waitingPattern)
                        .font(.system(.body, design: .monospaced))
                    TextField("에러 패턴", text: $errorPattern)
                        .font(.system(.body, design: .monospaced))
                }

                // Presets section
                Section("프리셋") {
                    HStack(spacing: 8) {
                        ForEach(ExternalToolPreset.allCases, id: \.rawValue) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                Text(preset.rawValue)
                                    .font(.system(size: 12, weight: selectedPreset == preset ? .semibold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(selectedPreset == preset ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            selectedPreset = nil
                        } label: {
                            Text("커스텀")
                                .font(.system(size: 12, weight: selectedPreset == nil ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(selectedPreset == nil ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("프리셋 선택 시 명령과 패턴이 자동으로 채워집니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            // Buttons
            Divider()
            HStack {
                Spacer()
                Button("취소") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("저장") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || command.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadExistingProfile()
        }
    }

    private func loadExistingProfile() {
        guard let profile = existingProfile else { return }
        name = profile.name
        icon = profile.icon
        command = profile.command
        arguments = profile.arguments.joined(separator: " ")
        workingDirectory = profile.workingDirectory
        isRemote = profile.isRemote
        if let ssh = profile.sshConfig {
            sshHost = ssh.host
            sshPort = "\(ssh.port)"
            sshUser = ssh.user
            sshKeyPath = ssh.keyPath ?? ""
        }
        idlePattern = profile.healthCheckPatterns.idlePattern
        busyPattern = profile.healthCheckPatterns.busyPattern
        waitingPattern = profile.healthCheckPatterns.waitingPattern
        errorPattern = profile.healthCheckPatterns.errorPattern
    }

    private func applyPreset(_ preset: ExternalToolPreset) {
        selectedPreset = preset
        let profile = preset.profile
        name = profile.name
        command = profile.command
        arguments = profile.arguments.joined(separator: " ")
        idlePattern = profile.healthCheckPatterns.idlePattern
        busyPattern = profile.healthCheckPatterns.busyPattern
        waitingPattern = profile.healthCheckPatterns.waitingPattern
        errorPattern = profile.healthCheckPatterns.errorPattern
    }

    private func save() {
        let args = arguments.split(separator: " ").map(String.init)
        let sshConfig: SSHConfig? = isRemote ? SSHConfig(
            host: sshHost,
            port: Int(sshPort) ?? 22,
            user: sshUser,
            keyPath: sshKeyPath.isEmpty ? nil : sshKeyPath
        ) : nil

        let patterns = HealthCheckPatterns(
            idlePattern: idlePattern,
            busyPattern: busyPattern,
            waitingPattern: waitingPattern,
            errorPattern: errorPattern
        )

        let profile = ExternalToolProfile(
            id: existingProfile?.id ?? UUID(),
            name: name,
            icon: icon,
            command: command,
            arguments: args,
            workingDirectory: workingDirectory,
            sshConfig: sshConfig,
            healthCheckPatterns: patterns
        )

        onSave(profile)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "작업 디렉토리를 선택하세요"

        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func selectSSHKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.message = "SSH 키 파일을 선택하세요"

        if panel.runModal() == .OK, let url = panel.url {
            sshKeyPath = url.path
        }
    }
}
