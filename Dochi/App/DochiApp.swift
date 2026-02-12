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

        self.keychainService = keychainService
        self.settings = settings

        let defaultWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let sessionContext = SessionContext(workspaceId: defaultWorkspaceId)

        let toolService = BuiltInToolService(
            contextService: contextService,
            keychainService: keychainService,
            sessionContext: sessionContext
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
