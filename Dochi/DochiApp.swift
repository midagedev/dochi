import SwiftUI

@main
struct DochiApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var viewModel: DochiViewModel

    init() {
        let keychainService = KeychainService()
        let supabaseService = SupabaseService(keychainService: keychainService)
        let cloudContext = CloudContextService(supabaseService: supabaseService)
        let deviceService = DeviceService(supabaseService: supabaseService, keychainService: keychainService)
        let cloudConversation = CloudConversationService(supabaseService: supabaseService, deviceService: deviceService)
        let settings = AppSettings(keychainService: keychainService, contextService: cloudContext)
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: DochiViewModel(
            settings: settings,
            contextService: cloudContext,
            conversationService: cloudConversation,
            supabaseService: supabaseService,
            deviceService: deviceService
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 650)
    }
}
