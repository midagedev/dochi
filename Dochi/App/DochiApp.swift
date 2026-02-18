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
    private let controlPlaneService: LocalControlPlaneService

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

        self.controlPlaneService = LocalControlPlaneService { method, params in
            await Self.handleControlPlaneMethod(
                method: method,
                params: params,
                viewModel: viewModel,
                toolService: toolService,
                externalToolManager: externalToolManager
            )
        }

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
                DochiDevBridgeTools.register(toolService: toolService, manager: externalToolManager)
                if settings.localControlPlaneEnabled {
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

    nonisolated private static func handleControlPlaneMethod(
        method: String,
        params: [String: Any],
        viewModel: DochiViewModel,
        toolService: BuiltInToolService,
        externalToolManager: ExternalToolSessionManagerProtocol
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
                "timestamp": isoTimestamp(),
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

        case "bridge.open":
            return await handleBridgeOpen(params: params, externalToolManager: externalToolManager)

        case "bridge.status":
            return await handleBridgeStatus(params: params, externalToolManager: externalToolManager)

        case "bridge.send":
            return await handleBridgeSend(params: params, externalToolManager: externalToolManager)

        case "bridge.read":
            return await handleBridgeRead(params: params, externalToolManager: externalToolManager)

        default:
            return .failure(code: "method_not_found", message: "지원하지 않는 메서드입니다: \(method)")
        }
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
        let workingDirectory = nonEmptyString(params["working_directory"]) ?? "~"
        let arguments = params["arguments"] as? [String] ?? []

        let profile = await MainActor.run { () -> ExternalToolProfile in
            if let existing = externalToolManager.profiles.first(where: { $0.name == profileName }) {
                return existing
            }

            let created = ExternalToolProfile(
                name: profileName,
                command: preset.command,
                arguments: arguments,
                workingDirectory: workingDirectory,
                healthCheckPatterns: preset.healthPatterns
            )
            externalToolManager.saveProfile(created)
            return created
        }

        let existingSessionPayload = await MainActor.run { () -> UncheckedJSONObject? in
            guard let payload = existingBridgeSessionPayload(for: profile.id, manager: externalToolManager) else {
                return nil
            }
            return UncheckedJSONObject(value: payload)
        }
        if let existingSessionPayload {
            var payload = existingSessionPayload.value
            payload["reused"] = true
            return .ok(payload)
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
                let profileName = externalToolManager.profiles.first(where: { $0.id == session.profileId })?.name ?? "unknown"
                return [
                    "session_id": session.id.uuidString,
                    "profile_id": session.profileId.uuidString,
                    "profile_name": profileName,
                    "status": session.status.rawValue,
                    "started_at": session.startedAt.map(isoTimestamp(_:)) ?? NSNull(),
                    "last_activity": session.lastActivityText ?? NSNull(),
                ]
            }
            return UncheckedJSONArray(value: sessions)
        }
        let sessions = sessionsPayload.value

        return .ok([
            "count": sessions.count,
            "sessions": sessions,
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

        let lines = max(1, min(500, params["lines"] as? Int ?? 80))
        let output = await externalToolManager.captureOutput(sessionId: sessionId, lines: lines)
        return .ok([
            "session_id": sessionId.uuidString,
            "count": output.count,
            "lines": output,
        ])
    }

    @MainActor
    private static func existingBridgeSessionPayload(
        for profileId: UUID,
        manager: ExternalToolSessionManagerProtocol
    ) -> [String: Any]? {
        guard let session = manager.sessions.first(where: { $0.profileId == profileId && $0.status != .dead }) else {
            return nil
        }
        let profileName = manager.profiles.first(where: { $0.id == session.profileId })?.name ?? "unknown"
        return [
            "session_id": session.id.uuidString,
            "profile_id": session.profileId.uuidString,
            "profile_name": profileName,
            "status": session.status.rawValue,
            "started_at": session.startedAt.map(isoTimestamp(_:)) ?? NSNull(),
            "last_activity": session.lastActivityText ?? NSNull(),
        ]
    }

    @MainActor
    private static func bridgeSessionPayload(
        sessionId: UUID,
        manager: ExternalToolSessionManagerProtocol
    ) -> [String: Any]? {
        guard let session = manager.sessions.first(where: { $0.id == sessionId }) else {
            return nil
        }
        let profileName = manager.profiles.first(where: { $0.id == session.profileId })?.name ?? "unknown"
        return [
            "session_id": session.id.uuidString,
            "profile_id": session.profileId.uuidString,
            "profile_name": profileName,
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

    nonisolated private static func isoTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
