import SwiftUI

@main
struct DochiApp: App {
    @State private var viewModel: DochiViewModel
    private let keychainService: KeychainService
    private let settings: AppSettings

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

        // Restore Supabase session
        Task {
            await supabaseService.restoreSession()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    if viewModel.isVoiceMode {
                        viewModel.prepareTTSEngine()
                    }
                }
        }

        Settings {
            SettingsView(settings: settings, keychainService: keychainService)
        }
    }
}
