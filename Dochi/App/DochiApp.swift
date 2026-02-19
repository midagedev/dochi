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
        Task { @MainActor [weak self] in
            self?.ensurePrimaryWindowVisible()
        }

        // In some launch paths, SwiftUI scenes are attached after this callback.
        // Retry once shortly after launch so we don't end up with a headless app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            Task { @MainActor in
                self?.ensurePrimaryWindowVisible()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.ensurePrimaryWindowVisible()
        }
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

    @MainActor
    private func ensurePrimaryWindowVisible() {
        NSApp.activate(ignoringOtherApps: true)

        if let primaryWindow = Self.findPrimaryWindow() {
            primaryWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Ask the responder chain to create a main window if none exists.
        for actionName in ["newWindowForTab:", "newWindow:", "newDocument:"] {
            _ = NSApp.sendAction(Selector(actionName), to: nil, from: nil)
        }

        if let primaryWindow = Self.findPrimaryWindow() {
            primaryWindow.makeKeyAndOrderFront(nil)
        }
    }

    @MainActor
    private static func findPrimaryWindow() -> NSWindow? {
        NSApp.windows.first(where: { window in
            let className = window.className
            return className != "NSStatusBarWindow" && className != "_NSPopoverWindow"
        })
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
    private let controlPlaneService: LocalControlPlaneService
    private let controlPlaneTokenManager: ControlPlaneTokenManager

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

        let viewModel = DochiViewModel(
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
        )
        _viewModel = State(initialValue: viewModel)

        let controlPlaneTokenManager = ControlPlaneTokenManager()
        self.controlPlaneTokenManager = controlPlaneTokenManager
        self.controlPlaneService = LocalControlPlaneService(
            methodHandler: { method, params in
                await Self.handleControlPlaneMethod(
                    method: method,
                    params: params,
                    viewModel: viewModel,
                    toolService: toolService,
                    externalToolManager: externalToolManager,
                    tokenManager: controlPlaneTokenManager
                )
            },
            authTokenProvider: { controlPlaneTokenManager.currentToken() }
        )

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
            mainWindowContent
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

    private var mainWindowContent: some View {
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
                    Log.app.info("Scheduler executing: \(schedule.name) [target=\(schedule.targetSummary)] — \(schedule.prompt)")
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
                DochiDevBridgeTools.register(toolService: toolService, manager: externalToolManager)
                if settings.localControlPlaneEnabled {
                    controlPlaneTokenManager.rotate()
                    controlPlaneService.start()
                }

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
                controlPlaneService.stop()
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
            .onChange(of: settings.localControlPlaneEnabled) { _, enabled in
                if enabled {
                    controlPlaneTokenManager.rotate()
                    controlPlaneService.start()
                } else {
                    controlPlaneService.stop()
                }
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

    private enum ControlPlaneBridgePreset: String {
        case codex
        case claude
        case aider

        var command: String {
            switch self {
            case .codex:
                return "codex"
            case .claude:
                return "claude"
            case .aider:
                return "aider"
            }
        }

        var healthPatterns: HealthCheckPatterns {
            switch self {
            case .codex:
                return .codexCLI
            case .claude:
                return .claudeCode
            case .aider:
                return .aider
            }
        }

        var defaultProfileName: String {
            switch self {
            case .codex:
                return "Dochi Bridge Codex"
            case .claude:
                return "Dochi Bridge Claude"
            case .aider:
                return "Dochi Bridge Aider"
            }
        }
    }

    private struct UncheckedJSONObject: @unchecked Sendable {
        let value: [String: Any]
    }

    private struct UncheckedJSONArray: @unchecked Sendable {
        let value: [[String: Any]]
    }

    private struct UncheckedViewModel: @unchecked Sendable {
        let value: DochiViewModel
    }

    private static let streamRegistry = ControlPlaneStreamRegistry()

    nonisolated private static func handleControlPlaneMethod(
        method: String,
        params: [String: Any],
        viewModel: DochiViewModel,
        toolService: BuiltInToolService,
        externalToolManager: ExternalToolSessionManagerProtocol,
        tokenManager: ControlPlaneTokenManager
    ) async -> LocalControlPlaneMethodResult {
        switch method {
        case "app.ping":
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            return .ok([
                "status": "ok",
                "app": "Dochi",
                "version": version,
                "build": build,
                "socket_path": LocalControlPlaneService.defaultSocketURL.path,
                "token_path": tokenManager.tokenFilePath,
                "auth_required": true,
                "timestamp": isoTimestamp(),
            ])

        case "auth.rotate":
            let rotatedToken = tokenManager.rotate()
            return .ok([
                "status": "rotated",
                "token_path": tokenManager.tokenFilePath,
                "token_length": rotatedToken.count,
                "rotated_at": isoTimestamp(),
            ])

        case "session.list":
            let sessionsPayload = await MainActor.run { () -> UncheckedJSONArray in
                viewModel.loadConversations()
                let currentConversationId = viewModel.currentConversation?.id
                let sessions = viewModel.conversations.map { conversation in
                    let preview = (conversation.messages.last?.content ?? "")
                        .replacingOccurrences(of: "\n", with: " ")
                    return [
                        "id": conversation.id.uuidString,
                        "title": conversation.title,
                        "source": conversation.source.rawValue,
                        "message_count": conversation.messages.count,
                        "updated_at": isoTimestamp(conversation.updatedAt),
                        "is_active": currentConversationId == conversation.id,
                        "last_message_preview": String(preview.prefix(120)),
                    ]
                }
                return UncheckedJSONArray(value: sessions)
            }
            let sessions = sessionsPayload.value
            return .ok([
                "count": sessions.count,
                "sessions": sessions,
            ])

        case "chat.send":
            guard let prompt = (params["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !prompt.isEmpty else {
                return .failure(code: "empty_prompt", message: "prompt가 필요합니다.")
            }

            let timeoutSeconds = params["timeout_seconds"] as? Int ?? 120
            do {
                let response = try await viewModel.sendMessageFromControlPlane(
                    prompt: prompt,
                    timeoutSeconds: timeoutSeconds
                )
                var result: [String: Any] = [
                    "conversation_id": response.conversationId,
                    "assistant_message_id": response.assistantMessageId,
                    "assistant_message": response.assistantMessage,
                    "message_count": response.messageCount,
                ]
                result["status"] = "completed"
                return .ok(result)
            } catch let error as DochiViewModel.ControlPlaneChatSendError {
                return .failure(
                    code: error.errorCode,
                    message: error.errorDescription ?? "chat.send 실패"
                )
            } catch {
                return .failure(code: "internal_error", message: error.localizedDescription)
            }

        case "chat.stream.open":
            return await handleChatStreamOpen(params: params, viewModel: viewModel)

        case "chat.stream.read":
            return await handleChatStreamRead(params: params)

        case "chat.stream.close":
            return await handleChatStreamClose(params: params)

        case "tool.execute":
            guard let name = (params["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                return .failure(code: "missing_tool_name", message: "name이 필요합니다.")
            }

            let argumentsPayload = UncheckedJSONObject(value: params["arguments"] as? [String: Any] ?? [:])
            let toolResult = await executeTool(
                toolService: toolService,
                name: name,
                arguments: argumentsPayload
            )
            if toolResult.isError {
                return .failure(code: "tool_error", message: toolResult.content)
            }
            return .ok([
                "tool_name": name,
                "content": toolResult.content,
            ])

        case "log.recent":
            let minutes = max(1, min(1_440, params["minutes"] as? Int ?? 10))
            let limit = max(1, min(500, params["limit"] as? Int ?? 120))
            let category = nonEmptyString(params["category"])
            let level = nonEmptyString(params["level"])?.lowercased()
            let contains = nonEmptyString(params["contains"])

            do {
                let entries = try await fetchDochiLogs(
                    minutes: minutes,
                    category: category,
                    level: level,
                    contains: contains,
                    limit: limit
                )
                let serialized = entries.map { entry in
                    [
                        "timestamp": isoTimestamp(entry.date),
                        "category": entry.category,
                        "level": entry.level,
                        "message": entry.message,
                    ]
                }
                return .ok([
                    "count": serialized.count,
                    "entries": serialized,
                ])
            } catch {
                return .failure(code: "log_fetch_failed", message: error.localizedDescription)
            }

        case "log.tail.open":
            return await handleLogTailOpen(params: params)

        case "log.tail.read":
            return await handleLogTailRead(params: params)

        case "log.tail.close":
            return await handleLogTailClose(params: params)

        case "bridge.open":
            return await handleBridgeOpen(params: params, externalToolManager: externalToolManager)

        case "bridge.status":
            return await handleBridgeStatus(params: params, externalToolManager: externalToolManager)

        case "bridge.send":
            return await handleBridgeSend(params: params, externalToolManager: externalToolManager)

        case "bridge.read":
            return await handleBridgeRead(params: params, externalToolManager: externalToolManager)

        case "bridge.roots":
            return await handleBridgeRoots(params: params, externalToolManager: externalToolManager)

        case "bridge.session_history.reindex":
            return await handleBridgeSessionHistoryReindex(params: params, externalToolManager: externalToolManager)

        case "bridge.session_history.search":
            return await handleBridgeSessionHistorySearch(params: params, externalToolManager: externalToolManager)

        case "bridge.orchestrator.select_session":
            return await handleBridgeOrchestratorSelectSession(params: params, externalToolManager: externalToolManager)

        case "bridge.orchestrator.policy_matrix":
            return await handleBridgeOrchestratorPolicyMatrix(externalToolManager: externalToolManager)

        case "bridge.orchestrator.guard_command":
            return await handleBridgeOrchestratorGuardCommand(params: params, externalToolManager: externalToolManager)

        case "bridge.orchestrator.execute":
            return await handleBridgeOrchestratorExecute(params: params, externalToolManager: externalToolManager)

        case "bridge.repo.list":
            return await handleBridgeRepositoryList(externalToolManager: externalToolManager)

        case "bridge.repo.init":
            return await handleBridgeRepositoryInit(params: params, externalToolManager: externalToolManager)

        case "bridge.repo.clone":
            return await handleBridgeRepositoryClone(params: params, externalToolManager: externalToolManager)

        case "bridge.repo.attach":
            return await handleBridgeRepositoryAttach(params: params, externalToolManager: externalToolManager)

        case "bridge.repo.remove":
            return await handleBridgeRepositoryRemove(params: params, externalToolManager: externalToolManager)

        default:
            return .failure(code: "method_not_found", message: "지원하지 않는 메서드입니다: \(method)")
        }
    }

    nonisolated private static func handleChatStreamOpen(
        params: [String: Any],
        viewModel: DochiViewModel
    ) async -> LocalControlPlaneMethodResult {
        guard let prompt = nonEmptyString(params["prompt"]) else {
            return .failure(code: "empty_prompt", message: "prompt가 필요합니다.")
        }

        let timeoutSeconds = max(5, min(300, params["timeout_seconds"] as? Int ?? 120))
        let correlationId = nonEmptyString(params["correlation_id"]) ?? UUID().uuidString
        let streamId = await streamRegistry.createChatSession(correlationId: correlationId)
        let uncheckedViewModel = UncheckedViewModel(value: viewModel)

        let task = Task {
            do {
                _ = try await uncheckedViewModel.value.runControlPlaneChatStream(
                    prompt: prompt,
                    correlationId: correlationId,
                    timeoutSeconds: timeoutSeconds
                ) { event in
                    await streamRegistry.appendChatEvent(
                        streamId: streamId,
                        type: event.kind.rawValue,
                        timestamp: event.timestamp,
                        text: event.text,
                        toolName: event.toolName
                    )
                    logCorrelationEvent(event, correlationId: correlationId)
                }
                await streamRegistry.finishChat(streamId: streamId, errorMessage: nil)
            } catch let error as DochiViewModel.ControlPlaneChatSendError {
                await streamRegistry.finishChat(
                    streamId: streamId,
                    errorMessage: error.errorDescription ?? "chat.stream 실패"
                )
            } catch {
                await streamRegistry.finishChat(streamId: streamId, errorMessage: error.localizedDescription)
            }
        }

        await streamRegistry.attachChatTask(streamId: streamId, task: task)
        return .ok([
            "stream_id": streamId,
            "correlation_id": correlationId,
            "status": "started",
        ])
    }

    nonisolated private static func handleChatStreamRead(
        params: [String: Any]
    ) async -> LocalControlPlaneMethodResult {
        guard let streamId = nonEmptyString(params["stream_id"]) else {
            return .failure(code: "invalid_session_id", message: "stream_id가 필요합니다.")
        }
        let limit = max(1, min(500, params["limit"] as? Int ?? 80))

        guard let snapshot = await streamRegistry.readChat(streamId: streamId, limit: limit) else {
            return .failure(code: "session_not_found", message: "스트림 세션을 찾을 수 없습니다: \(streamId)")
        }

        var payload: [String: Any] = [
            "stream_id": snapshot.streamId,
            "correlation_id": snapshot.correlationId,
            "done": snapshot.done,
            "count": snapshot.events.count,
            "events": snapshot.events.map(serializeStreamEvent(_:)),
        ]
        if let errorMessage = snapshot.errorMessage, !errorMessage.isEmpty {
            payload["error_message"] = errorMessage
        }
        return .ok(payload)
    }

    nonisolated private static func handleChatStreamClose(
        params: [String: Any]
    ) async -> LocalControlPlaneMethodResult {
        guard let streamId = nonEmptyString(params["stream_id"]) else {
            return .failure(code: "invalid_session_id", message: "stream_id가 필요합니다.")
        }
        guard await streamRegistry.closeChat(streamId: streamId) else {
            return .failure(code: "session_not_found", message: "스트림 세션을 찾을 수 없습니다: \(streamId)")
        }
        return .ok([
            "stream_id": streamId,
            "status": "closed",
        ])
    }

    nonisolated private static func handleLogTailOpen(
        params: [String: Any]
    ) async -> LocalControlPlaneMethodResult {
        let correlationId = nonEmptyString(params["correlation_id"]) ?? UUID().uuidString
        let category = nonEmptyString(params["category"])
        let level = nonEmptyString(params["level"])?.lowercased()
        let contains = nonEmptyString(params["contains"])
        let lookbackSeconds = max(1, min(3_600, params["lookback_seconds"] as? Int ?? 30))
        let startAt = Date().addingTimeInterval(-TimeInterval(lookbackSeconds))

        let tailId = await streamRegistry.createLogTailSession(
            correlationId: correlationId,
            category: category,
            level: level,
            contains: contains,
            startAt: startAt
        )

        return .ok([
            "tail_id": tailId,
            "correlation_id": correlationId,
            "status": "started",
        ])
    }

    nonisolated private static func handleLogTailRead(
        params: [String: Any]
    ) async -> LocalControlPlaneMethodResult {
        guard let tailId = nonEmptyString(params["tail_id"]) else {
            return .failure(code: "invalid_session_id", message: "tail_id가 필요합니다.")
        }
        let limit = max(1, min(500, params["limit"] as? Int ?? 200))

        guard let state = await streamRegistry.logTailState(tailId: tailId) else {
            return .failure(code: "session_not_found", message: "log tail 세션을 찾을 수 없습니다: \(tailId)")
        }

        let elapsedMinutes = max(1, Int(ceil(Date().timeIntervalSince(state.cursorDate) / 60.0)) + 1)
        let windowMinutes = min(1_440, elapsedMinutes)

        do {
            let fetchLimit = max(limit * 5, 500)
            let fetched = try await fetchDochiLogs(
                minutes: windowMinutes,
                category: state.category,
                level: state.level,
                contains: state.contains,
                limit: fetchLimit
            )

            guard let snapshot = await streamRegistry.consumeLogTailEntries(
                tailId: tailId,
                entries: fetched,
                limit: limit
            ) else {
                return .failure(code: "session_not_found", message: "log tail 세션을 찾을 수 없습니다: \(tailId)")
            }

            return .ok([
                "tail_id": snapshot.tailId,
                "correlation_id": snapshot.correlationId,
                "count": snapshot.events.count,
                "events": snapshot.events.map(serializeStreamEvent(_:)),
            ])
        } catch {
            return .failure(code: "log_fetch_failed", message: error.localizedDescription)
        }
    }

    nonisolated private static func handleLogTailClose(
        params: [String: Any]
    ) async -> LocalControlPlaneMethodResult {
        guard let tailId = nonEmptyString(params["tail_id"]) else {
            return .failure(code: "invalid_session_id", message: "tail_id가 필요합니다.")
        }
        guard await streamRegistry.closeLogTail(tailId: tailId) else {
            return .failure(code: "session_not_found", message: "log tail 세션을 찾을 수 없습니다: \(tailId)")
        }
        return .ok([
            "tail_id": tailId,
            "status": "closed",
        ])
    }

    nonisolated private static func logCorrelationEvent(
        _ event: DochiViewModel.ControlPlaneStreamEvent,
        correlationId: String
    ) {
        switch event.kind {
        case .toolCall:
            let toolName = event.toolName ?? "unknown"
            Log.tool.info("[cid:\(correlationId)] tool_call \(toolName)")
        case .toolResult:
            let preview = String((event.text ?? "").prefix(120))
            Log.tool.info("[cid:\(correlationId)] tool_result \(preview)")
        default:
            break
        }
    }

    nonisolated private static func serializeStreamEvent(_ event: ControlPlaneStreamEventRecord) -> [String: Any] {
        var payload: [String: Any] = [
            "sequence": event.sequence,
            "type": event.type,
            "timestamp": event.timestamp,
            "correlation_id": event.correlationId,
        ]
        if let text = event.text {
            payload["text"] = text
        }
        if let toolName = event.toolName {
            payload["tool_name"] = toolName
        }
        if let category = event.category {
            payload["category"] = category
        }
        if let level = event.level {
            payload["level"] = level
        }
        if let message = event.message {
            payload["message"] = message
        }
        return payload
    }

    nonisolated private static func handleBridgeOpen(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard await externalToolManager.isTmuxAvailable else {
            return .failure(code: "tmux_unavailable", message: "tmux를 찾을 수 없습니다.")
        }

        let agentRaw = nonEmptyString(params["agent"])?.lowercased() ?? "codex"
        guard let preset = ControlPlaneBridgePreset(rawValue: agentRaw) else {
            return .failure(code: "invalid_agent", message: "agent는 codex, claude, aider 중 하나여야 합니다.")
        }

        let profileName = nonEmptyString(params["profile_name"]) ?? preset.defaultProfileName
        let requestedWorkingDirectory = nonEmptyString(params["working_directory"])
        let forceWorkingDirectory = boolValue(params["force_working_directory"]) ?? false
        let arguments = params["arguments"] as? [String] ?? []

        let existingProfile = await MainActor.run { () -> ExternalToolProfile? in
            externalToolManager.profiles.first(where: { $0.name == profileName })
        }

        if let existingProfile {
            let existingSessionPayload = await MainActor.run { () -> UncheckedJSONObject? in
                guard let payload = existingBridgeSessionPayload(for: existingProfile.id, manager: externalToolManager) else {
                    return nil
                }
                return UncheckedJSONObject(value: payload)
            }
            if let existingSessionPayload {
                let decision = BridgeWorkingDirectorySelector.decideForActiveSession(
                    profileWorkingDirectory: existingProfile.workingDirectory,
                    requestedWorkingDirectory: requestedWorkingDirectory,
                    forceWorkingDirectory: forceWorkingDirectory
                )
                var payload = existingSessionPayload.value
                payload["reused"] = true
                payload["working_directory"] = decision.workingDirectory
                payload["selection_reason"] = decision.selectionReason.rawValue
                payload["selection_detail"] = decision.selectionDetail
                return .ok(payload)
            }
        }

        let recommendedRoots: [GitRepositoryInsight]
        if existingProfile == nil, requestedWorkingDirectory == nil {
            recommendedRoots = await externalToolManager.discoverGitRepositoryInsights(
                searchPaths: nil,
                limit: 10
            )
        } else {
            recommendedRoots = []
        }
        let decision = BridgeWorkingDirectorySelector.decide(
            existingProfile: existingProfile,
            requestedWorkingDirectory: requestedWorkingDirectory,
            forceWorkingDirectory: forceWorkingDirectory,
            recommendedRoots: recommendedRoots
        )

        let profile = await MainActor.run { () -> ExternalToolProfile in
            if var existing = existingProfile {
                if decision.selectionReason == .existingProfileOverridden {
                    existing.workingDirectory = decision.workingDirectory
                    externalToolManager.saveProfile(existing)
                }
                return existing
            }

            let created = ExternalToolProfile(
                name: profileName,
                command: preset.command,
                arguments: arguments,
                workingDirectory: decision.workingDirectory,
                healthCheckPatterns: preset.healthPatterns
            )
            externalToolManager.saveProfile(created)
            return created
        }

        do {
            try await externalToolManager.startSession(profileId: profile.id)
        } catch {
            return .failure(code: "bridge_open_failed", message: error.localizedDescription)
        }

        let createdSessionPayload = await MainActor.run { () -> UncheckedJSONObject? in
            guard let payload = existingBridgeSessionPayload(for: profile.id, manager: externalToolManager) else {
                return nil
            }
            return UncheckedJSONObject(value: payload)
        }
        guard let createdSessionPayload else {
            return .failure(code: "bridge_open_failed", message: "브리지 세션 생성 후 조회에 실패했습니다.")
        }

        var payload = createdSessionPayload.value
        payload["reused"] = false
        payload["working_directory"] = decision.workingDirectory
        payload["selection_reason"] = decision.selectionReason.rawValue
        payload["selection_detail"] = decision.selectionDetail
        return .ok(payload)
    }

    nonisolated private static func handleBridgeStatus(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        if let sessionIdRaw = nonEmptyString(params["session_id"]) {
            guard let sessionId = UUID(uuidString: sessionIdRaw) else {
                return .failure(code: "invalid_session_id", message: "session_id 형식이 올바르지 않습니다.")
            }

            let payload = await MainActor.run { () -> UncheckedJSONObject? in
                guard let payload = bridgeSessionPayload(sessionId: sessionId, manager: externalToolManager) else {
                    return nil
                }
                return UncheckedJSONObject(value: payload)
            }
            guard let payload else {
                return .failure(code: "session_not_found", message: "세션을 찾을 수 없습니다: \(sessionIdRaw)")
            }
            return .ok(payload.value)
        }

        let sessionsPayload = await MainActor.run { () -> UncheckedJSONArray in
            let sessions: [[String: Any]] = externalToolManager.sessions.map { session in
                let profile = externalToolManager.profiles.first(where: { $0.id == session.profileId })
                let profileName = profile?.name ?? "unknown"
                return [
                    "session_id": session.id.uuidString,
                    "profile_id": session.profileId.uuidString,
                    "profile_name": profileName,
                    "working_directory": profile?.workingDirectory ?? "~",
                    "status": session.status.rawValue,
                    "started_at": session.startedAt.map(isoTimestamp(_:)) ?? NSNull(),
                    "last_activity": session.lastActivityText ?? NSNull(),
                ]
            }
            return UncheckedJSONArray(value: sessions)
        }
        let sessions = sessionsPayload.value
        let discoveredSessions = await externalToolManager.discoverLocalCodingSessions(limit: 80)
        let discoveredPayload: [[String: Any]] = discoveredSessions.map { session in
            [
                "source": session.source.rawValue,
                "provider": session.provider,
                "session_id": session.sessionId,
                "working_directory": session.workingDirectory ?? NSNull(),
                "path": session.path,
                "updated_at": isoTimestamp(session.updatedAt),
                "is_active": session.isActive,
            ]
        }
        let unifiedSessions = await externalToolManager.listUnifiedCodingSessions(limit: 120)
        let unifiedPayload: [[String: Any]] = unifiedSessions.map { session in
            [
                "source": session.source,
                "runtime_type": session.runtimeType.rawValue,
                "controllability_tier": session.controllabilityTier.rawValue,
                "activity_state": session.activityState.rawValue,
                "activity_score": session.activityScore,
                "activity_signals": [
                    "runtime_alive_score": session.activitySignals.runtimeAliveScore,
                    "recent_output_score": session.activitySignals.recentOutputScore,
                    "recent_command_score": session.activitySignals.recentCommandScore,
                    "file_freshness_score": session.activitySignals.fileFreshnessScore,
                    "error_penalty_score": session.activitySignals.errorPenaltyScore,
                ],
                "provider": session.provider,
                "native_session_id": session.nativeSessionId,
                "runtime_session_id": session.runtimeSessionId ?? NSNull(),
                "working_directory": session.workingDirectory ?? NSNull(),
                "repository_root": session.repositoryRoot ?? NSNull(),
                "path": session.path,
                "updated_at": isoTimestamp(session.updatedAt),
                "is_active": session.isActive,
                "is_unassigned": session.isUnassigned,
            ]
        }
        let unassignedCount = unifiedSessions.filter(\.isUnassigned).count

        return .ok([
            "count": sessions.count,
            "sessions": sessions,
            "discovered_count": discoveredPayload.count,
            "discovered_sessions": discoveredPayload,
            "unified_count": unifiedPayload.count,
            "unified_sessions": unifiedPayload,
            "unassigned_count": unassignedCount,
        ])
    }

    nonisolated private static func handleBridgeSend(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let sessionIdRaw = nonEmptyString(params["session_id"]),
              let sessionId = UUID(uuidString: sessionIdRaw) else {
            return .failure(code: "invalid_session_id", message: "유효한 session_id가 필요합니다.")
        }
        guard let command = nonEmptyString(params["command"]) else {
            return .failure(code: "missing_command", message: "command가 필요합니다.")
        }

        do {
            try await externalToolManager.sendCommand(sessionId: sessionId, command: command)
            return .ok([
                "session_id": sessionId.uuidString,
                "status": "sent",
                "command": command,
            ])
        } catch {
            return .failure(code: "bridge_send_failed", message: error.localizedDescription)
        }
    }

    nonisolated private static func handleBridgeRead(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let sessionIdRaw = nonEmptyString(params["session_id"]),
              let sessionId = UUID(uuidString: sessionIdRaw) else {
            return .failure(code: "invalid_session_id", message: "유효한 session_id가 필요합니다.")
        }

        let sessionExists = await MainActor.run {
            externalToolManager.sessions.contains { $0.id == sessionId }
        }
        guard sessionExists else {
            return .failure(code: "session_not_found", message: "세션을 찾을 수 없습니다: \(sessionIdRaw)")
        }

        let lines = max(1, min(500, params["lines"] as? Int ?? 80))
        let output = await externalToolManager.captureOutput(sessionId: sessionId, lines: lines)
        return .ok([
            "session_id": sessionId.uuidString,
            "count": output.count,
            "lines": output,
        ])
    }

    nonisolated private static func handleBridgeRoots(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        let limit = max(1, min(200, params["limit"] as? Int ?? 20))
        let searchPaths = params["search_paths"] as? [String]
        let roots = await externalToolManager.discoverGitRepositoryInsights(
            searchPaths: searchPaths,
            limit: limit
        )

        let payload = roots.map { insight in
            [
                "work_domain": insight.workDomain,
                "work_domain_confidence": insight.workDomainConfidence,
                "work_domain_reason": insight.workDomainReason,
                "path": insight.path,
                "name": insight.name,
                "branch": insight.branch,
                "origin_url": insight.originURL ?? NSNull(),
                "remote_host": insight.remoteHost ?? NSNull(),
                "remote_owner": insight.remoteOwner ?? NSNull(),
                "remote_repository": insight.remoteRepository ?? NSNull(),
                "last_commit_epoch": insight.lastCommitEpoch ?? NSNull(),
                "last_commit_iso8601": insight.lastCommitISO8601 ?? NSNull(),
                "last_commit_relative": insight.lastCommitRelative,
                "upstream_last_commit_epoch": insight.upstreamLastCommitEpoch ?? NSNull(),
                "upstream_last_commit_iso8601": insight.upstreamLastCommitISO8601 ?? NSNull(),
                "upstream_last_commit_relative": insight.upstreamLastCommitRelative,
                "days_since_last_commit": insight.daysSinceLastCommit ?? NSNull(),
                "recent_commit_count_30d": insight.recentCommitCount30d,
                "changed_file_count": insight.changedFileCount,
                "untracked_file_count": insight.untrackedFileCount,
                "ahead_count": insight.aheadCount ?? NSNull(),
                "behind_count": insight.behindCount ?? NSNull(),
                "score": insight.score,
            ] as [String: Any]
        }

        return .ok([
            "count": payload.count,
            "roots": payload,
        ])
    }

    nonisolated private static func handleBridgeSessionHistoryReindex(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        let limit = max(10, min(2_000, params["limit"] as? Int ?? 500))
        let chunkCount = await externalToolManager.rebuildSessionHistoryIndex(limit: limit)
        return .ok([
            "status": "reindexed",
            "limit": limit,
            "chunk_count": chunkCount,
        ])
    }

    nonisolated private static func handleBridgeSessionHistorySearch(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let query = nonEmptyString(params["query"]) else {
            return .failure(code: "missing_query", message: "query가 필요합니다.")
        }

        let limit = max(1, min(200, params["limit"] as? Int ?? 20))
        let repositoryRoot = nonEmptyString(params["repository_root"])
        let branch = nonEmptyString(params["branch"])
        let since = parseISO8601Timestamp(nonEmptyString(params["since"]))
        let until = parseISO8601Timestamp(nonEmptyString(params["until"]))

        let results = await externalToolManager.searchSessionHistory(
            query: SessionHistorySearchQuery(
                query: query,
                repositoryRoot: repositoryRoot,
                branch: branch,
                since: since,
                until: until,
                limit: limit
            )
        )

        let payload: [[String: Any]] = results.map { item in
            [
                "id": item.id.uuidString,
                "provider": item.provider,
                "session_id": item.sessionId,
                "repository_root": item.repositoryRoot ?? NSNull(),
                "branch": item.branch ?? NSNull(),
                "source_path": item.sourcePath,
                "score": item.score,
                "snippet": item.maskedSnippet,
                "start_at": isoTimestamp(item.startAt),
                "end_at": isoTimestamp(item.endAt),
                "tags": item.tags,
            ]
        }

        return .ok([
            "count": payload.count,
            "results": payload,
        ])
    }

    nonisolated private static func handleBridgeOrchestratorSelectSession(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        let repositoryRoot = nonEmptyString(params["repository_root"])
        let selection = await externalToolManager.selectSessionForOrchestration(repositoryRoot: repositoryRoot)
        return .ok(serializeOrchestrationSelection(selection))
    }

    nonisolated private static func handleBridgeOrchestratorPolicyMatrix(
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        let rules = await MainActor.run {
            externalToolManager.orchestrationGuardPolicyRules()
        }
        let payload: [[String: Any]] = rules.map { rule in
            [
                "tier": rule.tier.rawValue,
                "command_class": rule.commandClass.rawValue,
                "decision": rule.decisionKind.rawValue,
                "policy_code": rule.policyCode.rawValue,
                "reason": rule.reason,
            ]
        }
        return .ok([
            "count": payload.count,
            "rules": payload,
        ])
    }

    nonisolated private static func handleBridgeOrchestratorGuardCommand(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let tierRaw = nonEmptyString(params["tier"]),
              let tier = CodingSessionControllabilityTier(rawValue: tierRaw) else {
            return .failure(code: "invalid_tier", message: "유효한 tier가 필요합니다. (t0_full/t1_attach/t2_observe/t3_unknown)")
        }
        guard let command = nonEmptyString(params["command"]) else {
            return .failure(code: "missing_command", message: "command가 필요합니다.")
        }

        let decision = await MainActor.run {
            externalToolManager.evaluateOrchestrationExecutionGuard(
                tier: tier,
                command: command
            )
        }

        if decision.kind == .denied {
            return .failure(code: decision.policyCode.rawValue, message: decision.reason)
        }
        if decision.kind == .confirmationRequired {
            return .failure(code: decision.policyCode.rawValue, message: decision.reason)
        }

        return .ok([
            "decision": decision.kind.rawValue,
            "policy_code": decision.policyCode.rawValue,
            "command_class": decision.commandClass.rawValue,
            "reason": decision.reason,
            "is_destructive_command": decision.isDestructiveCommand,
        ])
    }

    nonisolated private static func handleBridgeOrchestratorExecute(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let command = nonEmptyString(params["command"]) else {
            return .failure(code: "missing_command", message: "command가 필요합니다.")
        }
        let repositoryRoot = nonEmptyString(params["repository_root"])
        let confirmed = boolValue(params["confirmed"]) ?? false
        let selection = await externalToolManager.selectSessionForOrchestration(repositoryRoot: repositoryRoot)

        switch selection.action {
        case .reuseT0Active, .attachT1:
            guard let session = selection.selectedSession else {
                return .failure(code: "session_not_found", message: "선택된 세션을 찾을 수 없습니다.")
            }
            let decision = await MainActor.run {
                externalToolManager.evaluateOrchestrationExecutionGuard(
                    tier: session.controllabilityTier,
                    command: command
                )
            }

            if decision.kind == .denied {
                return .failure(code: decision.policyCode.rawValue, message: decision.reason)
            }
            if decision.kind == .confirmationRequired, !confirmed {
                return .failure(code: decision.policyCode.rawValue, message: decision.reason)
            }

            guard let runtimeSessionId = session.runtimeSessionId,
                  let runtimeUUID = UUID(uuidString: runtimeSessionId) else {
                return .failure(code: "runtime_session_missing", message: "실행 가능한 runtime_session_id를 찾을 수 없습니다.")
            }

            do {
                try await externalToolManager.sendCommand(sessionId: runtimeUUID, command: command)
                return .ok([
                    "status": "sent",
                    "command": command,
                    "selection": serializeOrchestrationSelection(selection),
                    "guard": [
                        "decision": decision.kind.rawValue,
                        "policy_code": decision.policyCode.rawValue,
                        "command_class": decision.commandClass.rawValue,
                        "reason": decision.reason,
                        "is_destructive_command": decision.isDestructiveCommand,
                    ],
                ])
            } catch {
                return .failure(code: "bridge_send_failed", message: error.localizedDescription)
            }
        case .createT0:
            return .failure(
                code: "session_creation_required",
                message: "실행 가능한 세션이 없어 새 T0 세션 생성이 필요합니다."
            )
        case .analyzeOnly:
            if let session = selection.selectedSession {
                let decision = await MainActor.run {
                    externalToolManager.evaluateOrchestrationExecutionGuard(
                        tier: session.controllabilityTier,
                        command: command
                    )
                }
                return .failure(code: decision.policyCode.rawValue, message: decision.reason)
            }
            return .failure(
                code: "analyze_only_fallback",
                message: "현재는 분석 전용(T2/T3) 세션만 존재하여 실행이 차단되었습니다."
            )
        case .none:
            return .failure(code: "session_not_found", message: selection.reason)
        }
    }

    nonisolated private static func handleBridgeRepositoryList(
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        let repositories = await MainActor.run {
            externalToolManager.managedRepositories
                .filter { !$0.isArchived }
                .sorted(by: { $0.updatedAt > $1.updatedAt })
        }
        let payload = repositories.map(serializeManagedRepository(_:))
        return .ok([
            "count": payload.count,
            "repositories": payload,
        ])
    }

    nonisolated private static func handleBridgeRepositoryInit(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let path = nonEmptyString(params["path"]) else {
            return .failure(code: "invalid_path", message: "path가 필요합니다.")
        }
        let defaultBranch = nonEmptyString(params["default_branch"]) ?? "main"
        let createReadme = params["create_readme"] as? Bool ?? false
        let createGitignore = params["create_gitignore"] as? Bool ?? false

        do {
            let repository = try await externalToolManager.initializeRepository(
                path: path,
                defaultBranch: defaultBranch,
                createReadme: createReadme,
                createGitignore: createGitignore
            )
            return .ok([
                "status": "initialized",
                "repository": serializeManagedRepository(repository),
            ])
        } catch {
            return .failure(code: "bridge_repo_init_failed", message: error.localizedDescription)
        }
    }

    nonisolated private static func handleBridgeRepositoryClone(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let remoteURL = nonEmptyString(params["remote_url"]) else {
            return .failure(code: "missing_remote_url", message: "remote_url이 필요합니다.")
        }
        guard let destinationPath = nonEmptyString(params["destination_path"]) else {
            return .failure(code: "missing_destination_path", message: "destination_path가 필요합니다.")
        }
        let branch = nonEmptyString(params["branch"])

        do {
            let repository = try await externalToolManager.cloneRepository(
                remoteURL: remoteURL,
                destinationPath: destinationPath,
                branch: branch
            )
            return .ok([
                "status": "cloned",
                "repository": serializeManagedRepository(repository),
            ])
        } catch {
            return .failure(code: "bridge_repo_clone_failed", message: error.localizedDescription)
        }
    }

    nonisolated private static func handleBridgeRepositoryAttach(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let path = nonEmptyString(params["path"]) else {
            return .failure(code: "invalid_path", message: "path가 필요합니다.")
        }

        do {
            let repository = try await externalToolManager.attachRepository(path: path)
            return .ok([
                "status": "attached",
                "repository": serializeManagedRepository(repository),
            ])
        } catch {
            return .failure(code: "bridge_repo_attach_failed", message: error.localizedDescription)
        }
    }

    nonisolated private static func handleBridgeRepositoryRemove(
        params: [String: Any],
        externalToolManager: ExternalToolSessionManagerProtocol
    ) async -> LocalControlPlaneMethodResult {
        guard let repositoryIdRaw = nonEmptyString(params["repository_id"]),
              let repositoryId = UUID(uuidString: repositoryIdRaw) else {
            return .failure(code: "invalid_repository_id", message: "유효한 repository_id가 필요합니다.")
        }
        let deleteDirectory = params["delete_directory"] as? Bool ?? false

        do {
            try await externalToolManager.removeManagedRepository(id: repositoryId, deleteDirectory: deleteDirectory)
            return .ok([
                "status": "removed",
                "repository_id": repositoryId.uuidString,
                "delete_directory": deleteDirectory,
            ])
        } catch {
            return .failure(code: "bridge_repo_remove_failed", message: error.localizedDescription)
        }
    }

    nonisolated private static func serializeManagedRepository(_ repository: ManagedGitRepository) -> [String: Any] {
        [
            "repository_id": repository.id.uuidString,
            "name": repository.name,
            "root_path": repository.rootPath,
            "source": repository.source.rawValue,
            "origin_url": repository.originURL ?? NSNull(),
            "default_branch": repository.defaultBranch ?? NSNull(),
            "is_archived": repository.isArchived,
            "created_at": isoTimestamp(repository.createdAt),
            "updated_at": isoTimestamp(repository.updatedAt),
        ]
    }

    @MainActor
    private static func existingBridgeSessionPayload(
        for profileId: UUID,
        manager: ExternalToolSessionManagerProtocol
    ) -> [String: Any]? {
        guard let session = manager.sessions.first(where: { $0.profileId == profileId && $0.status != .dead }) else {
            return nil
        }
        let profile = manager.profiles.first(where: { $0.id == session.profileId })
        let profileName = profile?.name ?? "unknown"
        return [
            "session_id": session.id.uuidString,
            "profile_id": session.profileId.uuidString,
            "profile_name": profileName,
            "working_directory": profile?.workingDirectory ?? "~",
            "status": session.status.rawValue,
            "started_at": session.startedAt.map(isoTimestamp(_:)) ?? NSNull(),
            "last_activity": session.lastActivityText ?? NSNull(),
        ]
    }

    nonisolated private static func serializeOrchestrationSelection(
        _ selection: OrchestrationSessionSelection
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "action": selection.action.rawValue,
            "reason": selection.reason,
            "repository_root": selection.repositoryRoot ?? NSNull(),
        ]
        if let selected = selection.selectedSession {
            payload["selected_session"] = [
                "source": selected.source,
                "runtime_type": selected.runtimeType.rawValue,
                "controllability_tier": selected.controllabilityTier.rawValue,
                "provider": selected.provider,
                "native_session_id": selected.nativeSessionId,
                "runtime_session_id": selected.runtimeSessionId ?? NSNull(),
                "working_directory": selected.workingDirectory ?? NSNull(),
                "repository_root": selected.repositoryRoot ?? NSNull(),
                "activity_state": selected.activityState.rawValue,
                "activity_score": selected.activityScore,
                "path": selected.path,
                "updated_at": isoTimestamp(selected.updatedAt),
            ] as [String: Any]
        } else {
            payload["selected_session"] = NSNull()
        }
        return payload
    }

    @MainActor
    private static func bridgeSessionPayload(
        sessionId: UUID,
        manager: ExternalToolSessionManagerProtocol
    ) -> [String: Any]? {
        guard let session = manager.sessions.first(where: { $0.id == sessionId }) else {
            return nil
        }
        let profile = manager.profiles.first(where: { $0.id == session.profileId })
        let profileName = profile?.name ?? "unknown"
        return [
            "session_id": session.id.uuidString,
            "profile_id": session.profileId.uuidString,
            "profile_name": profileName,
            "working_directory": profile?.workingDirectory ?? "~",
            "status": session.status.rawValue,
            "started_at": session.startedAt.map(isoTimestamp(_:)) ?? NSNull(),
            "last_activity": session.lastActivityText ?? NSNull(),
        ]
    }

    nonisolated private static func nonEmptyString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "1", "true", "yes", "y":
                return true
            case "0", "false", "no", "n":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    nonisolated private static func isoTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    nonisolated private static func parseISO8601Timestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFractional.date(from: value) {
            return parsed
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }

    @MainActor
    private static func executeTool(
        toolService: BuiltInToolService,
        name: String,
        arguments: UncheckedJSONObject
    ) async -> ToolResult {
        await toolService.execute(name: name, arguments: arguments.value)
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
