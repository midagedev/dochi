import SwiftUI
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// UsageStore reference for flushing pending data on app termination (C-3).
    var usageStore: UsageStore?
    /// MenuBarManager reference for popover toggle (H-1).
    var menuBarManager: MenuBarManager?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any pending usage data to disk before exit (C-3)
        if let store = usageStore {
            store.flushToDiskSync()
            Log.app.info("UsageStore flushed on app termination")
        }

        // Teardown menu bar (H-1)
        menuBarManager?.teardown()
    }

    /// Toggle menu bar popover (called from NSStatusItem button action)
    @MainActor @objc func toggleMenuBarPopover() {
        menuBarManager?.togglePopover()
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
    private let notificationManager: NotificationManager
    private let modelDownloadManager: ModelDownloadManager
    private let usageStore: UsageStore
    private let spotlightIndexer: SpotlightIndexer
    private let vectorStore: VectorStore
    private let documentIndexer: DocumentIndexer
    private let memoryConsolidator: MemoryConsolidator
    private let delegationManager: DelegationManager
    private let schedulerService: SchedulerService

    init() {
        let settings = AppSettings()
        let contextService = ContextService()
        let keychainService = KeychainService()
        let conversationService = ConversationService()
        let llmService = LLMService(settings: settings)
        let speechService = SpeechService()
        let ttsService = TTSRouter(settings: settings, keychainService: keychainService)
        let soundService = SoundService()
        let supabaseService = SupabaseService()
        let telegramService = TelegramService()
        let mcpService = MCPService()
        let heartbeatService = HeartbeatService(settings: settings)
        let notificationManager = NotificationManager(settings: settings)

        self.keychainService = keychainService
        self.settings = settings
        self.contextService = contextService
        self.ttsService = ttsService
        self.telegramService = telegramService
        self.mcpService = mcpService
        self.supabaseService = supabaseService
        self.heartbeatService = heartbeatService
        self.notificationManager = notificationManager
        self.modelDownloadManager = ModelDownloadManager()

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

        let delegationManager = DelegationManager()
        self.delegationManager = delegationManager

        let schedulerService = SchedulerService(settings: settings)
        self.schedulerService = schedulerService

        let toolService = BuiltInToolService(
            contextService: contextService,
            keychainService: keychainService,
            sessionContext: sessionContext,
            settings: settings,
            supabaseService: supabaseService,
            telegramService: telegramService,
            mcpService: mcpService,
            llmService: llmService,
            delegationManager: delegationManager
        )
        self.toolService = toolService

        let metricsCollector = MetricsCollector()
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        let usageStore = UsageStore(baseURL: appSupportURL)
        self.usageStore = usageStore
        metricsCollector.usageStore = usageStore
        metricsCollector.settings = settings

        // Spotlight indexer (H-4)
        let spotlightIndexer = SpotlightIndexer(settings: settings)
        self.spotlightIndexer = spotlightIndexer

        // RAG services (I-1)
        let vectorStore = VectorStore(workspaceId: workspaceId)
        let embeddingService = EmbeddingService(keychainService: keychainService, model: settings.ragEmbeddingModel)
        let documentIndexer = DocumentIndexer(vectorStore: vectorStore, embeddingService: embeddingService, settings: settings)
        self.vectorStore = vectorStore
        self.documentIndexer = documentIndexer

        // Memory Consolidator (I-2)
        let memoryConsolidator = MemoryConsolidator(
            contextService: contextService,
            llmService: llmService,
            keychainService: keychainService
        )
        self.memoryConsolidator = memoryConsolidator

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
            sessionContext: sessionContext,
            metricsCollector: metricsCollector
        ))

        contextService.migrateIfNeeded()

        // Configure Shortcuts service (H-2)
        DochiShortcutService.shared.configure(
            contextService: contextService,
            keychainService: keychainService,
            settings: settings,
            llmService: llmService,
            heartbeatService: heartbeatService
        )

        heartbeatService.configure(contextService: contextService, sessionContext: sessionContext)
        heartbeatService.setNotificationManager(notificationManager)
        heartbeatService.setProactiveHandler { [weak viewModel] message in
            guard let viewModel else { return }
            Log.app.info("Heartbeat proactive message: \(message)")
            viewModel.injectProactiveMessage(message)
        }

        // Setup notification categories (H-3)
        notificationManager.registerCategories()
        UNUserNotificationCenter.current().delegate = notificationManager

        // Start Telegram connection if enabled
        if settings.telegramEnabled,
           let token = keychainService.load(account: "telegram_bot_token"), !token.isEmpty {
            let mode = TelegramConnectionMode(rawValue: settings.telegramConnectionMode) ?? .polling
            if mode == .webhook, !settings.telegramWebhookURL.isEmpty {
                Task {
                    do {
                        try await telegramService.startWebhook(
                            token: token,
                            url: settings.telegramWebhookURL,
                            port: UInt16(settings.telegramWebhookPort)
                        )
                    } catch {
                        Log.telegram.error("웹훅 시작 실패: \(error.localizedDescription)")
                        telegramService.startPolling(token: token)
                    }
                }
            } else {
                telegramService.startPolling(token: token)
            }
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
            ContentView(viewModel: viewModel, supabaseService: supabaseService, heartbeatService: heartbeatService)
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

                    // Configure Spotlight indexer (H-4)
                    viewModel.configureSpotlightIndexer(spotlightIndexer)

                    // Configure RAG DocumentIndexer (I-1)
                    viewModel.configureDocumentIndexer(documentIndexer)

                    // Configure Memory Consolidator (I-2)
                    viewModel.configureMemoryConsolidator(memoryConsolidator)

                    // Configure FeedbackStore (I-4)
                    let feedbackStore = FeedbackStore()
                    viewModel.configureFeedbackStore(feedbackStore)

                    // Configure DelegationManager (J-2)
                    viewModel.configureDelegationManager(delegationManager)

                    // Configure SchedulerService (J-3)
                    viewModel.configureSchedulerService(schedulerService)
                    schedulerService.setExecutionHandler { [weak viewModel] schedule in
                        guard let viewModel else { return }
                        Log.app.info("Scheduler executing: \(schedule.name) — \(schedule.prompt)")
                        viewModel.injectProactiveMessage(schedule.prompt)
                    }
                    schedulerService.start()

                    // Configure DevicePolicyService (J-1)
                    let devicePolicyService = DevicePolicyService(settings: settings)
                    viewModel.configureDevicePolicyService(devicePolicyService)
                    Task { await devicePolicyService.registerCurrentDevice() }

                    // Wire notification callbacks (H-3)
                    notificationManager.onReply = { [weak viewModel] text, category, originalBody in
                        guard let viewModel else { return }
                        viewModel.handleNotificationReply(text: text, category: category, originalBody: originalBody)
                    }
                    notificationManager.onOpenApp = { [weak viewModel] category in
                        guard let viewModel else { return }
                        viewModel.handleNotificationOpenApp(category: category)
                    }
                    if settings.heartbeatEnabled {
                        Task {
                            await notificationManager.requestAuthorizationIfNeeded()
                        }
                    }

                    // Refresh cached monthly cost for budget checking (C-2)
                    Task {
                        await viewModel.metricsCollector.refreshMonthCost()
                    }

                    // Wire UsageStore to AppDelegate for flush on termination (C-3)
                    appDelegate.usageStore = usageStore

                    // Setup menu bar manager (H-1)
                    if appDelegate.menuBarManager == nil {
                        let manager = MenuBarManager(settings: settings, viewModel: viewModel)
                        appDelegate.menuBarManager = manager
                        manager.setup()
                    }

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
                    schedulerService.stop()
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
                .onChange(of: settings.automationEnabled) { _, _ in
                    schedulerService.restart()
                }
                .onChange(of: settings.menuBarEnabled) { _, _ in
                    appDelegate.menuBarManager?.handleSettingsChange()
                }
                .onChange(of: settings.menuBarGlobalShortcutEnabled) { _, _ in
                    appDelegate.menuBarManager?.handleSettingsChange()
                }
                .onOpenURL { url in
                    viewModel.handleDeepLink(url: url)
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

        Window("로그 뷰어", id: "log-viewer") {
            LogViewerView()
        }
        .defaultSize(width: 1000, height: 600)

        Settings {
            SettingsView(
                settings: settings,
                keychainService: keychainService,
                contextService: contextService,
                sessionContext: sessionContext,
                ttsService: ttsService,
                downloadManager: modelDownloadManager,
                telegramService: telegramService,
                mcpService: mcpService,
                supabaseService: supabaseService,
                toolService: toolService,
                devicePolicyService: viewModel.devicePolicyService,
                schedulerService: schedulerService,
                heartbeatService: heartbeatService,
                notificationManager: notificationManager,
                metricsCollector: viewModel.metricsCollector,
                viewModel: viewModel,
                documentIndexer: documentIndexer,
                feedbackStore: viewModel.feedbackStore
            )
        }
        .commands {
            DebugCommands()
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

struct DebugCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("로그 뷰어") {
                openWindow(id: "log-viewer")
            }
            .keyboardShortcut("L", modifiers: [.command, .shift])
        }
    }
}
