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

    // Telegram mapping state
    @State private var chatMappings: [TelegramChatMapping] = []

    var body: some View {
        Form {
            telegramSection
            telegramMappingSection
            mcpSection
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            botToken = keychainService.load(account: "telegram_bot_token") ?? ""
            chatMappings = TelegramChatMappingStore.loadMappings(from: settings)
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
                            let mode = TelegramConnectionMode(rawValue: settings.telegramConnectionMode) ?? .polling
                            if mode == .webhook, !settings.telegramWebhookURL.isEmpty {
                                Task {
                                    try? await telegramService?.startWebhook(
                                        token: token,
                                        url: settings.telegramWebhookURL,
                                        port: UInt16(settings.telegramWebhookPort)
                                    )
                                }
                            } else {
                                telegramService?.startPolling(token: token)
                            }
                        }
                    } else {
                        telegramService?.stopPolling()
                        Task { try? await telegramService?.stopWebhook() }
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

            Picker("연결 모드", selection: Binding(
                get: { TelegramConnectionMode(rawValue: settings.telegramConnectionMode) ?? .polling },
                set: { settings.telegramConnectionMode = $0.rawValue }
            )) {
                ForEach(TelegramConnectionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            if TelegramConnectionMode(rawValue: settings.telegramConnectionMode) == .webhook {
                HStack {
                    TextField("웹훅 URL", text: Binding(
                        get: { settings.telegramWebhookURL },
                        set: { settings.telegramWebhookURL = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }

                HStack {
                    Text("포트")
                        .font(.caption)
                    TextField("포트", value: Binding(
                        get: { settings.telegramWebhookPort },
                        set: { settings.telegramWebhookPort = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }

                if let tg = telegramService {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tg.isWebhookActive ? .green : .gray)
                            .frame(width: 6, height: 6)
                        Text(tg.isWebhookActive ? "웹훅 활성" : "웹훅 비활성")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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

    // MARK: - Telegram Mapping Section

    @ViewBuilder
    private var telegramMappingSection: some View {
        Section("텔레그램 채팅 매핑") {
            Toggle("이 디바이스를 텔레그램 호스트로 사용", isOn: Binding(
                get: { settings.isTelegramHost },
                set: { settings.isTelegramHost = $0 }
            ))
            .help("활성화하면 이 디바이스가 텔레그램 메시지를 처리합니다")

            if chatMappings.isEmpty {
                Text("등록된 채팅 매핑이 없습니다. 텔레그램 대화가 시작되면 자동으로 추가됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(chatMappings) { mapping in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mapping.label.isEmpty ? "Chat #\(mapping.chatId)" : mapping.label)
                                .font(.system(size: 13, weight: .medium))
                            Text("ID: \(mapping.chatId)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { mapping.enabled },
                            set: { newValue in
                                updateMappingEnabled(chatId: mapping.chatId, enabled: newValue)
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(mapping.enabled ? "활성" : "비활성")

                        Button {
                            removeMappingChat(chatId: mapping.chatId)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("삭제")
                    }
                }
            }
        }
    }

    private func updateMappingEnabled(chatId: Int64, enabled: Bool) {
        if let idx = chatMappings.firstIndex(where: { $0.chatId == chatId }) {
            chatMappings[idx].enabled = enabled
            TelegramChatMappingStore.saveMappings(chatMappings, to: settings)
        }
    }

    private func removeMappingChat(chatId: Int64) {
        chatMappings.removeAll { $0.chatId == chatId }
        TelegramChatMappingStore.saveMappings(chatMappings, to: settings)
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
