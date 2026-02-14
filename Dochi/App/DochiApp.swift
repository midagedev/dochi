import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

@main
struct DochiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel: DochiViewModel
    private let keychainService: KeychainService
    private let settings: AppSettings
    private let contextService: ContextService
    private let sessionContext: SessionContext
    private let ttsService: TTSRouter
    private let telegramService: TelegramService
    private let mcpService: MCPService
    private let supabaseService: SupabaseService
    private let toolService: BuiltInToolService
    private let heartbeatService: HeartbeatService

    init() {
        let settings = AppSettings()
        let contextService = ContextService()
        let keychainService = KeychainService()
        let conversationService = ConversationService()
        let llmService = LLMService()
        let speechService = SpeechService()
        let ttsService = TTSRouter(settings: settings, keychainService: keychainService)
        let soundService = SoundService()
        let supabaseService = SupabaseService()
        let telegramService = TelegramService()
        let mcpService = MCPService()
        let heartbeatService = HeartbeatService(settings: settings)

        self.keychainService = keychainService
        self.settings = settings
        self.contextService = contextService
        self.ttsService = ttsService
        self.telegramService = telegramService
        self.mcpService = mcpService
        self.supabaseService = supabaseService
        self.heartbeatService = heartbeatService

        let workspaceId = UUID(uuidString: settings.currentWorkspaceId)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        // Restore last active user
        var restoredUserId: String? = nil
        if !settings.defaultUserId.isEmpty {
            let profiles = contextService.loadProfiles()
            if profiles.contains(where: { $0.id.uuidString == settings.defaultUserId }) {
                restoredUserId = settings.defaultUserId
            } else {
                settings.defaultUserId = ""
            }
        }

        let sessionContext = SessionContext(workspaceId: workspaceId, currentUserId: restoredUserId)
        self.sessionContext = sessionContext

        let toolService = BuiltInToolService(
            contextService: contextService,
            keychainService: keychainService,
            sessionContext: sessionContext,
            settings: settings,
            supabaseService: supabaseService,
            telegramService: telegramService,
            mcpService: mcpService
        )
        self.toolService = toolService

        _viewModel = State(initialValue: DochiViewModel(
            llmService: llmService,
            toolService: toolService,
            contextService: contextService,
            conversationService: conversationService,
            keychainService: keychainService,
            speechService: speechService,
            ttsService: ttsService,
            soundService: soundService,
            settings: settings,
            sessionContext: sessionContext
        ))

        contextService.migrateIfNeeded()

        heartbeatService.setProactiveHandler { message in
            Log.app.info("Heartbeat proactive message: \(message)")
        }

        // Start Telegram polling if enabled
        if settings.telegramEnabled,
           let token = keychainService.load(account: "telegram_bot_token"), !token.isEmpty {
            telegramService.startPolling(token: token)
        }

        // Restore MCP servers from AppStorage
        restoreMCPServers(mcpService: mcpService, json: settings.mcpServersJSON)

        // Configure Supabase if previously set
        if !settings.supabaseURL.isEmpty, !settings.supabaseAnonKey.isEmpty,
           let url = URL(string: settings.supabaseURL) {
            supabaseService.configure(url: url, anonKey: settings.supabaseAnonKey)
        }

        // Restore Supabase session
        Task {
            await supabaseService.restoreSession()
        }
    }

    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingCompleted")

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, supabaseService: supabaseService)
                .onAppear {
                    if viewModel.isVoiceMode {
                        viewModel.prepareTTSEngine()
                    }
                    // Wire Telegram message handler
                    viewModel.setTelegramService(telegramService)
                    telegramService.onMessage = { [weak viewModel] update in
                        guard let viewModel else { return }
                        Task {
                            await viewModel.handleTelegramMessage(update)
                        }
                    }

                    heartbeatService.restart()

                    // Smoke test: write app state for automated verification
                    SmokeTestReporter.report(
                        profileCount: viewModel.userProfiles.count,
                        currentUserId: sessionContext.currentUserId,
                        currentUserName: viewModel.currentUserName == "(사용자 없음)" ? nil : viewModel.currentUserName,
                        conversationCount: viewModel.conversations.count,
                        workspaceId: sessionContext.workspaceId.uuidString,
                        agentName: settings.activeAgentName
                    )
                }
                .onDisappear {
                    heartbeatService.stop()
                }
                .onChange(of: settings.heartbeatEnabled) { _, _ in
                    heartbeatService.restart()
                }
                .onChange(of: settings.heartbeatIntervalMinutes) { _, _ in
                    heartbeatService.restart()
                }
                .onChange(of: settings.heartbeatCheckCalendar) { _, _ in
                    heartbeatService.restart()
                }
                .onChange(of: settings.heartbeatCheckKanban) { _, _ in
                    heartbeatService.restart()
                }
                .onChange(of: settings.heartbeatCheckReminders) { _, _ in
                    heartbeatService.restart()
                }
                .onChange(of: settings.heartbeatQuietHoursStart) { _, _ in
                    heartbeatService.restart()
                }
                .onChange(of: settings.heartbeatQuietHoursEnd) { _, _ in
                    heartbeatService.restart()
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(
                        settings: settings,
                        keychainService: keychainService,
                        contextService: contextService,
                        onComplete: {
                            // Sync newly created user to sessionContext
                            if !settings.defaultUserId.isEmpty {
                                sessionContext.currentUserId = settings.defaultUserId
                            }
                            showOnboarding = false
                        }
                    )
                    .interactiveDismissDisabled()
                }
        }

        Settings {
            SettingsView(
                settings: settings,
                keychainService: keychainService,
                contextService: contextService,
                sessionContext: sessionContext,
                ttsService: ttsService,
                telegramService: telegramService,
                mcpService: mcpService,
                supabaseService: supabaseService,
                toolService: toolService
            )
        }
    }

    private func restoreMCPServers(mcpService: MCPService, json: String) {
        guard let data = json.data(using: .utf8),
              let servers = try? JSONDecoder().decode([MCPServerConfig].self, from: data) else {
            return
        }
        for server in servers {
            mcpService.addServer(config: server)
            if server.isEnabled {
                Task {
                    try? await mcpService.connect(serverId: server.id)
                }
            }
        }
        Log.app.info("Restored \(servers.count) MCP server(s) from settings")
    }
}
