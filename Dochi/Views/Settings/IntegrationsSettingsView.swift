import SwiftUI

struct IntegrationsSettingsView: View {
    var keychainService: KeychainServiceProtocol
    var telegramService: TelegramServiceProtocol?
    var mcpService: MCPServiceProtocol?
    var settings: AppSettings

    // Telegram state
    @State private var botToken = ""
    @State private var botUsername: String?
    @State private var botCheckError: String?
    @State private var isCheckingBot = false

    // MCP state
    @State private var showMCPServerEdit = false
    @State private var editingServer: MCPServerConfig?
    @State private var serverToDelete: UUID?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            telegramSection
            mcpSection
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            botToken = keychainService.load(account: "telegram_bot_token") ?? ""
        }
        .sheet(isPresented: $showMCPServerEdit) {
            MCPServerEditView(
                mcpService: mcpService,
                editingServer: editingServer,
                onSave: {
                    editingServer = nil
                }
            )
        }
    }

    // MARK: - Telegram Section

    @ViewBuilder
    private var telegramSection: some View {
        Section("텔레그램") {
            Toggle("봇 활성화", isOn: Binding(
                get: { settings.telegramEnabled },
                set: { newValue in
                    settings.telegramEnabled = newValue
                    if newValue {
                        if let token = keychainService.load(account: "telegram_bot_token"), !token.isEmpty {
                            telegramService?.startPolling(token: token)
                        }
                    } else {
                        telegramService?.stopPolling()
                    }
                }
            ))

            HStack {
                SecureField("봇 토큰", text: $botToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button("저장") {
                    saveBotToken()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack {
                connectionStatusView

                Spacer()

                Button {
                    checkBot()
                } label: {
                    HStack(spacing: 4) {
                        if isCheckingBot {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                        Text("봇 정보 확인")
                    }
                }
                .disabled(isCheckingBot || botToken.isEmpty)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let username = botUsername {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("@\(username)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = botCheckError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle("스트리밍 답변", isOn: Binding(
                get: { settings.telegramStreamReplies },
                set: { settings.telegramStreamReplies = $0 }
            ))
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        if let tg = telegramService {
            HStack(spacing: 4) {
                Circle()
                    .fill(tg.isPolling ? .green : .red)
                    .frame(width: 6, height: 6)
                Text(tg.isPolling ? "연결됨" : "연결 안 됨")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveBotToken() {
        let token = botToken.trimmingCharacters(in: .whitespaces)
        if token.isEmpty {
            try? keychainService.delete(account: "telegram_bot_token")
        } else {
            try? keychainService.save(account: "telegram_bot_token", value: token)
        }
    }

    private func checkBot() {
        let token = botToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        isCheckingBot = true
        botCheckError = nil
        botUsername = nil

        Task {
            do {
                let user = try await telegramService?.getMe(token: token)
                botUsername = user?.username
            } catch {
                botCheckError = error.localizedDescription
            }
            isCheckingBot = false
        }
    }

    // MARK: - MCP Section

    @ViewBuilder
    private var mcpSection: some View {
        Section("MCP 서버") {
            let servers = mcpService?.listServers() ?? []

            if servers.isEmpty {
                Text("등록된 MCP 서버가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(servers) { server in
                    mcpServerRow(server)
                }
            }

            Button {
                editingServer = nil
                showMCPServerEdit = true
            } label: {
                Label("MCP 서버 추가", systemImage: "plus")
            }
        }
        .confirmationDialog(
            "이 MCP 서버를 삭제하시겠습니까?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let id = serverToDelete {
                    mcpService?.removeServer(id: id)
                }
            }
            Button("취소", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func mcpServerRow(_ server: MCPServerConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(size: 13, weight: .medium))
                Text(server.command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Connection state dot
            mcpConnectionDot(for: server.id)

            Button {
                editingServer = server
                showMCPServerEdit = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("편집")

            Button {
                serverToDelete = server.id
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("삭제")
        }
    }

    @ViewBuilder
    private func mcpConnectionDot(for serverId: UUID) -> some View {
        Circle()
            .fill(.gray)
            .frame(width: 6, height: 6)
            .help("연결 상태 확인 불가")
    }
}
