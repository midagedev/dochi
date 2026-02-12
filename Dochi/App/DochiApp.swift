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

        self.keychainService = keychainService
        self.settings = settings

        // Use a default workspace ID for local-only mode (P4 will add workspace switching)
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
            settings: settings,
            sessionContext: sessionContext
        ))

        contextService.migrateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }

        Settings {
            SettingsView(settings: settings, keychainService: keychainService)
        }
    }
}
