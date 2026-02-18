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
    private let pluginManager: PluginManager
    private let resourceOptimizer: any ResourceOptimizerProtocol
    private let terminalService: any TerminalServiceProtocol
    private let proactiveSuggestionService: any ProactiveSuggestionServiceProtocol
    private let interestDiscoveryService: InterestDiscoveryService
    private let externalToolManager: ExternalToolSessionManager
    private let telegramProactiveRelay: TelegramProactiveRelay
    private let deviceHeartbeatService: DeviceHeartbeatService

    init() {
        let settings = AppSettings()
        let contextService = ContextService()
        let keychainService = KeychainService()
        Self.migrateLegacyAPIKeysIfNeeded(keychainService: keychainService)
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
        let deviceHeartbeatService = DeviceHeartbeatService(supabaseService: supabaseService, settings: settings)
        self.deviceHeartbeatService = deviceHeartbeatService

        let delegationManager = DelegationManager()
        self.delegationManager = delegationManager

        let schedulerService = SchedulerService(settings: settings)
        self.schedulerService = schedulerService

        // Plugin Manager (J-4)
        let pluginManager = PluginManager()
        self.pluginManager = pluginManager

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

        // Resource Optimizer (J-5)
        let resourceOptimizer = ResourceOptimizerService(baseURL: appSupportURL, usageStore: usageStore)
        self.resourceOptimizer = resourceOptimizer

        // Terminal Service (K-1)
        let terminalService = TerminalService(
            maxSessions: settings.terminalMaxSessions,
            maxBufferLines: settings.terminalMaxBufferLines,
            defaultShellPath: settings.terminalShellPath,
            commandTimeout: settings.terminalCommandTimeout
        )
        self.terminalService = terminalService

        // Interest Discovery Service (K-3)
        let interestDiscoveryService = InterestDiscoveryService(settings: settings)
        self.interestDiscoveryService = interestDiscoveryService

        // External Tool Session Manager (K-4)
        let externalToolManager = ExternalToolSessionManager(settings: settings)
        self.externalToolManager = externalToolManager

        // Proactive Suggestion Service (K-2)
        let proactiveSuggestionService = ProactiveSuggestionService(
            settings: settings,
            contextService: contextService,
            conversationService: conversationService,
            sessionContext: sessionContext
        )
        self.proactiveSuggestionService = proactiveSuggestionService

        // Telegram Proactive Relay (K-6)
        let telegramProactiveRelay = TelegramProactiveRelay(
            settings: settings,
            telegramService: telegramService,
            keychainService: keychainService
        )
        self.telegramProactiveRelay = telegramProactiveRelay
        heartbeatService.setTelegramRelay(telegramProactiveRelay)
        proactiveSuggestionService.setTelegramRelay(telegramProactiveRelay)

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

        // Start Telegram connection only on the designated host device.
        if settings.isTelegramHost,
           settings.telegramEnabled,
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
                        guard settings.isTelegramHost else {
                            Log.telegram.debug("isTelegramHost=false 이므로 텔레그램 메시지 처리를 건너뜀")
                            return
                        }
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

                    // Configure PluginManager (J-4)
                    viewModel.configurePluginManager(pluginManager)

                    // Configure ResourceOptimizer (J-5)
                    viewModel.configureResourceOptimizer(resourceOptimizer)
                    heartbeatService.setResourceOptimizer(resourceOptimizer)

                    // Configure SchedulerService (J-3)
                    viewModel.configureSchedulerService(schedulerService)
                    schedulerService.setExecutionHandler { [weak viewModel] schedule in
                        guard let viewModel else { return }
                        Log.app.info("Scheduler executing: \(schedule.name) [agent=\(schedule.agentName)] — \(schedule.prompt)")
                        try await viewModel.executeScheduledAutomation(schedule)
                    }
                    schedulerService.start()

                    // Configure TerminalService (K-1)
                    viewModel.configureTerminalService(terminalService)
                    toolService.configureTerminalService(terminalService)

                    // Configure ProactiveSuggestionService (K-2)
                    viewModel.configureProactiveSuggestionService(proactiveSuggestionService)
                    proactiveSuggestionService.start()

                    // Configure TelegramProactiveRelay (K-6)
                    viewModel.configureTelegramProactiveRelay(telegramProactiveRelay)
                    applyTelegramHostRole()

                    // Configure InterestDiscoveryService (K-3)
                    viewModel.configureInterestDiscoveryService(interestDiscoveryService)
                    heartbeatService.setInterestDiscoveryService(interestDiscoveryService)

                    // Configure ExternalToolSessionManager (K-4)
                    viewModel.configureExternalToolManager(externalToolManager)
                    heartbeatService.setExternalToolManager(externalToolManager)
                    ExternalToolTools.register(toolService: toolService, manager: externalToolManager)

                    // Configure DevicePolicyService (J-1)
                    let devicePolicyService = DevicePolicyService(settings: settings)
                    viewModel.configureDevicePolicyService(devicePolicyService)
                    Task {
                        await devicePolicyService.registerCurrentDevice()
                    }

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
                    proactiveSuggestionService.stop()
                    deviceHeartbeatService.stopHeartbeat()
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
                .onChange(of: settings.autoSyncEnabled) { _, _ in
                    viewModel.syncEngine?.refreshAutoSyncSchedule()
                }
                .onChange(of: settings.realtimeSyncEnabled) { _, _ in
                    viewModel.syncEngine?.refreshAutoSyncSchedule()
                }
                .onChange(of: settings.proactiveSuggestionEnabled) { _, newValue in
                    if newValue {
                        proactiveSuggestionService.start()
                    } else {
                        proactiveSuggestionService.stop()
                    }
                }
                .onChange(of: settings.menuBarEnabled) { _, _ in
                    appDelegate.menuBarManager?.handleSettingsChange()
                }
                .onChange(of: settings.menuBarGlobalShortcutEnabled) { _, _ in
                    appDelegate.menuBarManager?.handleSettingsChange()
                }
                .task(id: proactiveSuggestionNotificationTrigger) {
                    await syncProactiveSuggestionNotification()
                }
                .task(id: deviceHeartbeatLifecycleTrigger) {
                    await syncDeviceHeartbeatLifecycle()
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
            settingsView
        }
        .commands {
            DebugCommands()
        }
    }

    private var settingsView: some View {
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
            pluginManager: pluginManager,
            documentIndexer: documentIndexer,
            feedbackStore: viewModel.feedbackStore,
            resourceOptimizer: resourceOptimizer
        )
    }

    private func applyTelegramHostRole() {
        if settings.isTelegramHost {
            startTelegramIngressIfNeeded()
            telegramProactiveRelay.start()
        } else {
            stopTelegramIngress()
            telegramProactiveRelay.stop()
        }
    }

    private func startTelegramIngressIfNeeded() {
        guard settings.isTelegramHost, settings.telegramEnabled else { return }
        guard let token = keychainService.load(account: "telegram_bot_token"), !token.isEmpty else {
            return
        }

        // Ensure we do not keep stale polling/webhook sessions when host role changes.
        stopTelegramIngress()

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

    private func stopTelegramIngress() {
        telegramService.stopPolling()
        Task {
            try? await telegramService.stopWebhook()
        }
    }

    private func deviceHeartbeatWorkspaceIds() -> [UUID] {
        if let workspaceId = UUID(uuidString: settings.currentWorkspaceId) {
            return [workspaceId]
        }
        return [sessionContext.workspaceId]
    }

    private var proactiveSuggestionNotificationTrigger: String {
        let suggestionId = viewModel.currentSuggestion?.id.uuidString ?? "none"
        return "\(settings.suggestionNotificationChannel)-\(suggestionId)"
    }

    private func syncProactiveSuggestionNotification() async {
        let channel = NotificationChannel(rawValue: settings.suggestionNotificationChannel) ?? .off
        guard channel.deliversToApp,
              let suggestion = viewModel.currentSuggestion else { return }
        guard !NSApp.isActive else { return }

        await notificationManager.requestAuthorizationIfNeeded()
        notificationManager.sendProactiveSuggestionNotification(suggestion: suggestion)
    }

    private var deviceHeartbeatLifecycleTrigger: String {
        let userId = supabaseService.authState.userId?.uuidString ?? "signed-out"
        return "\(settings.deviceCloudSyncEnabled)-\(settings.currentWorkspaceId)-\(userId)"
    }

    private func syncDeviceHeartbeatLifecycle() async {
        guard settings.deviceCloudSyncEnabled,
              supabaseService.isConfigured,
              supabaseService.authState.userId != nil else {
            deviceHeartbeatService.stopHeartbeat()
            return
        }

        await deviceHeartbeatService.startHeartbeat(workspaceIds: deviceHeartbeatWorkspaceIds())
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

    private static func migrateLegacyAPIKeysIfNeeded(keychainService: KeychainServiceProtocol) {
        for provider in LLMProvider.allCases where provider.requiresAPIKey {
            guard let legacyAccount = provider.legacyAPIKeyAccount else { continue }

            let currentValue = keychainService.load(account: provider.keychainAccount)
            if let currentValue, !currentValue.isEmpty {
                continue
            }

            guard let legacyValue = keychainService.load(account: legacyAccount), !legacyValue.isEmpty else {
                continue
            }

            do {
                try keychainService.save(account: provider.keychainAccount, value: legacyValue)
                try? keychainService.delete(account: legacyAccount)
                Log.app.info("Migrated legacy API key account for \(provider.displayName)")
            } catch {
                Log.app.error("Failed to migrate API key for \(provider.displayName): \(error.localizedDescription)")
            }
        }
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
