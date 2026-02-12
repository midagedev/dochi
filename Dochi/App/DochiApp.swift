import SwiftUI

@main
struct DochiApp: App {
    @State private var viewModel: DochiViewModel
    private let keychainService: KeychainService
    private let settings: AppSettings
    private let ttsService: SupertonicService
    private let telegramService: TelegramService
    private let mcpService: MCPService
    private let supabaseService: SupabaseService

    init() {
        let settings = AppSettings()
        let contextService = ContextService()
        let keychainService = KeychainService()
        let conversationService = ConversationService()
        let llmService = LLMService()
        let speechService = SpeechService()
        let ttsService = SupertonicService()
        let soundService = SoundService()
        let supabaseService = SupabaseService()
        let telegramService = TelegramService()
        let mcpService = MCPService()

        self.keychainService = keychainService
        self.settings = settings
        self.ttsService = ttsService
        self.telegramService = telegramService
        self.mcpService = mcpService
        self.supabaseService = supabaseService

        let workspaceId = UUID(uuidString: settings.currentWorkspaceId)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let sessionContext = SessionContext(workspaceId: workspaceId)

        let toolService = BuiltInToolService(
            contextService: contextService,
            keychainService: keychainService,
            sessionContext: sessionContext,
            settings: settings,
            supabaseService: supabaseService,
            telegramService: telegramService,
            mcpService: mcpService
        )

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
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(
                        settings: settings,
                        keychainService: keychainService,
                        onComplete: { showOnboarding = false }
                    )
                    .interactiveDismissDisabled()
                }
        }

        Settings {
            SettingsView(
                settings: settings,
                keychainService: keychainService,
                ttsService: ttsService,
                telegramService: telegramService,
                mcpService: mcpService,
                supabaseService: supabaseService
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
