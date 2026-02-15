import SwiftUI

struct ExternalToolDashboardView: View {
    let manager: ExternalToolSessionManagerProtocol
    let session: ExternalToolSession
    let settings: AppSettings
    @State private var commandInput = ""
    @State private var isStarting = false
    @State private var showProfileEditor = false

    private var profile: ExternalToolProfile? {
        manager.profiles.first(where: { $0.id == session.profileId })
    }

    private var elapsedText: String {
        guard let started = session.startedAt else { return "" }
        let interval = Date().timeIntervalSince(started)
        let minutes = Int(interval) / 60
        if minutes < 60 {
            return "\(minutes)분 경과"
        }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return "\(hours)시간 \(remainMinutes)분 경과"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Waiting banner
            if session.status == .waiting {
                waitingBanner
            }

            // Output area
            outputArea

            Divider()

            // Command input
            commandInputArea
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: profile?.icon ?? "terminal.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile?.name ?? "알 수 없음")
                        .font(.system(size: 14, weight: .semibold))

                    Circle()
                        .fill(session.status.color)
                        .frame(width: 8, height: 8)

                    Text(session.status.displayText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(profile?.workingDirectory ?? "~")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    if profile?.isRemote == true {
                        Text("SSH")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    } else {
                        Text("로컬")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    if !elapsedText.isEmpty {
                        Text(elapsedText)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if isStarting {
                ProgressView()
                    .controlSize(.small)
            }

            // Action buttons
            HStack(spacing: 6) {
                if session.status != .dead {
                    Button {
                        Task { await manager.stopSession(id: session.id) }
                    } label: {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("정지")
                }

                Button {
                    isStarting = true
                    Task {
                        try? await manager.restartSession(id: session.id)
                        isStarting = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("재시작")

                Button {
                    showProfileEditor = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("설정")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showProfileEditor) {
            if let profile {
                ExternalToolProfileEditorView(
                    manager: manager,
                    existingProfile: profile,
                    onSave: { updated in
                        manager.saveProfile(updated)
                        showProfileEditor = false
                    },
                    onCancel: { showProfileEditor = false }
                )
            }
        }
    }

    // MARK: - Waiting Banner

    @ViewBuilder
    private var waitingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            Text("사용자 입력 대기 중")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)

            if let lastLine = session.lastOutput.last(where: { $0.contains("[Y/n]") || $0.contains("[y/N]") }) {
                Text(lastLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Output Area

    @ViewBuilder
    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(session.lastOutput.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: session.lastOutput.count) { _, _ in
                if let last = session.lastOutput.indices.last {
                    withAnimation {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Command Input

    @ViewBuilder
    private var commandInputArea: some View {
        HStack(spacing: 8) {
            TextField("작업 내용을 입력하세요...", text: $commandInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    sendCommand()
                }

            Button {
                sendCommand()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(commandInput.isEmpty ? .secondary.opacity(0.5) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(commandInput.isEmpty || session.status == .dead)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sendCommand() {
        let text = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandInput = ""
        Task {
            try? await manager.sendCommand(sessionId: session.id, command: text)
        }
    }
}

// MARK: - Empty Dashboard

struct ExternalToolEmptyDashboardView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hammer")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("외부 도구를 선택하세요.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
