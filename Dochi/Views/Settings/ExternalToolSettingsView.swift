import SwiftUI

struct ExternalToolSettingsView: View {
    var settings: AppSettings
    var externalToolManager: ExternalToolSessionManagerProtocol?

    @State private var showProfileEditor = false
    @State private var editingProfile: ExternalToolProfile?

    var body: some View {
        Form {
            // Enable toggle
            Section {
                Toggle("외부 도구 관리 활성화", isOn: Binding(
                    get: { settings.externalToolEnabled },
                    set: { settings.externalToolEnabled = $0 }
                ))

                Text("tmux를 통해 Claude Code, Codex 등 외부 AI 도구를 관리합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // tmux availability warning
                if let manager = externalToolManager, !manager.isTmuxAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 12))
                        Text("tmux가 설치되어 있지 않습니다. `brew install tmux`로 설치하세요.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } header: {
                SettingsSectionHeader(
                    title: "외부 AI 도구",
                    helpContent: "tmux 세션 기반으로 Claude Code, Codex CLI, aider 등 외부 AI 도구의 상태를 모니터링하고, 작업을 디스패치하며, 결과를 수집합니다."
                )
            }

            // Health check settings
            Section {
                HStack {
                    Text("상태 확인 간격: \(settings.externalToolHealthCheckIntervalSeconds)초")
                    Slider(
                        value: Binding(
                            get: { Double(settings.externalToolHealthCheckIntervalSeconds) },
                            set: { settings.externalToolHealthCheckIntervalSeconds = Int($0.rounded()) }
                        ),
                        in: 10...120,
                        step: 5
                    )
                }

                HStack {
                    Text("출력 캡처 줄 수: \(settings.externalToolOutputCaptureLines)줄")
                    Slider(
                        value: Binding(
                            get: { Double(settings.externalToolOutputCaptureLines) },
                            set: { settings.externalToolOutputCaptureLines = Int($0.rounded()) }
                        ),
                        in: 20...500,
                        step: 20
                    )
                }

                Toggle("자동 재시작 (세션 종료 시)", isOn: Binding(
                    get: { settings.externalToolAutoRestart },
                    set: { settings.externalToolAutoRestart = $0 }
                ))
            } header: {
                SettingsSectionHeader(
                    title: "헬스체크",
                    helpContent: "주기적으로 tmux capture-pane 출력을 읽어 도구 상태(유휴/작업중/입력대기/에러)를 판별합니다."
                )
            }

            // Profile list
            Section {
                if let manager = externalToolManager {
                    if manager.profiles.isEmpty {
                        Text("등록된 프로파일이 없습니다")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.profiles) { profile in
                            HStack {
                                Image(systemName: profile.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.system(size: 13))
                                    HStack(spacing: 6) {
                                        Text(profile.isRemote ? "SSH" : "로컬")
                                            .font(.system(size: 10))
                                            .foregroundStyle(profile.isRemote ? .orange : .secondary)
                                        Text(profile.command)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button("편집") {
                                    editingProfile = profile
                                    showProfileEditor = true
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("삭제", role: .destructive) {
                                    manager.deleteProfile(id: profile.id)
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundStyle(.red)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Button {
                        editingProfile = nil
                        showProfileEditor = true
                    } label: {
                        Label("프로파일 추가", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text("외부 도구 매니저가 초기화되지 않았습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } header: {
                SettingsSectionHeader(
                    title: "등록된 프로파일",
                    helpContent: "외부 AI 도구 프로파일입니다. 각 프로파일에는 실행 명령, 작업 디렉토리, 헬스체크 패턴이 포함됩니다."
                )
            }

            // tmux settings
            Section {
                HStack {
                    Text("tmux 경로")
                    TextField("/usr/bin/tmux", text: Binding(
                        get: { settings.externalToolTmuxPath },
                        set: { settings.externalToolTmuxPath = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("세션 접두사")
                    TextField("dochi-", text: Binding(
                        get: { settings.externalToolSessionPrefix },
                        set: { settings.externalToolSessionPrefix = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }

                Text("도치가 생성하는 세션 이름에 이 접두사가 붙습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(
                    title: "tmux",
                    helpContent: "tmux 실행 경로와 세션 이름 접두사를 설정합니다."
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showProfileEditor) {
            if let manager = externalToolManager {
                ExternalToolProfileEditorView(
                    manager: manager,
                    existingProfile: editingProfile,
                    onSave: { profile in
                        manager.saveProfile(profile)
                        showProfileEditor = false
                    },
                    onCancel: { showProfileEditor = false }
                )
            }
        }
    }
}
