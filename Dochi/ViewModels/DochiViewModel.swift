import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class DochiViewModel {
    enum ScheduledAutomationExecutionError: LocalizedError {
        case interactionBusy
        case emptyPrompt
        case agentNotFound(String)
        case dispatchRejected(String)

        var errorDescription: String? {
            switch self {
            case .interactionBusy:
                return "앱이 다른 작업을 처리 중이라 자동화를 실행할 수 없습니다."
            case .emptyPrompt:
                return "자동화 프롬프트가 비어 있습니다."
            case .agentNotFound(let name):
                return "자동화 대상 에이전트를 찾을 수 없습니다: \(name)"
            case .dispatchRejected(let reason):
                return reason
            }
        }
    }

    enum ControlPlaneChatSendError: LocalizedError {
        case interactionBusy
        case emptyPrompt
        case timeout
        case requestFailed(String)
        case noConversation
        case noAssistantResponse

        var errorCode: String {
            switch self {
            case .interactionBusy:
                return "interaction_busy"
            case .emptyPrompt:
                return "empty_prompt"
            case .timeout:
                return "chat_timeout"
            case .requestFailed:
                return "chat_failed"
            case .noConversation:
                return "no_conversation"
            case .noAssistantResponse:
                return "no_assistant_response"
            }
        }

        var errorDescription: String? {
            switch self {
            case .interactionBusy:
                return "앱이 다른 작업을 처리 중입니다."
            case .emptyPrompt:
                return "prompt가 비어 있습니다."
            case .timeout:
                return "응답 대기 시간이 초과되었습니다."
            case .requestFailed(let reason):
                return reason
            case .noConversation:
                return "대화를 생성하지 못했습니다."
            case .noAssistantResponse:
                return "어시스턴트 응답을 찾을 수 없습니다."
            }
        }
    }

    struct ControlPlaneChatSendResponse: Sendable {
        let conversationId: String
        let assistantMessageId: String
        let assistantMessage: String
        let messageCount: Int
    }

    struct ControlPlaneStreamEvent: Sendable {
        enum Kind: String, Sendable {
            case partial
            case toolCall = "tool_call"
            case toolResult = "tool_result"
            case done
            case error
        }

        let kind: Kind
        let text: String?
        let toolName: String?
        let timestamp: String
    }

    struct ControlPlaneSecretOptions: Sendable {
        let allowedToolNames: [String]

        init(allowedToolNames: [String]) {
            self.allowedToolNames = allowedToolNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { result, value in
                    if !result.contains(value) {
                        result.append(value)
                    }
                }
        }
    }

    struct MenuBarSubscriptionUsageSummary: Identifiable, Equatable, Sendable {
        enum Provider: String, CaseIterable, Sendable {
            case codex
            case claude
            case gemini

            var displayName: String {
                switch self {
                case .codex:
                    return "Codex"
                case .claude:
                    return "Claude"
                case .gemini:
                    return "Gemini"
                }
            }
        }

        enum Availability: Sendable, Equatable {
            case active
            case notConfigured
            case serviceUnavailable
        }

        struct UsageWindow: Equatable, Sendable, Identifiable {
            let label: String
            let usedPercent: Double
            let detail: String?

            var id: String {
                "\(label)-\(Int(usedPercent.rounded()))-\(detail ?? "")"
            }
        }

        let provider: Provider
        let remainingText: String
        let detailText: String
        let availability: Availability
        let windows: [UsageWindow]
        let statusText: String?

        var id: Provider { provider }

        init(
            provider: Provider,
            remainingText: String,
            detailText: String,
            availability: Availability,
            windows: [UsageWindow] = [],
            statusText: String? = nil
        ) {
            self.provider = provider
            self.remainingText = remainingText
            self.detailText = detailText
            self.availability = availability
            self.windows = windows
            self.statusText = statusText
        }
    }

    enum ControlPlaneExecutionMode: Sendable {
        case standard
        case secret(ControlPlaneSecretOptions)
    }

    // MARK: - State

    private(set) var interactionState: InteractionState = .idle
    private(set) var sessionState: SessionState = .inactive
    private(set) var processingSubState: ProcessingSubState?

    // MARK: - Data

    var currentConversation: Conversation?
    var conversations: [Conversation] = []
    var streamingText: String = ""
    var inputText: String = ""
    var errorMessage: String?
    var currentToolName: String?
    var partialTranscript: String = ""
    var pendingToolConfirmation: ToolConfirmation?
    var userProfiles: [UserProfile] = []
    var currentUserName: String = "(사용자 없음)"
    var selectedCapabilityLabel: String?

    // MARK: - Tool Execution Tracking (UX-7)
    var toolExecutions: [ToolExecution] = []
    var allToolCardsCollapsed: Bool = true

    // MARK: - Image Attachments (I-3)
    var pendingImages: [ImageAttachment] = []
    var visionWarningDismissed: Bool = false

    // MARK: - Memory Toast (UX-8)
    var memoryToastEvents: [MemoryToastEvent] = []

    // MARK: - Notification Navigation (H-3)
    /// Set by notification handlers to request ContentView navigate to a specific section.
    var notificationRequestedSection: String?
    /// Set by notification handlers to request showing the memory panel.
    var notificationShowMemoryPanel: Bool = false

    // MARK: - Spotlight (H-4)
    private(set) var spotlightIndexer: SpotlightIndexerProtocol?

    // MARK: - RAG (I-1)
    private(set) var documentIndexer: DocumentIndexer?
    private var ragLastContextInfo: RAGContextInfo?

    // MARK: - Memory Consolidation (I-2)
    private(set) var memoryConsolidator: MemoryConsolidator?
    private var lastConsolidatedConversationId: UUID?

    // MARK: - Feedback (I-4)
    private(set) var feedbackStore: FeedbackStoreProtocol?

    // MARK: - Agent Delegation (J-2)
    private(set) var delegationManager: DelegationManager?
    var showDelegationMonitor: Bool = false

    // MARK: - Scheduler (J-3)
    private(set) var schedulerService: SchedulerServiceProtocol?

    // MARK: - Plugin System (J-4)
    private(set) var pluginManager: PluginManagerProtocol?

    // MARK: - Resource Optimizer (J-5)
    private(set) var resourceOptimizer: (any ResourceOptimizerProtocol)?
    private(set) var menuBarSubscriptionUsage: [MenuBarSubscriptionUsageSummary] =
        MenuBarSubscriptionUsageSummary.Provider.allCases.map { provider in
            MenuBarSubscriptionUsageSummary(
                provider: provider,
                remainingText: "미등록",
                detailText: "플랜 연결 필요",
                availability: .notConfigured
            )
        }
    private(set) var isMenuBarSubscriptionUsageRefreshing: Bool = false

    // MARK: - Terminal (K-1)
    private(set) var terminalService: TerminalServiceProtocol?
    var showTerminalPanel: Bool = false

    // MARK: - Proactive Suggestions (K-2)
    private(set) var proactiveSuggestionService: ProactiveSuggestionServiceProtocol?
    var showSuggestionHistory: Bool = false

    // MARK: - Task Opportunity (D1)
    private(set) var completedTaskOpportunityIDs: Set<UUID> = []
    var taskOpportunityActionInFlightID: UUID?
    var taskOpportunityActionFeedback: TaskOpportunityActionFeedback?
    var reminderOpportunityExecutor: ((TaskOpportunity) async -> ToolResult)?
    var kanbanOpportunityExecutor: ((TaskOpportunity) -> Bool)?

    // MARK: - Interest Discovery (K-3)
    private(set) var interestDiscoveryService: InterestDiscoveryServiceProtocol?

    // MARK: - Telegram Proactive (K-6)
    private(set) var telegramProactiveRelay: TelegramProactiveRelayProtocol?

    // MARK: - External Tool (K-4)
    private(set) var externalToolManager: ExternalToolSessionManagerProtocol?
    private var telegramOrchestrationApprovalStore = OrchestrationExecutionApprovalStore()
    private let telegramOrchestrationSummaryService: any OrchestrationSummaryServiceProtocol = OrchestrationSummaryService()

    // MARK: - Device Policy (J-1)
    var devicePolicyService: DevicePolicyServiceProtocol?
    var showConnectedDevicesPopover: Bool = false

    /// @Observable 관찰 추적을 위해 구체 타입으로 캐스팅하여 반환
    var concreteSpotlightIndexer: SpotlightIndexer? {
        spotlightIndexer as? SpotlightIndexer
    }

    // MARK: - Sync (G-3)
    private(set) var syncEngine: SyncEngine?

    // MARK: - Conversation Organization
    var conversationTags: [ConversationTag] = []
    var conversationFolders: [ConversationFolder] = []
    var conversationFilter: ConversationFilter = ConversationFilter()
    var isMultiSelectMode: Bool = false
    var selectedConversationIds: Set<UUID> = []

    // MARK: - TTS Fallback State
    var isTTSFallbackActive: Bool = false
    var ttsFallbackProviderName: String?

    // MARK: - Offline Fallback State
    var isOfflineFallbackActive: Bool = false
    var originalProvider: LLMProvider?
    var originalModel: String?
    var localServerStatus: LocalServerStatus = .unknown

    // MARK: - Services

    private var toolService: BuiltInToolServiceProtocol
    var allToolInfos: [ToolInfo] { toolService.allToolInfos }
    let contextService: ContextServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private(set) var keychainService: KeychainServiceProtocol
    private let speechService: SpeechServiceProtocol
    private var ttsService: TTSServiceProtocol
    private let soundService: SoundServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    let metricsCollector: MetricsCollector
    private let nativeAgentLoopService: NativeAgentLoopService
    private let nativeSessionStore: NativeSessionStore
    private let contextCompactionService: ContextCompactionService
    private let memoryPipeline: any MemoryPipelineProtocol
    @ObservationIgnored private var modelRouterV2: ModelRouterV2

    // MARK: - Internal

    private var processingTask: Task<Void, Never>?
    private var sessionTimeoutTask: Task<Void, Never>?
    private var confirmationTimeoutTask: Task<Void, Never>?
    private var localServerMonitorTask: Task<Void, Never>?
    private var activeControlPlaneExecutionMode: ControlPlaneExecutionMode = .standard
    private var sentenceChunker = SentenceChunker()
    private static let sessionEndingTimeout: TimeInterval = 10
    private static let toolConfirmationTimeout: TimeInterval = 30

    // MARK: - Computed

    var isVoiceMode: Bool {
        settings.currentInteractionMode == .voiceAndText
    }

    var isMicAuthorized: Bool {
        speechService.isAuthorized
    }

    /// Token usage from the most recent LLM exchange (input tokens sent).
    var lastInputTokens: Int? {
        metricsCollector.recentMetrics.last?.inputTokens
    }

    /// Token usage from the most recent LLM exchange (output tokens received).
    var lastOutputTokens: Int? {
        metricsCollector.recentMetrics.last?.outputTokens
    }

    /// Context window size (tokens) for the currently selected model.
    var contextWindowTokens: Int {
        settings.currentProvider.contextWindowTokens(for: settings.llmModel)
    }

    private var activeControlPlaneSecretOptions: ControlPlaneSecretOptions? {
        if case .secret(let options) = activeControlPlaneExecutionMode {
            return options
        }
        return nil
    }

    private var isControlPlaneSecretExecutionActive: Bool {
        activeControlPlaneSecretOptions != nil
    }

    // MARK: - Init

    init(
        toolService: BuiltInToolServiceProtocol,
        contextService: ContextServiceProtocol,
        conversationService: ConversationServiceProtocol,
        keychainService: KeychainServiceProtocol,
        speechService: SpeechServiceProtocol,
        ttsService: TTSServiceProtocol,
        soundService: SoundServiceProtocol,
        settings: AppSettings,
        sessionContext: SessionContext,
        metricsCollector: MetricsCollector = MetricsCollector(),
        nativeAgentLoopService: NativeAgentLoopService? = nil,
        nativeSessionStore: NativeSessionStore? = nil,
        contextCompactionService: ContextCompactionService? = nil,
        memoryPipeline: (any MemoryPipelineProtocol)? = nil,
        modelRouter: ModelRouterV2? = nil
    ) {
        self.toolService = toolService
        self.contextService = contextService
        self.conversationService = conversationService
        self.keychainService = keychainService
        self.speechService = speechService
        self.ttsService = ttsService
        self.soundService = soundService
        self.settings = settings
        self.sessionContext = sessionContext
        self.metricsCollector = metricsCollector
        let resolvedMemoryPipeline = memoryPipeline ?? MemoryPipelineService(contextService: contextService)
        self.memoryPipeline = resolvedMemoryPipeline
        let resolvedNativeAgentLoopService: NativeAgentLoopService
        if let nativeAgentLoopService {
            nativeAgentLoopService.setMemoryPipeline(resolvedMemoryPipeline)
            resolvedNativeAgentLoopService = nativeAgentLoopService
        } else {
            resolvedNativeAgentLoopService = NativeAgentLoopService(
                adapters: [
                    AnthropicNativeLLMProviderAdapter(),
                    OpenAINativeLLMProviderAdapter(),
                    ZAINativeLLMProviderAdapter(),
                    OllamaNativeLLMProviderAdapter(),
                    LMStudioNativeLLMProviderAdapter()
                ],
                toolService: toolService,
                memoryPipeline: resolvedMemoryPipeline
            )
        }
        self.nativeAgentLoopService = resolvedNativeAgentLoopService
        self.nativeSessionStore = nativeSessionStore ?? NativeSessionStore()
        self.contextCompactionService = contextCompactionService ?? ContextCompactionService()
        if let modelRouter {
            self.modelRouterV2 = modelRouter
        } else {
            self.modelRouterV2 = ModelRouterV2(
                settings: settings,
                readinessProbe: { provider in
                    if provider.isLocal {
                        switch provider {
                        case .ollama:
                            let baseURL = URL(string: settings.ollamaBaseURL)
                            ?? URL(string: "http://localhost:11434")!
                            return await OllamaModelFetcher.isAvailable(baseURL: baseURL)
                        case .lmStudio:
                            let baseURL = URL(string: settings.lmStudioBaseURL)
                            ?? URL(string: "http://localhost:1234")!
                            return await LMStudioModelFetcher.isAvailable(baseURL: baseURL)
                        default:
                            return false
                        }
                    }

                    guard provider.requiresAPIKey else { return true }
                    if let key = keychainService.load(account: provider.keychainAccount)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !key.isEmpty {
                        return true
                    }
                    if let legacyAccount = provider.legacyAPIKeyAccount,
                       let legacy = keychainService.load(account: legacyAccount)?
                       .trimmingCharacters(in: .whitespacesAndNewlines),
                       !legacy.isEmpty {
                        return true
                    }
                    return false
                },
                supportsProvider: { provider in
                    resolvedNativeAgentLoopService.supports(provider: provider)
                }
            )
        }

        // Wire TTS completion callback
        self.ttsService.onComplete = { [weak self] in
            self?.handleTTSComplete()
        }

        // Wire TTS fallback state callback
        if let router = ttsService as? TTSRouter {
            router.onFallbackStateChanged = { [weak self] active, providerName in
                self?.isTTSFallbackActive = active
                self?.ttsFallbackProviderName = providerName
            }
        }

        // Wire sensitive tool confirmation handler
        self.toolService.confirmationHandler = { [weak self] toolName, toolDescription in
            guard let self else { return false }
            return await self.requestToolConfirmation(toolName: toolName, toolDescription: toolDescription)
        }

        // Load user profiles
        reloadProfiles()

        // Start local server monitoring if using a local provider
        startLocalServerMonitoringIfNeeded()

        Log.app.info("DochiViewModel initialized")
    }

    // MARK: - Sync (G-3)

    /// SyncEngine 설정 (SupabaseService 주입 후 호출)
    func configureSyncEngine(supabaseService: SupabaseServiceProtocol) {
        // 기존 엔진의 자동 동기화 Task 정리 (Task 누수 방지)
        syncEngine?.stopAutoSync()

        let engine = SyncEngine(
            supabaseService: supabaseService,
            settings: settings,
            contextService: contextService,
            conversationService: conversationService
        )
        self.syncEngine = engine
        Log.cloud.info("SyncEngine configured")
    }

    /// 동기화 상태 복원 (앱 시작 시)
    func restoreSyncState() {
        syncEngine?.restoreSyncState()
    }

    /// 동기화 토스트 제거
    func dismissSyncToast(id: UUID) {
        syncEngine?.dismissSyncToast(id: id)
    }

    // MARK: - Spotlight (H-4)

    /// SpotlightIndexer 설정
    func configureSpotlightIndexer(_ indexer: SpotlightIndexerProtocol) {
        self.spotlightIndexer = indexer
        Log.app.info("SpotlightIndexer configured")
    }

    /// RAG DocumentIndexer 설정
    func configureDocumentIndexer(_ indexer: DocumentIndexer) {
        self.documentIndexer = indexer
        Log.app.info("DocumentIndexer configured")
    }

    /// Memory Consolidator 설정 (I-2)
    func configureMemoryConsolidator(_ consolidator: MemoryConsolidator) {
        self.memoryConsolidator = consolidator
        Log.app.info("MemoryConsolidator configured")
    }

    /// FeedbackStore 설정 (I-4)
    func configureFeedbackStore(_ store: FeedbackStoreProtocol) {
        self.feedbackStore = store
        Log.app.info("FeedbackStore configured")
    }

    func configureDevicePolicyService(_ service: DevicePolicyServiceProtocol) {
        self.devicePolicyService = service
        Log.app.info("DevicePolicyService configured")
    }

    func configureDelegationManager(_ manager: DelegationManager) {
        self.delegationManager = manager
        Log.app.info("DelegationManager configured")
    }

    func configureSchedulerService(_ service: SchedulerServiceProtocol) {
        self.schedulerService = service
        Log.app.info("SchedulerService configured")
    }

    /// PluginManager 설정 (J-4)
    func configurePluginManager(_ manager: PluginManagerProtocol) {
        self.pluginManager = manager
        Log.app.info("PluginManager configured")
    }

    /// ResourceOptimizerService 설정 (J-5)
    func configureResourceOptimizer(_ optimizer: any ResourceOptimizerProtocol) {
        self.resourceOptimizer = optimizer
        Log.app.info("ResourceOptimizerService configured")
        Task {
            let added = await optimizer.bootstrapDefaultExternalSubscriptionsIfNeeded()
            if added > 0 {
                Log.app.info("ResourceOptimizer auto-bootstrapped \(added) external subscriptions")
            }
            await self.refreshMenuBarSubscriptionUsage()
        }
    }

    // MARK: - Terminal (K-1)

    func configureTerminalService(_ service: TerminalServiceProtocol) {
        self.terminalService = service
        Log.app.info("TerminalService configured")
    }

    func toggleTerminalPanel() {
        showTerminalPanel.toggle()
        if showTerminalPanel, let service = terminalService, service.sessions.isEmpty {
            service.createSession(name: nil, shellPath: settings.terminalShellPath)
        }
    }

    func createTerminalSession() {
        guard let service = terminalService else { return }
        service.createSession(name: nil, shellPath: settings.terminalShellPath)
        if !showTerminalPanel && settings.terminalAutoShowPanel {
            showTerminalPanel = true
        }
    }

    func closeTerminalSession() {
        guard let service = terminalService,
              let activeId = service.activeSessionId else { return }
        service.closeSession(id: activeId)
        if service.sessions.isEmpty {
            showTerminalPanel = false
        }
    }

    func clearTerminalOutput() {
        guard let service = terminalService,
              let activeId = service.activeSessionId else { return }
        service.clearOutput(for: activeId)
    }

    // MARK: - Proactive Suggestions (K-2)

    func configureProactiveSuggestionService(_ service: ProactiveSuggestionServiceProtocol) {
        self.proactiveSuggestionService = service
        Log.app.info("ProactiveSuggestionService configured")
    }

    // MARK: - Telegram Proactive (K-6)

    func configureTelegramProactiveRelay(_ relay: TelegramProactiveRelayProtocol) {
        self.telegramProactiveRelay = relay
        Log.app.info("TelegramProactiveRelay configured")
    }

    // MARK: - External Tool (K-4)

    func configureExternalToolManager(_ manager: ExternalToolSessionManagerProtocol) {
        self.externalToolManager = manager
        Log.app.info("ExternalToolSessionManager configured")
    }

    func configureOrchestrationApprovalStore(_ store: OrchestrationExecutionApprovalStore) {
        self.telegramOrchestrationApprovalStore = store
        Log.app.info("OrchestrationExecutionApprovalStore configured")
    }

    // MARK: - Interest Discovery (K-3)

    func configureInterestDiscoveryService(_ service: InterestDiscoveryServiceProtocol) {
        self.interestDiscoveryService = service
        // Load profile for current user
        if let userId = sessionContext.currentUserId {
            service.loadProfile(userId: userId)
        }
        Log.app.info("InterestDiscoveryService configured")
    }

    var currentSuggestion: ProactiveSuggestion? {
        proactiveSuggestionService?.currentSuggestion
    }

    var menuBarSuggestion: ProactiveSuggestion? {
        guard settings.proactiveSuggestionMenuBarEnabled else { return nil }
        return currentSuggestion
    }

    func refreshMenuBarSubscriptionUsage() async {
        guard !isMenuBarSubscriptionUsageRefreshing else { return }
        isMenuBarSubscriptionUsageRefreshing = true
        defer { isMenuBarSubscriptionUsageRefreshing = false }

        guard let optimizer = resourceOptimizer else {
            menuBarSubscriptionUsage = Self.menuBarUnavailablePlaceholders()
            return
        }

        if optimizer.subscriptions.isEmpty {
            _ = await optimizer.bootstrapDefaultExternalSubscriptionsIfNeeded()
        }

        let subscriptions = optimizer.subscriptions
        guard !subscriptions.isEmpty else {
            menuBarSubscriptionUsage = Self.menuBarNotConfiguredPlaceholders()
            return
        }

        let groupedWithoutSnapshots = Self.menuBarUsageGroups(
            from: subscriptions,
            snapshots: [:]
        )
        menuBarSubscriptionUsage = Self.menuBarSummaries(from: groupedWithoutSnapshots)

        if let cached = optimizer.latestSubscriptionUsageSnapshot,
           !cached.utilizations.isEmpty {
            let cachedGrouped = Self.menuBarUsageGroups(
                from: cached.utilizations.map(\.subscription),
                snapshots: cached.monitoringSnapshots
            )
            if !cachedGrouped.isEmpty {
                menuBarSubscriptionUsage = Self.menuBarSummaries(from: cachedGrouped)
            }
        }

        let refreshed = await optimizer.refreshSubscriptionUsageSnapshot(force: false)
        let refreshedGrouped = Self.menuBarUsageGroups(
            from: refreshed.utilizations.map(\.subscription),
            snapshots: refreshed.monitoringSnapshots
        )
        menuBarSubscriptionUsage = refreshedGrouped.isEmpty
            ? Self.menuBarSummaries(from: groupedWithoutSnapshots)
            : Self.menuBarSummaries(from: refreshedGrouped)
    }

    private static func menuBarUnavailablePlaceholders() -> [MenuBarSubscriptionUsageSummary] {
        MenuBarSubscriptionUsageSummary.Provider.allCases.map { provider in
            MenuBarSubscriptionUsageSummary(
                provider: provider,
                remainingText: "연결 없음",
                detailText: "사용량 서비스 비활성",
                availability: .serviceUnavailable
            )
        }
    }

    private static func menuBarNotConfiguredPlaceholders() -> [MenuBarSubscriptionUsageSummary] {
        MenuBarSubscriptionUsageSummary.Provider.allCases.map { provider in
            MenuBarSubscriptionUsageSummary(
                provider: provider,
                remainingText: "미등록",
                detailText: "플랜 연결 필요",
                availability: .notConfigured
            )
        }
    }

    private static func menuBarUsageGroups(
        from subscriptions: [SubscriptionPlan],
        snapshots: [UUID: SubscriptionMonitoringSnapshot]
    ) -> [MenuBarSubscriptionUsageSummary.Provider: (SubscriptionPlan, SubscriptionMonitoringSnapshot?)] {
        var grouped: [MenuBarSubscriptionUsageSummary.Provider: (SubscriptionPlan, SubscriptionMonitoringSnapshot?)] = [:]
        for subscription in subscriptions {
            guard let provider = menuBarProvider(from: subscription.providerName) else {
                continue
            }
            let snapshot = snapshots[subscription.id]
            let candidate = (subscription, snapshot)
            if let existing = grouped[provider] {
                if shouldPreferMenuBarUsageCandidate(candidate: candidate, over: existing) {
                    grouped[provider] = candidate
                }
            } else {
                grouped[provider] = candidate
            }
        }
        return grouped
    }

    private static func menuBarSummaries(
        from grouped: [MenuBarSubscriptionUsageSummary.Provider: (SubscriptionPlan, SubscriptionMonitoringSnapshot?)]
    ) -> [MenuBarSubscriptionUsageSummary] {
        MenuBarSubscriptionUsageSummary.Provider.allCases.map { provider in
            guard let entry = grouped[provider] else {
                return MenuBarSubscriptionUsageSummary(
                    provider: provider,
                    remainingText: "미등록",
                    detailText: "플랜 연결 필요",
                    availability: .notConfigured
                )
            }
            return makeMenuBarUsageSummary(
                provider: provider,
                snapshot: entry.1
            )
        }
    }

    private static func menuBarProvider(
        from providerName: String
    ) -> MenuBarSubscriptionUsageSummary.Provider? {
        let normalized = providerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("claude") || normalized.contains("anthropic") {
            return .claude
        }
        if normalized.contains("gemini") {
            return .gemini
        }
        if normalized.contains("codex")
            || normalized.contains("chatgpt")
            || normalized.contains("openai") {
            return .codex
        }
        return nil
    }

    private static func shouldPreferMenuBarUsageCandidate(
        candidate: (SubscriptionPlan, SubscriptionMonitoringSnapshot?),
        over current: (SubscriptionPlan, SubscriptionMonitoringSnapshot?)
    ) -> Bool {
        let candidateWindowCount = menuBarWindowCount(candidate.1)
        let currentWindowCount = menuBarWindowCount(current.1)
        if candidateWindowCount != currentWindowCount {
            return candidateWindowCount > currentWindowCount
        }

        let candidateHasPrimaryWindow = candidate.1?.primaryWindow != nil
        let currentHasPrimaryWindow = current.1?.primaryWindow != nil
        if candidateHasPrimaryWindow != currentHasPrimaryWindow {
            return candidateHasPrimaryWindow
        }

        let candidateUpdatedAt = candidate.1?.lastCollectedAt ?? candidate.0.createdAt
        let currentUpdatedAt = current.1?.lastCollectedAt ?? current.0.createdAt
        if candidateUpdatedAt != currentUpdatedAt {
            return candidateUpdatedAt > currentUpdatedAt
        }

        let candidateHasLimit = candidate.0.monthlyTokenLimit != nil
        let currentHasLimit = current.0.monthlyTokenLimit != nil
        if candidateHasLimit != currentHasLimit {
            return candidateHasLimit
        }

        return candidate.0.id.uuidString < current.0.id.uuidString
    }

    private static func menuBarWindowCount(_ snapshot: SubscriptionMonitoringSnapshot?) -> Int {
        guard let snapshot else { return 0 }
        var count = 0
        if snapshot.primaryWindow != nil { count += 1 }
        if snapshot.secondaryWindow != nil { count += 1 }
        return count
    }

    private static func makeMenuBarUsageSummary(
        provider: MenuBarSubscriptionUsageSummary.Provider,
        snapshot: SubscriptionMonitoringSnapshot?
    ) -> MenuBarSubscriptionUsageSummary {
        let windows = menuBarUsageWindows(snapshot)
        let statusText = snapshot?.statusPresentation.label

        if let leadingWindow = windows.first {
            let remainingPercent = max(0, min(100, 100 - leadingWindow.usedPercent))
            let label = menuBarWindowLabel(leadingWindow.label)
            return MenuBarSubscriptionUsageSummary(
                provider: provider,
                remainingText: "\(Int(remainingPercent.rounded()))% 남음",
                detailText: "\(label) 사용 \(Int(leadingWindow.usedPercent.rounded()))%",
                availability: .active,
                windows: windows,
                statusText: statusText
            )
        }

        return MenuBarSubscriptionUsageSummary(
            provider: provider,
            remainingText: "잔여 미확인",
            detailText: statusText ?? "주간/세션 데이터 대기",
            availability: .active,
            windows: windows,
            statusText: statusText
        )
    }

    private static func menuBarUsageWindows(
        _ snapshot: SubscriptionMonitoringSnapshot?
    ) -> [MenuBarSubscriptionUsageSummary.UsageWindow] {
        guard let snapshot else { return [] }
        var windows: [MenuBarSubscriptionUsageSummary.UsageWindow] = []

        if let primary = snapshot.primaryWindow {
            windows.append(
                MenuBarSubscriptionUsageSummary.UsageWindow(
                    label: menuBarWindowTitle(primary, fallback: "세션"),
                    usedPercent: primary.usedPercent,
                    detail: menuBarWindowResetDetail(primary)
                )
            )
        }
        if let secondary = snapshot.secondaryWindow {
            let fallback = secondary.windowMinutes == 10_080 ? "주간" : "보조"
            windows.append(
                MenuBarSubscriptionUsageSummary.UsageWindow(
                    label: menuBarWindowTitle(secondary, fallback: fallback),
                    usedPercent: secondary.usedPercent,
                    detail: menuBarWindowResetDetail(secondary)
                )
            )
        }
        return windows
    }

    private static func menuBarWindowTitle(
        _ window: MonitoringUsageWindowSnapshot,
        fallback: String
    ) -> String {
        if let minutes = window.windowMinutes, minutes > 0 {
            if minutes == 300 { return "세션" }
            if minutes == 10_080 { return "주간" }
            if minutes == 1_440 { return "일간" }
            if minutes % 1_440 == 0 { return "\(minutes / 1_440)일" }
            if minutes % 60 == 0 { return "\(minutes / 60)시간" }
            return "\(minutes)분"
        }
        let trimmed = window.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func menuBarWindowLabel(_ rawLabel: String) -> String {
        let trimmed = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "윈도우" }
        return trimmed
    }

    private static func menuBarWindowResetDetail(_ window: MonitoringUsageWindowSnapshot) -> String? {
        if let resetsAt = window.resetsAt {
            return menuBarRemainingDurationText(resetsAt.timeIntervalSince(Date()))
        }

        guard let reset = window.resetDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !reset.isEmpty else {
            return nil
        }
        let compact = reset.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        if let parsedSeconds = menuBarParseResetSeconds(from: compact) {
            return menuBarRemainingDurationText(parsedSeconds)
        }

        // 표기를 남은시간 기준으로 통일하기 위해 절대 시각 문자열은 노출하지 않는다.
        return "남은시간 확인중"
    }

    private static func menuBarRemainingDurationText(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "갱신 반영 대기" }
        if seconds < 60 { return "1분 미만 남음" }
        if seconds < 3_600 {
            return "\(Int(ceil(seconds / 60)))분 남음"
        }
        if seconds < 86_400 {
            return "\(Int(ceil(seconds / 3_600)))시간 남음"
        }
        return "\(Int(ceil(seconds / 86_400)))일 남음"
    }

    private static func menuBarParseResetSeconds(from text: String) -> TimeInterval? {
        let lowered = text.lowercased()

        if let days = menuBarExtractNumber(
            from: lowered,
            patterns: [#"(\d+)\s*(day|days|d)\b"#, #"(\d+)\s*일"#]
        ) {
            return TimeInterval(days * 86_400)
        }
        if let hours = menuBarExtractNumber(
            from: lowered,
            patterns: [#"(\d+)\s*(hour|hours|hr|hrs|h)\b"#, #"(\d+)\s*시간"#]
        ) {
            return TimeInterval(hours * 3_600)
        }
        if let minutes = menuBarExtractNumber(
            from: lowered,
            patterns: [#"(\d+)\s*(minute|minutes|min|mins|m)\b"#, #"(\d+)\s*분"#]
        ) {
            return TimeInterval(minutes * 60)
        }
        return nil
    }

    private static func menuBarExtractNumber(
        from text: String,
        patterns: [String]
    ) -> Int? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else {
                continue
            }
            guard match.numberOfRanges > 1 else { continue }
            let numberRange = match.range(at: 1)
            guard numberRange.location != NSNotFound else { continue }
            let raw = nsText.substring(with: numberRange)
            if let value = Int(raw), value >= 0 {
                return value
            }
        }
        return nil
    }

    var suggestionHistory: [ProactiveSuggestion] {
        proactiveSuggestionService?.suggestionHistory ?? []
    }

    var proactiveSuggestionState: ProactiveSuggestionState {
        proactiveSuggestionService?.state ?? .disabled
    }

    var isSuggestionPaused: Bool {
        get { proactiveSuggestionService?.isPaused ?? false }
        set { proactiveSuggestionService?.isPaused = newValue }
    }

    var suggestionToastEvents: [SuggestionToastEvent] {
        proactiveSuggestionService?.toastEvents ?? []
    }

    func recordUserActivity() {
        proactiveSuggestionService?.recordActivity()
    }

    func acceptSuggestion(_ suggestion: ProactiveSuggestion) {
        proactiveSuggestionService?.acceptSuggestion(suggestion)
        inputText = suggestion.suggestedPrompt
        sendMessage()
    }

    func deferSuggestion(_ suggestion: ProactiveSuggestion) {
        proactiveSuggestionService?.deferSuggestion(suggestion)
    }

    func dismissSuggestionType(_ suggestion: ProactiveSuggestion) {
        proactiveSuggestionService?.dismissSuggestionType(suggestion)
    }

    func dismissSuggestionToast(id: UUID) {
        proactiveSuggestionService?.dismissToast(id: id)
    }

    func toggleProactiveSuggestionPause() {
        guard let service = proactiveSuggestionService else { return }
        service.isPaused.toggle()
        Log.app.info("Proactive suggestion \(service.isPaused ? "paused" : "resumed")")
    }

    func executeTaskOpportunity(_ opportunity: TaskOpportunity) {
        taskOpportunityActionInFlightID = opportunity.id

        Task { @MainActor in
            let feedback = await performTaskOpportunity(opportunity)
            taskOpportunityActionInFlightID = nil
            taskOpportunityActionFeedback = feedback

            if feedback.isSuccess {
                completedTaskOpportunityIDs.insert(opportunity.id)
            } else {
                errorMessage = feedback.message
            }

            let opportunityId = opportunity.id
            try? await Task.sleep(for: .seconds(3))
            if taskOpportunityActionFeedback?.opportunityId == opportunityId {
                taskOpportunityActionFeedback = nil
            }
        }
    }

    private func performTaskOpportunity(_ opportunity: TaskOpportunity) async -> TaskOpportunityActionFeedback {
        switch opportunity.actionKind {
        case .createReminder:
            let result: ToolResult
            if let reminderOpportunityExecutor {
                result = await reminderOpportunityExecutor(opportunity)
            } else {
                result = await registerReminderFromOpportunity(opportunity)
            }

            return TaskOpportunityActionFeedback(
                opportunityId: opportunity.id,
                isSuccess: !result.isError,
                message: result.content
            )

        case .createKanbanCard:
            let isSuccess: Bool
            if let kanbanOpportunityExecutor {
                isSuccess = kanbanOpportunityExecutor(opportunity)
            } else {
                isSuccess = registerKanbanFromOpportunity(opportunity)
            }

            let message: String
            if isSuccess {
                message = "칸반에 '\(opportunity.suggestedTitle)' 항목을 등록했습니다."
            } else {
                message = "칸반 등록에 실패했습니다. 보드/컬럼 설정을 확인해주세요."
            }

            return TaskOpportunityActionFeedback(
                opportunityId: opportunity.id,
                isSuccess: isSuccess,
                message: message
            )
        }
    }

    private func registerReminderFromOpportunity(_ opportunity: TaskOpportunity) async -> ToolResult {
        var arguments: [String: Any] = [
            "title": opportunity.suggestedTitle
        ]
        if let notes = opportunity.suggestedNotes, !notes.isEmpty {
            arguments["notes"] = notes
        }
        if let dueDate = opportunity.dueDateISO8601, !dueDate.isEmpty {
            arguments["due_date"] = dueDate
        }

        let tool = CreateReminderTool()
        return await tool.execute(arguments: arguments)
    }

    private func registerKanbanFromOpportunity(_ opportunity: TaskOpportunity) -> Bool {
        let targetBoardName: String
        if let boardName = opportunity.boardName?.trimmingCharacters(in: .whitespacesAndNewlines), !boardName.isEmpty {
            targetBoardName = boardName
        } else {
            targetBoardName = "기본 보드"
        }

        let board = KanbanManager.shared.board(name: targetBoardName) ?? KanbanManager.shared.createBoard(name: targetBoardName)
        let description = opportunity.suggestedNotes ?? "Heartbeat opportunity"

        return KanbanManager.shared.addCard(
            boardId: board.id,
            title: opportunity.suggestedTitle,
            priority: .medium,
            description: description
        ) != nil
    }

    func dismissScheduleExecutionBanner() {
        schedulerService?.clearCurrentExecution()
    }

    /// Execute a scheduler entry by routing to the selected target and dispatching the prompt.
    func executeScheduledAutomation(_ schedule: ScheduleEntry) async throws {
        let prompt = schedule.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw ScheduledAutomationExecutionError.emptyPrompt
        }
        try await executeAgentScheduledAutomation(schedule: schedule, prompt: prompt)
    }

    private func executeAgentScheduledAutomation(schedule: ScheduleEntry, prompt: String) async throws {
        guard interactionState == .idle else {
            throw ScheduledAutomationExecutionError.interactionBusy
        }

        let requestedAgent = schedule.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let availableAgents = contextService.listAgents(workspaceId: sessionContext.workspaceId)
        guard let targetAgent = resolveScheduledAgentName(requestedAgent, available: availableAgents) else {
            throw ScheduledAutomationExecutionError.agentNotFound(schedule.agentName)
        }

        if settings.activeAgentName.localizedCaseInsensitiveCompare(targetAgent) != .orderedSame {
            switchAgent(name: targetAgent)
        } else {
            ensureConversation()
        }

        let beforeMessageCount = currentConversation?.messages.count ?? 0
        inputText = prompt
        sendMessage()

        let afterMessageCount = currentConversation?.messages.count ?? 0
        if afterMessageCount == beforeMessageCount {
            let reason = errorMessage ?? "자동화 프롬프트를 전송하지 못했습니다."
            throw ScheduledAutomationExecutionError.dispatchRejected(reason)
        }
    }

    /// 피드백 제출 (I-4)
    func submitFeedback(messageId: UUID, conversationId: UUID, rating: FeedbackRating, category: FeedbackCategory? = nil, comment: String? = nil) {
        // Look up the message's actual provider/model from metadata (C-1 fix)
        let message = findMessage(id: messageId, in: conversationId)
        let provider = message?.metadata?.provider ?? settings.llmProvider
        let model = message?.metadata?.model ?? settings.llmModel

        let entry = FeedbackEntry(
            messageId: messageId,
            conversationId: conversationId,
            rating: rating,
            category: category,
            comment: comment,
            agentName: settings.activeAgentName,
            provider: provider,
            model: model
        )
        feedbackStore?.add(entry)
    }

    /// 피드백 삭제 (I-4)
    func removeFeedback(messageId: UUID) {
        feedbackStore?.remove(messageId: messageId)
    }

    /// 대화에서 메시지를 찾기 (C-1: 메시지 메타데이터 조회용)
    private func findMessage(id messageId: UUID, in conversationId: UUID) -> Message? {
        // Check currentConversation first (most common case)
        if currentConversation?.id == conversationId,
           let msg = currentConversation?.messages.first(where: { $0.id == messageId }) {
            return msg
        }
        // Fall back to conversations list
        if let conv = conversations.first(where: { $0.id == conversationId }),
           let msg = conv.messages.first(where: { $0.id == messageId }) {
            return msg
        }
        return nil
    }

    private func resolveScheduledAgentName(_ requestedAgentName: String, available: [String]) -> String? {
        let trimmed = requestedAgentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = trimmed.isEmpty ? settings.activeAgentName : trimmed

        if let matched = available.first(where: {
            $0.localizedCaseInsensitiveCompare(preferred) == .orderedSame
        }) {
            return matched
        }

        // "도치"는 기본 에이전트로 UI/설정에서 사용할 수 있으므로 목록에 없어도 허용한다.
        if preferred.localizedCaseInsensitiveCompare("도치") == .orderedSame {
            return "도치"
        }
        return nil
    }

    /// 딥링크 처리 (dochi:// URL)
    func handleDeepLink(url: URL) {
        guard let deepLink = SpotlightIndexer.parseDeepLink(url: url) else {
            Log.app.warning("Spotlight: 유효하지 않은 딥링크 — \(url.absoluteString)")
            errorMessage = "유효하지 않은 링크입니다."
            // Auto-dismiss error after 3 seconds
            Task {
                try? await Task.sleep(for: .seconds(3))
                if self.errorMessage == "유효하지 않은 링크입니다." {
                    self.errorMessage = nil
                }
            }
            return
        }

        // Bring app to foreground
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        switch deepLink {
        case .conversation(let id):
            selectConversation(id: id)
            Log.app.info("Spotlight: 대화 딥링크 처리 — \(id)")
        case .memoryUser(let userId):
            // Navigate to memory panel — set notification properties to trigger UI
            notificationShowMemoryPanel = true
            Log.app.info("Spotlight: 사용자 메모리 딥링크 처리 — \(userId)")
        case .memoryAgent(let wsId, let agentName):
            notificationShowMemoryPanel = true
            Log.app.info("Spotlight: 에이전트 메모리 딥링크 처리 — \(wsId)/\(agentName)")
        case .memoryWorkspace(let wsId):
            notificationShowMemoryPanel = true
            Log.app.info("Spotlight: 워크스페이스 메모리 딥링크 처리 — \(wsId)")
        }
    }

    /// 현재 대화를 Spotlight에 인덱싱
    private func indexCurrentConversationIfNeeded() {
        guard let conversation = currentConversation else { return }
        spotlightIndexer?.indexConversation(conversation)
    }

    /// 메모리 저장/수정 시 Spotlight 인크리멘탈 인덱싱 (H-4)
    private func indexMemoryForSpotlight(scope: MemoryToastEvent.Scope, content: String) {
        guard let indexer = spotlightIndexer else { return }

        switch scope {
        case .personal:
            guard let userId = sessionContext.currentUserId else { return }
            let profiles = contextService.loadProfiles()
            let userName = profiles.first(where: { $0.id.uuidString == userId })?.name ?? "사용자"
            indexer.indexMemory(
                scope: "personal",
                identifier: "user-\(userId)",
                title: "\(userName)의 개인 메모리",
                content: content
            )
        case .workspace:
            let wsId = sessionContext.workspaceId
            indexer.indexMemory(
                scope: "workspace",
                identifier: "workspace-\(wsId.uuidString)",
                title: "워크스페이스 메모리",
                content: content
            )
        case .agent:
            let wsId = sessionContext.workspaceId
            let agentName = settings.activeAgentName
            indexer.indexMemory(
                scope: "agent",
                identifier: "agent-\(wsId.uuidString)-\(agentName)",
                title: "\(agentName) 에이전트 메모리",
                content: content
            )
        }
    }

    // MARK: - Local Server Monitoring

    /// Start periodic local server status checking (30s interval) when using a local provider.
    func startLocalServerMonitoringIfNeeded() {
        localServerMonitorTask?.cancel()
        guard settings.currentProvider.isLocal || settings.offlineFallbackEnabled else { return }

        localServerMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkLocalServerStatus()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Check the connection status of the currently relevant local server.
    private func checkLocalServerStatus() async {
        let provider = settings.currentProvider
        guard provider.isLocal else {
            // If offline fallback is enabled, check fallback provider
            if settings.offlineFallbackEnabled,
               let fallbackProvider = LLMProvider(rawValue: settings.offlineFallbackProvider),
               fallbackProvider.isLocal {
                let available = await checkProviderAvailable(fallbackProvider)
                localServerStatus = available ? .connected : .disconnected
            }
            return
        }

        localServerStatus = .checking
        let available = await checkProviderAvailable(provider)
        localServerStatus = available ? .connected : .disconnected

        if !available {
            Log.llm.warning("Local server \(provider.displayName) not available")
        }
    }

    /// Check if a specific local provider's server is available.
    private func checkProviderAvailable(_ provider: LLMProvider) async -> Bool {
        switch provider {
        case .ollama:
            let baseURL = URL(string: settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
            return await OllamaModelFetcher.isAvailable(baseURL: baseURL)
        case .lmStudio:
            let baseURL = URL(string: settings.lmStudioBaseURL) ?? URL(string: "http://localhost:1234")!
            return await LMStudioModelFetcher.isAvailable(baseURL: baseURL)
        default:
            return false
        }
    }

    /// Activate offline fallback: switch to local model and remember original.
    func activateOfflineFallback(provider: LLMProvider, model: String) {
        guard !isOfflineFallbackActive else { return }
        originalProvider = settings.currentProvider
        originalModel = settings.llmModel
        settings.llmProvider = provider.rawValue
        settings.llmModel = model
        isOfflineFallbackActive = true
        Log.app.info("Offline fallback activated: \(provider.displayName)/\(model)")
    }

    /// Restore the original model after offline fallback.
    func restoreOriginalModel() {
        guard isOfflineFallbackActive,
              let provider = originalProvider,
              let model = originalModel else { return }
        settings.llmProvider = provider.rawValue
        settings.llmModel = model
        isOfflineFallbackActive = false
        originalProvider = nil
        originalModel = nil
        Log.app.info("Original model restored: \(provider.displayName)/\(model)")
    }

    /// Restore the original TTS provider after fallback.
    func restoreTTSProvider() {
        if let router = ttsService as? TTSRouter {
            router.restoreTTSProvider()
        }
        isTTSFallbackActive = false
        ttsFallbackProviderName = nil
        Log.app.info("TTS provider restored from fallback")
    }

    // MARK: - State Transitions

    private func transition(to newState: InteractionState) {
        let oldState = interactionState
        guard validateTransition(from: oldState, to: newState) else {
            Log.app.error("Invalid state transition: \(String(describing: oldState)) → \(String(describing: newState))")
            return
        }
        interactionState = newState
        Log.app.info("Interaction: \(String(describing: oldState)) → \(String(describing: newState))")

        if newState != .processing {
            processingSubState = nil
            currentToolName = nil
        }
    }

    private func setSessionState(_ newState: SessionState) {
        let old = sessionState
        sessionState = newState
        Log.app.info("Session: \(String(describing: old)) → \(String(describing: newState))")
    }

    private func validateTransition(from: InteractionState, to: InteractionState) -> Bool {
        // Forbidden combinations
        if to == .listening && interactionState == .speaking { return false }
        if to == .processing && sessionState == .ending { return false }

        switch (from, to) {
        case (.idle, .processing), (.idle, .listening):
            return true
        case (.listening, .processing), (.listening, .idle):
            return true
        case (.processing, .speaking), (.processing, .idle):
            return true
        case (.speaking, .idle), (.speaking, .listening):
            return true
        default:
            return false
        }
    }

    // MARK: - Text Actions

    func sendMessage() {
        recordUserActivity()  // K-2: reset idle timer on send
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !pendingImages.isEmpty
        guard !text.isEmpty || hasImages else { return }
        guard interactionState == .idle else {
            Log.app.warning("Cannot send message: not idle (current: \(String(describing: self.interactionState)))")
            return
        }

        // Budget check: block if monthly budget exceeded
        if metricsCollector.isBudgetExceeded {
            errorMessage = "월 예산을 초과했습니다. 설정 > 사용량에서 예산을 조정하거나 차단을 해제하세요."
            Log.app.warning("LLM request blocked: monthly budget exceeded")
            return
        }

        // Barge-in: if TTS is playing in text mode, stop it
        ttsService.stopAndClear()

        // Check vision support early (before clearing state)
        var shouldProcessImages = false
        if hasImages {
            let provider = settings.currentProvider
            let model = settings.llmModel
            let capabilities = ProviderCapabilityMatrix.capabilities(
                for: provider,
                model: model
            )
            if !capabilities.supportsVision {
                Log.app.warning("Vision not supported by \(model). Images will not be sent.")
                if !visionWarningDismissed {
                    errorMessage = "현재 모델(\(model))은 이미지 입력을 지원하지 않습니다. 텍스트만 전송됩니다."
                }
            } else {
                shouldProcessImages = true
            }
        }

        let finalText = text.isEmpty ? "이미지를 분석해주세요." : text
        let imagesToProcess = shouldProcessImages ? pendingImages : []
        inputText = ""
        pendingImages = []
        visionWarningDismissed = false
        errorMessage = nil

        ensureConversation()

        // K-3: Analyze message for interest discovery
        if !isControlPlaneSecretExecutionActive,
           let conversationId = currentConversation?.id,
           let interestService = interestDiscoveryService {
            let countBefore = interestService.profile.interests.count
            interestService.analyzeMessage(finalText, conversationId: conversationId)
            // Persist if new interest was inferred
            if interestService.profile.interests.count > countBefore,
               let userId = sessionContext.currentUserId {
                interestService.saveProfile(userId: userId)
                interestService.syncToMemory(contextService: contextService, userId: userId)
            }
        }

        if imagesToProcess.isEmpty {
            // No images — send immediately
            appendUserMessage(finalText, imageData: nil)
            markCurrentNativeSessionActive()
            transition(to: .processing)
            processingSubState = .streaming

            // Route through native loop.
            processingTask = Task {
                await processPrimaryLLMPath(
                    input: finalText,
                    includesImages: false,
                    channel: .chat
                )
            }
        } else {
            // Process images off main thread, then send.
            // Native path currently handles image messages as text-first requests.
            transition(to: .processing)
            processingSubState = .streaming
            processingTask = Task {
                let imageContents = await Task.detached { () -> [ImageContent] in
                    var processed: [ImageContent] = []
                    for attachment in imagesToProcess {
                        if let content = ImageProcessor.processForLLM(attachment.image) {
                            processed.append(content)
                        } else {
                            Log.app.warning("Failed to process image: \(attachment.fileName)")
                        }
                    }
                    return processed
                }.value

                if !imageContents.isEmpty {
                    Log.app.info("Attached \(imageContents.count) image(s) to message")
                }
                appendUserMessage(finalText, imageData: imageContents.isEmpty ? nil : imageContents)
                markCurrentNativeSessionActive()
                await processPrimaryLLMPath(
                    input: finalText,
                    includesImages: !imageContents.isEmpty,
                    channel: .chat
                )
            }
        }
    }

    /// Control Plane `chat.send`용 단발 요청.
    /// 기존 `sendMessage()` 플로우를 재사용하고, 완료까지 대기한 뒤 최신 assistant 응답을 반환한다.
    func sendMessageFromControlPlane(
        prompt: String,
        timeoutSeconds: Int = 120,
        executionMode: ControlPlaneExecutionMode = .standard
    ) async throws -> ControlPlaneChatSendResponse {
        try await runControlPlaneChatStream(
            prompt: prompt,
            correlationId: UUID().uuidString,
            timeoutSeconds: timeoutSeconds,
            executionMode: executionMode
        ) { _ in }
    }

    /// Control Plane `chat.stream`용 이벤트 스트림 실행.
    /// partial/tool_call/tool_result/done 이벤트를 순서대로 전달한다.
    func runControlPlaneChatStream(
        prompt: String,
        correlationId: String,
        timeoutSeconds: Int = 120,
        executionMode: ControlPlaneExecutionMode = .standard,
        onEvent: @Sendable @escaping (ControlPlaneStreamEvent) async -> Void
    ) async throws -> ControlPlaneChatSendResponse {
        switch executionMode {
        case .standard:
            return try await runControlPlaneChatStreamCore(
                prompt: prompt,
                correlationId: correlationId,
                timeoutSeconds: timeoutSeconds,
                onEvent: onEvent
            )
        case .secret(let secretOptions):
            return try await runControlPlaneChatStreamSecret(
                prompt: prompt,
                correlationId: correlationId,
                timeoutSeconds: timeoutSeconds,
                secretOptions: secretOptions,
                onEvent: onEvent
            )
        }
    }

    private func runControlPlaneChatStreamSecret(
        prompt: String,
        correlationId: String,
        timeoutSeconds: Int,
        secretOptions: ControlPlaneSecretOptions,
        onEvent: @Sendable @escaping (ControlPlaneStreamEvent) async -> Void
    ) async throws -> ControlPlaneChatSendResponse {
        guard !secretOptions.allowedToolNames.isEmpty else {
            throw ControlPlaneChatSendError.requestFailed("secret 모드는 secret_allowed_tools가 1개 이상 필요합니다.")
        }

        let previousConversation = currentConversation
        let previousStreamingText = streamingText
        let previousErrorMessage = errorMessage
        let previousToolName = currentToolName
        let previousInputText = inputText
        let previousPendingImages = pendingImages
        let previousVisionWarningDismissed = visionWarningDismissed

        activeControlPlaneExecutionMode = .secret(secretOptions)
        currentConversation = Conversation(title: "Secret Smoke Session", userId: sessionContext.currentUserId)
        streamingText = ""
        errorMessage = nil
        currentToolName = nil
        inputText = ""
        pendingImages = []
        visionWarningDismissed = false

        defer {
            activeControlPlaneExecutionMode = .standard
            currentConversation = previousConversation
            streamingText = previousStreamingText
            errorMessage = previousErrorMessage
            currentToolName = previousToolName
            inputText = previousInputText
            pendingImages = previousPendingImages
            visionWarningDismissed = previousVisionWarningDismissed
        }

        do {
            return try await runControlPlaneChatStreamCore(
                prompt: prompt,
                correlationId: correlationId,
                timeoutSeconds: timeoutSeconds,
                onEvent: onEvent
            )
        } catch let error as ControlPlaneChatSendError {
            guard shouldFallbackToDeterministicSecretStream(for: error) else {
                throw error
            }
            Log.runtime.notice("Secret stream deterministic fallback activated: \(error.errorDescription ?? error.localizedDescription)")
            return try await runControlPlaneChatStreamSecretDeterministicMock(
                prompt: prompt,
                correlationId: correlationId,
                secretOptions: secretOptions,
                onEvent: onEvent
            )
        }
    }

    private func runControlPlaneChatStreamCore(
        prompt: String,
        correlationId: String,
        timeoutSeconds: Int,
        onEvent: @Sendable @escaping (ControlPlaneStreamEvent) async -> Void
    ) async throws -> ControlPlaneChatSendResponse {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw ControlPlaneChatSendError.emptyPrompt
        }
        guard interactionState == .idle else {
            throw ControlPlaneChatSendError.interactionBusy
        }

        let timeout = max(5, min(300, timeoutSeconds))
        let beforeMessageCount = currentConversation?.messages.count ?? 0
        var observedMessageCount = beforeMessageCount
        var lastStreamingLength = 0
        var lastToolName: String?

        inputText = trimmedPrompt
        sendMessage()

        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while interactionState != .idle {
            if Date() >= deadline {
                cancelRequest()
                await onEvent(ControlPlaneStreamEvent(
                    kind: .error,
                    text: "[cid:\(correlationId)] timeout",
                    toolName: nil,
                    timestamp: Self.controlPlaneTimestamp()
                ))
                throw ControlPlaneChatSendError.timeout
            }

            if streamingText.count < lastStreamingLength {
                lastStreamingLength = streamingText.count
            } else if streamingText.count > lastStreamingLength {
                let delta = String(streamingText.dropFirst(lastStreamingLength))
                if !delta.isEmpty {
                    await onEvent(ControlPlaneStreamEvent(
                        kind: .partial,
                        text: delta,
                        toolName: nil,
                        timestamp: Self.controlPlaneTimestamp()
                    ))
                }
                lastStreamingLength = streamingText.count
            }

            if currentToolName != lastToolName {
                lastToolName = currentToolName
                if let lastToolName, !lastToolName.isEmpty {
                    await onEvent(ControlPlaneStreamEvent(
                        kind: .toolCall,
                        text: nil,
                        toolName: lastToolName,
                        timestamp: Self.controlPlaneTimestamp()
                    ))
                }
            }

            if let conversation = currentConversation,
               conversation.messages.count > observedMessageCount {
                let newMessages = conversation.messages.dropFirst(observedMessageCount)
                for message in newMessages where message.role == .tool {
                    let inferredToolName = Self.inferToolNameFromToolResult(message.content)
                    let resolvedToolName = lastToolName ?? inferredToolName
                    if let resolvedToolName, resolvedToolName != lastToolName {
                        await onEvent(ControlPlaneStreamEvent(
                            kind: .toolCall,
                            text: nil,
                            toolName: resolvedToolName,
                            timestamp: Self.controlPlaneTimestamp()
                        ))
                        lastToolName = resolvedToolName
                    }
                    await onEvent(ControlPlaneStreamEvent(
                        kind: .toolResult,
                        text: message.content,
                        toolName: resolvedToolName,
                        timestamp: Self.controlPlaneTimestamp()
                    ))
                }
                observedMessageCount = conversation.messages.count
            }

            try? await Task.sleep(for: .milliseconds(150))
        }

        if let conversation = currentConversation,
           conversation.messages.count > observedMessageCount {
            let newMessages = conversation.messages.dropFirst(observedMessageCount)
            for message in newMessages where message.role == .tool {
                let inferredToolName = Self.inferToolNameFromToolResult(message.content)
                let resolvedToolName = lastToolName ?? inferredToolName
                if let resolvedToolName, resolvedToolName != lastToolName {
                    await onEvent(ControlPlaneStreamEvent(
                        kind: .toolCall,
                        text: nil,
                        toolName: resolvedToolName,
                        timestamp: Self.controlPlaneTimestamp()
                    ))
                    lastToolName = resolvedToolName
                }
                await onEvent(ControlPlaneStreamEvent(
                    kind: .toolResult,
                    text: message.content,
                    toolName: resolvedToolName,
                    timestamp: Self.controlPlaneTimestamp()
                ))
            }
            observedMessageCount = conversation.messages.count
        }

        if let errorMessage, !errorMessage.isEmpty {
            await onEvent(ControlPlaneStreamEvent(
                kind: .error,
                text: "[cid:\(correlationId)] \(errorMessage)",
                toolName: nil,
                timestamp: Self.controlPlaneTimestamp()
            ))
            throw ControlPlaneChatSendError.requestFailed(errorMessage)
        }

        guard let conversation = currentConversation else {
            await onEvent(ControlPlaneStreamEvent(
                kind: .error,
                text: "[cid:\(correlationId)] no conversation",
                toolName: nil,
                timestamp: Self.controlPlaneTimestamp()
            ))
            throw ControlPlaneChatSendError.noConversation
        }

        let candidateMessages = Array(conversation.messages.dropFirst(beforeMessageCount))
        guard let assistantMessage = candidateMessages.last(where: { $0.role == .assistant })
            ?? conversation.messages.last(where: { $0.role == .assistant }) else {
            await onEvent(ControlPlaneStreamEvent(
                kind: .error,
                text: "[cid:\(correlationId)] no assistant response",
                toolName: nil,
                timestamp: Self.controlPlaneTimestamp()
            ))
            throw ControlPlaneChatSendError.noAssistantResponse
        }

        await onEvent(ControlPlaneStreamEvent(
            kind: .done,
            text: assistantMessage.content,
            toolName: nil,
            timestamp: Self.controlPlaneTimestamp()
        ))

        return ControlPlaneChatSendResponse(
            conversationId: conversation.id.uuidString,
            assistantMessageId: assistantMessage.id.uuidString,
            assistantMessage: assistantMessage.content,
            messageCount: conversation.messages.count
        )
    }

    nonisolated private static func controlPlaneTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    nonisolated private static func inferToolNameFromToolResult(_ text: String) -> String? {
        let marker = "secret-mock tool '"
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        let suffix = text[markerRange.upperBound...]
        guard let endQuoteIndex = suffix.firstIndex(of: "'") else {
            return nil
        }

        let candidate = suffix[..<endQuoteIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    private func shouldFallbackToDeterministicSecretStream(for error: ControlPlaneChatSendError) -> Bool {
        guard case let .requestFailed(reason) = error else {
            return false
        }

        let normalized = reason.lowercased()
        let indicators = [
            "api 키가 설정되지 않았습니다",
            "api key",
            "model not found",
            "model '",
            "사용 가능한 네이티브 provider가 없습니다",
            "provider가 없습니다",
            "connection refused",
            "네이티브 루프 오류",
        ]
        return indicators.contains { normalized.contains($0.lowercased()) }
    }

    private func runControlPlaneChatStreamSecretDeterministicMock(
        prompt: String,
        correlationId: String,
        secretOptions: ControlPlaneSecretOptions,
        onEvent: @Sendable @escaping (ControlPlaneStreamEvent) async -> Void
    ) async throws -> ControlPlaneChatSendResponse {
        guard let selectedTool = secretOptions.allowedToolNames.first else {
            throw ControlPlaneChatSendError.requestFailed("secret 모드는 secret_allowed_tools가 1개 이상 필요합니다.")
        }

        let now = Date()
        let toolArguments: [String: Any] = selectedTool == "datetime"
            ? ["action": "now"]
            : ["prompt": prompt]
        let argumentsDescription: String
        if JSONSerialization.isValidJSONObject(toolArguments),
           let data = try? JSONSerialization.data(withJSONObject: toolArguments, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            argumentsDescription = text
        } else {
            argumentsDescription = String(describing: toolArguments)
        }

        await onEvent(ControlPlaneStreamEvent(
            kind: .toolCall,
            text: nil,
            toolName: selectedTool,
            timestamp: Self.controlPlaneTimestamp(now)
        ))

        await onEvent(ControlPlaneStreamEvent(
            kind: .toolResult,
            text: "secret-mock tool '\(selectedTool)' executed with arguments: \(argumentsDescription)",
            toolName: selectedTool,
            timestamp: Self.controlPlaneTimestamp(Date())
        ))

        let assistantText = selectedTool == "datetime"
            ? "현재 시각은 \(Self.humanReadableDateTime(now))입니다. (secret-mock llm fallback)"
            : "요청된 도구 '\(selectedTool)' 호출을 완료했습니다. (secret-mock llm fallback)"
        await onEvent(ControlPlaneStreamEvent(
            kind: .done,
            text: assistantText,
            toolName: nil,
            timestamp: Self.controlPlaneTimestamp(Date())
        ))

        let conversationId = currentConversation?.id.uuidString ?? UUID().uuidString
        return ControlPlaneChatSendResponse(
            conversationId: conversationId,
            assistantMessageId: UUID().uuidString,
            assistantMessage: assistantText,
            messageCount: currentConversation?.messages.count ?? 0
        )
    }

    nonisolated private static func humanReadableDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE a h시 m분"
        return formatter.string(from: date)
    }

    // MARK: - Image Attachment Actions (I-3)

    func addImage(_ image: NSImage, fileName: String = "image") {
        guard pendingImages.count < ImageAttachment.maxCount else {
            errorMessage = "이미지는 최대 \(ImageAttachment.maxCount)장까지 첨부할 수 있습니다."
            Log.app.warning("Image attachment limit reached (\(ImageAttachment.maxCount))")
            return
        }

        if let attachment = ImageProcessor.createAttachment(from: image, fileName: fileName) {
            pendingImages.append(attachment)
            Log.app.info("Image attached: \(fileName) (\(attachment.data.count) bytes)")
        } else {
            errorMessage = "이미지를 처리할 수 없습니다. 지원되는 형식인지 확인하세요."
            Log.app.warning("Failed to create image attachment: \(fileName)")
        }
    }

    func addImageFromData(_ data: Data, fileName: String = "image") {
        guard pendingImages.count < ImageAttachment.maxCount else {
            errorMessage = "이미지는 최대 \(ImageAttachment.maxCount)장까지 첨부할 수 있습니다."
            return
        }

        let ext = (fileName as NSString).pathExtension
        let mimeType = ImageProcessor.mimeType(for: ext)

        if let attachment = ImageProcessor.createAttachment(from: data, mimeType: mimeType, fileName: fileName) {
            pendingImages.append(attachment)
            Log.app.info("Image attached from data: \(fileName) (\(data.count) bytes)")
        } else {
            errorMessage = "이미지를 처리할 수 없습니다."
            Log.app.warning("Failed to create image attachment from data: \(fileName)")
        }
    }

    func removeImage(id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }

    func clearPendingImages() {
        pendingImages = []
        visionWarningDismissed = false
    }

    /// Whether the current model supports Vision input.
    var currentModelSupportsVision: Bool {
        settings.currentProvider.supportsVision(model: settings.llmModel)
    }

    func cancelRequest() {
        processingTask?.cancel()
        processingTask = nil
        ttsService.stopAndClear()
        sentenceChunker = SentenceChunker()
        markCurrentNativeSessionInterrupted()
        nativeAgentLoopService.runStopHooks()

        // Preserve partial streaming text as assistant message
        if !streamingText.isEmpty {
            appendAssistantMessage(streamingText)
            streamingText = ""
        }

        processingSubState = nil
        currentToolName = nil
        transition(to: .idle)
        Log.app.info("Request cancelled by user")
    }

    private enum NativeLoopAttemptResult {
        case success
        case failure(reason: String)
        case cancelled
    }

    private func processPrimaryLLMPath(
        input: String,
        includesImages: Bool,
        channel: ModelRoutingChannel
    ) async {
        guard !Task.isCancelled else { return }
        guard settings.nativeAgentLoopEnabled else {
            errorMessage = "네이티브 에이전트 루프가 비활성화되어 있습니다."
            processingSubState = nil
            currentToolName = nil
            transition(to: .idle)
            return
        }

        if includesImages {
            Log.runtime.debug("Native loop will process image message as text-first request")
        }

        let decision = await modelRouterV2.decide(input: ModelRoutingInput(
            userInput: input,
            channel: channel,
            includesImages: includesImages
        ))
        Log.runtime.info("ModelRouterV2 decision: \(decision.summary)")

        let targets = decision.orderedReadyTargets
        guard !targets.isEmpty else {
            errorMessage = "사용 가능한 네이티브 provider가 없습니다. API 키/로컬 서버 상태를 확인해주세요."
            processingSubState = nil
            currentToolName = nil
            transition(to: .idle)
            return
        }

        var lastFailureReason: String?

        for (index, target) in targets.enumerated() {
            guard !Task.isCancelled else { return }

            if index > 0 {
                processingSubState = .streaming
                Log.runtime.warning(
                    "ModelRouterV2 fallback attempt \(index + 1)/\(targets.count): \(target.provider.rawValue)/\(target.model)"
                )
            }

            let result = await processNativeAgentLoop(
                input: input,
                provider: target.provider,
                model: target.model,
                wasFallback: index > 0
            )

            switch result {
            case .success:
                modelRouterV2.recordAttempt(provider: target.provider, success: true)
                errorMessage = nil
                processingSubState = nil
                currentToolName = nil
                transition(to: .idle)
                return
            case .failure(let reason):
                modelRouterV2.recordAttempt(provider: target.provider, success: false)
                lastFailureReason = reason
                streamingText = ""
                processingSubState = .streaming
                currentToolName = nil
            case .cancelled:
                errorMessage = nil
                streamingText = ""
                processingSubState = nil
                currentToolName = nil
                transition(to: .idle)
                return
            }
        }

        guard !Task.isCancelled else { return }
        errorMessage = "네이티브 루프 오류: \(lastFailureReason ?? "사용 가능한 provider가 없습니다.")"
        processingSubState = nil
        currentToolName = nil
        transition(to: .idle)
    }

    private func processNativeAgentLoop(
        input _: String,
        provider: LLMProvider,
        model: String,
        wasFallback: Bool
    ) async -> NativeLoopAttemptResult {
        var fallbackReason: String?
        var cancelled = false
        let startedAt = Date()
        var firstPartialLatency: TimeInterval?
        var doneInputTokens: Int?
        var doneOutputTokens: Int?
        var didReceiveDoneEvent = false
        var estimatedInputTokensForLatestRequest: Int?

        do {
            let request = try buildNativeLLMRequestFromConversation(
                provider: provider,
                model: model
            )
            let toolRefreshContext = makeNativeToolRefreshContext(
                provider: request.provider,
                model: request.model,
                conversation: currentConversation
            )
            estimatedInputTokensForLatestRequest = contextCompactionService.estimateRequestInputTokens(
                systemPrompt: request.systemPrompt,
                messages: request.messages,
                tools: request.tools,
                provider: provider,
                model: model
            )
            let nativeHookContext = NativeAgentLoopHookContext(
                sessionId: currentConversation?.id.uuidString ?? UUID().uuidString,
                workspaceId: sessionContext.workspaceId.uuidString,
                agentId: settings.activeAgentName,
                allowMemoryMutation: !isControlPlaneSecretExecutionActive,
                toolExecutionMode: {
                    if let secret = activeControlPlaneSecretOptions {
                        return .mock(allowedToolNames: secret.allowedToolNames)
                    }
                    return .live
                }()
            )

            streamingText = ""
            var accumulatedText = ""

            eventLoop: for try await event in nativeAgentLoopService.run(
                request: request,
                hookContext: nativeHookContext,
                toolRefreshContext: toolRefreshContext
            ) {
                guard !Task.isCancelled else { break }

                switch event.kind {
                case .partial:
                    processingSubState = .streaming
                    if let delta = event.text {
                        if firstPartialLatency == nil, !delta.isEmpty {
                            firstPartialLatency = Date().timeIntervalSince(startedAt)
                        }
                        accumulatedText += delta
                        streamingText = accumulatedText
                    }

                case .toolUse:
                    processingSubState = .toolCalling
                    currentToolName = event.toolName

                case .toolResult:
                    processingSubState = .streaming
                    currentToolName = nil

                    let toolResult = ToolResult(
                        toolCallId: event.toolCallId ?? "",
                        content: event.toolResultText ?? "",
                        isError: event.isToolResultError ?? false
                    )
                    appendToolResultMessage(toolResult)

                case .done:
                    didReceiveDoneEvent = true
                    doneInputTokens = event.inputTokens
                    doneOutputTokens = event.outputTokens
                    let finalText = event.text ?? accumulatedText
                    let totalLatency = Date().timeIntervalSince(startedAt)
                    let metadata = buildNativeMessageMetadata(
                        provider: provider,
                        model: model,
                        inputTokens: doneInputTokens,
                        outputTokens: doneOutputTokens,
                        totalLatency: totalLatency,
                        wasFallback: wasFallback
                    )
                    if !finalText.isEmpty {
                        appendAssistantMessage(finalText, metadata: metadata)
                    }
                    streamingText = ""
                    processingSubState = .complete
                    saveConversation()

                case .error:
                    let nativeError = event.error ?? NativeLLMError(
                        code: .unknown,
                        message: "Native loop error event without payload",
                        statusCode: nil,
                        retryAfterSeconds: nil
                    )
                    if nativeError.code == .cancelled {
                        cancelled = true
                        Log.runtime.info("Native loop cancelled by provider event")
                    } else {
                        fallbackReason = nativeError.message
                        Log.runtime.warning("Native loop emitted error event: \(nativeError.message)")
                    }
                    break eventLoop
                }
            }
        } catch let error as NativeLLMError {
            if error.code == .cancelled {
                Log.runtime.info("Native loop cancelled")
                cancelled = true
            } else {
                fallbackReason = error.message
                Log.runtime.error("Native loop failed: \(error.message)")
            }
        } catch {
            fallbackReason = error.localizedDescription
            Log.runtime.error("Native loop failed: \(error.localizedDescription)")
        }

        if cancelled {
            streamingText = ""
            return .cancelled
        }

        if let fallbackReason {
            streamingText = ""
            return .failure(reason: fallbackReason)
        }

        // Clean up
        let totalLatency = Date().timeIntervalSince(startedAt)
        if !didReceiveDoneEvent, !streamingText.isEmpty {
            let metadata = buildNativeMessageMetadata(
                provider: provider,
                model: model,
                inputTokens: doneInputTokens,
                outputTokens: doneOutputTokens,
                totalLatency: totalLatency,
                wasFallback: wasFallback
            )
            appendAssistantMessage(streamingText, metadata: metadata)
            streamingText = ""
        }

        if doneInputTokens == nil && doneOutputTokens == nil {
            Log.runtime.debug("Native loop usage unavailable for \(provider.rawValue)/\(model); recording nil token metrics")
        }

        if let estimatedInputTokens = estimatedInputTokensForLatestRequest,
           let actualInputTokens = doneInputTokens {
            metricsCollector.recordTokenEstimationDeviation(
                provider: provider.rawValue,
                model: model,
                estimatedInputTokens: estimatedInputTokens,
                actualInputTokens: actualInputTokens
            )
            contextCompactionService.recordObservedInputTokens(
                provider: provider,
                model: model,
                estimatedInputTokens: estimatedInputTokens,
                actualInputTokens: actualInputTokens
            )
        }

        recordNativeExchangeMetrics(
            provider: provider,
            model: model,
            inputTokens: doneInputTokens,
            outputTokens: doneOutputTokens,
            firstByteLatency: firstPartialLatency,
            totalLatency: totalLatency,
            wasFallback: wasFallback
        )
        return .success
    }

    func newConversation() {
        recordUserActivity()

        // I-2: 이전 대화에 대해 메모리 자동 정리 트리거
        triggerMemoryConsolidation(for: currentConversation)

        currentConversation = nil
        streamingText = ""
        errorMessage = nil
        toolService.resetRegistry()
    }

    func loadConversations() {
        conversations = conversationService.list()
        Log.app.debug("Loaded \(self.conversations.count) conversations")
    }

    func restoreNativeSessionIfNeeded() {
        guard currentConversation == nil else { return }
        guard let userId = normalizedUserId(sessionContext.currentUserId) else {
            Log.app.debug("Skipping native session restore: current user is not set")
            return
        }
        let records = nativeSessionStore.latestRecords(
            workspaceId: sessionContext.workspaceId,
            agentId: settings.activeAgentName,
            userId: userId
        )

        for record in records {
            guard let conversationId = UUID(uuidString: record.conversationId) else {
                continue
            }

            guard let conversation = conversationService.load(id: conversationId) else {
                nativeSessionStore.remove(
                    workspaceId: sessionContext.workspaceId,
                    agentId: settings.activeAgentName,
                    conversationId: conversationId
                )
                continue
            }

            guard normalizedUserId(conversation.userId) == userId else {
                continue
            }

            currentConversation = conversation
            if record.status == .interrupted {
                _ = nativeSessionStore.recoverIfInterrupted(
                    workspaceId: sessionContext.workspaceId,
                    agentId: settings.activeAgentName,
                    conversationId: conversation.id,
                    userId: userId
                )
            }
            Log.app.info("Restored native session conversation: \(conversation.id)")
            return
        }
    }

    func selectConversation(id: UUID) {
        guard interactionState == .idle else { return }
        recordUserActivity()

        // I-2: 이전 대화에 대해 메모리 자동 정리 트리거
        triggerMemoryConsolidation(for: currentConversation)

        if let conversation = conversationService.load(id: id) {
            currentConversation = conversation
            streamingText = ""
            errorMessage = nil
            toolService.resetRegistry()
            markCurrentNativeSessionActive()
            Log.app.info("Selected conversation: \(id)")
        }
    }

    /// 대화 목록에서 인덱스(1-based)로 대화 선택 (⌘1~9)
    func selectConversationByIndex(_ index: Int) {
        let zeroIndex = index - 1
        guard zeroIndex >= 0 && zeroIndex < conversations.count else {
            Log.app.debug("Conversation index \(index) out of range (count: \(self.conversations.count))")
            return
        }
        selectConversation(id: conversations[zeroIndex].id)
    }

    // MARK: - Workspace / Agent Switching

    func switchWorkspace(id: UUID) {
        guard interactionState == .idle else { return }
        recordUserActivity()

        saveConversation()
        settings.currentWorkspaceId = id.uuidString
        sessionContext.workspaceId = id
        toolService.resetRegistry()

        // Select first agent in the new workspace, or keep default
        let agents = contextService.listAgents(workspaceId: id)
        if let first = agents.first {
            settings.activeAgentName = first
        } else {
            settings.activeAgentName = "도치"
        }

        newConversation()
        loadConversations()
        Log.app.info("Switched workspace to \(id)")
    }

    func switchUser(profile: UserProfile) {
        recordUserActivity()
        sessionContext.currentUserId = profile.id.uuidString
        settings.defaultUserId = profile.id.uuidString
        currentUserName = profile.name
        // K-3: Reload interest profile for the new user
        interestDiscoveryService?.loadProfile(userId: profile.id.uuidString)
        Log.app.info("Switched user to: \(profile.name)")
    }

    func reloadProfiles() {
        userProfiles = contextService.loadProfiles()
        if let userId = sessionContext.currentUserId,
           let profile = userProfiles.first(where: { $0.id.uuidString == userId }) {
            currentUserName = profile.name
        } else {
            currentUserName = "(사용자 없음)"
        }
    }

    func switchAgent(name: String) {
        guard interactionState == .idle else { return }
        recordUserActivity()

        saveConversation()
        settings.activeAgentName = name
        toolService.resetRegistry()
        newConversation()
        Log.app.info("Switched agent to \(name)")
    }

    func deleteAgent(name: String) {
        let wsId = sessionContext.workspaceId
        contextService.deleteAgent(workspaceId: wsId, name: name)

        // If deleted agent was active, switch to another
        if settings.activeAgentName == name {
            let remaining = contextService.listAgents(workspaceId: wsId)
            let newAgent = remaining.first ?? "도치"
            settings.activeAgentName = newAgent
            toolService.resetRegistry()
            newConversation()
        }

        Log.app.info("Deleted agent: \(name)")
    }

    func deleteConversation(id: UUID) {
        conversationService.delete(id: id)
        nativeSessionStore.remove(
            workspaceId: sessionContext.workspaceId,
            agentId: settings.activeAgentName,
            conversationId: id
        )
        spotlightIndexer?.removeConversation(id: id)
        if currentConversation?.id == id {
            currentConversation = nil
            streamingText = ""
        }
        loadConversations()
        Log.app.info("Deleted conversation: \(id)")
    }

    func renameConversation(id: UUID, title: String) {
        guard var conversation = conversationService.load(id: id) else { return }
        if title.isEmpty {
            // Auto-generate from first user message
            let firstUserMessage = conversation.messages.first { $0.role == .user }
            conversation.title = String((firstUserMessage?.content ?? "대화").prefix(40))
        } else {
            conversation.title = title
        }
        conversationService.save(conversation: conversation)
        if currentConversation?.id == id {
            currentConversation = conversation
        }
        loadConversations()
    }

    // MARK: - Conversation Organization

    func loadOrganizationData() {
        conversationTags = contextService.loadTags()
        conversationFolders = contextService.loadFolders()
        Log.app.debug("Loaded \(self.conversationTags.count) tags, \(self.conversationFolders.count) folders")
    }

    // Favorites

    func toggleFavorite(id: UUID) {
        guard var conversation = conversationService.load(id: id) else { return }
        conversation.isFavorite.toggle()
        conversationService.save(conversation: conversation)
        if currentConversation?.id == id {
            currentConversation?.isFavorite = conversation.isFavorite
        }
        loadConversations()
        Log.app.info("Toggled favorite for \(id): \(conversation.isFavorite)")
    }

    // Tags

    func addTag(_ tag: ConversationTag) {
        conversationTags.append(tag)
        contextService.saveTags(conversationTags)
        Log.app.info("Added tag: \(tag.name)")
    }

    func deleteTag(id: UUID) {
        let tagName = conversationTags.first(where: { $0.id == id })?.name
        conversationTags.removeAll { $0.id == id }
        contextService.saveTags(conversationTags)

        // Remove tag from all conversations that have it
        if let name = tagName {
            for conversation in conversations where conversation.tags.contains(name) {
                var updated = conversation
                updated.tags.removeAll { $0 == name }
                conversationService.save(conversation: updated)
            }
            loadConversations()
        }
        Log.app.info("Deleted tag: \(tagName ?? "unknown")")
    }

    func updateTag(_ tag: ConversationTag) {
        guard let index = conversationTags.firstIndex(where: { $0.id == tag.id }) else { return }
        let oldName = conversationTags[index].name
        conversationTags[index] = tag
        contextService.saveTags(conversationTags)

        // If name changed, update all conversations
        if oldName != tag.name {
            for conversation in conversations where conversation.tags.contains(oldName) {
                var updated = conversation
                updated.tags.removeAll { $0 == oldName }
                updated.tags.append(tag.name)
                conversationService.save(conversation: updated)
            }
            loadConversations()
        }
        Log.app.info("Updated tag: \(tag.name)")
    }

    func toggleTagOnConversation(conversationId: UUID, tagName: String) {
        guard var conversation = conversationService.load(id: conversationId) else { return }
        if conversation.tags.contains(tagName) {
            conversation.tags.removeAll { $0 == tagName }
        } else {
            conversation.tags.append(tagName)
        }
        conversationService.save(conversation: conversation)
        if currentConversation?.id == conversationId {
            currentConversation?.tags = conversation.tags
        }
        loadConversations()
        Log.app.info("Toggled tag '\(tagName)' on conversation \(conversationId)")
    }

    // Folders

    func addFolder(_ folder: ConversationFolder) {
        var newFolder = folder
        newFolder.sortOrder = conversationFolders.count
        conversationFolders.append(newFolder)
        contextService.saveFolders(conversationFolders)
        Log.app.info("Added folder: \(folder.name)")
    }

    func deleteFolder(id: UUID) {
        let folderName = conversationFolders.first(where: { $0.id == id })?.name
        conversationFolders.removeAll { $0.id == id }
        contextService.saveFolders(conversationFolders)

        // Unassign conversations from deleted folder
        for conversation in conversations where conversation.folderId == id {
            var updated = conversation
            updated.folderId = nil
            conversationService.save(conversation: updated)
        }
        loadConversations()
        Log.app.info("Deleted folder: \(folderName ?? "unknown")")
    }

    func renameFolder(id: UUID, name: String) {
        guard let index = conversationFolders.firstIndex(where: { $0.id == id }) else { return }
        conversationFolders[index].name = name
        contextService.saveFolders(conversationFolders)
        Log.app.info("Renamed folder to: \(name)")
    }

    func moveConversationToFolder(conversationId: UUID, folderId: UUID?) {
        guard var conversation = conversationService.load(id: conversationId) else { return }
        conversation.folderId = folderId
        conversationService.save(conversation: conversation)
        if currentConversation?.id == conversationId {
            currentConversation?.folderId = folderId
        }
        loadConversations()
        Log.app.info("Moved conversation \(conversationId) to folder \(folderId?.uuidString ?? "none")")
    }

    // Filter

    func toggleFavoritesFilter() {
        conversationFilter.showFavoritesOnly.toggle()
        Log.app.info("Favorites filter toggled: \(self.conversationFilter.showFavoritesOnly)")
    }

    func resetFilter() {
        conversationFilter.reset()
        Log.app.info("Conversation filter reset")
    }

    // Multi-select

    func toggleMultiSelectMode() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedConversationIds.removeAll()
        }
        Log.app.info("Multi-select mode: \(self.isMultiSelectMode)")
    }

    func toggleConversationSelection(id: UUID) {
        if selectedConversationIds.contains(id) {
            selectedConversationIds.remove(id)
        } else {
            selectedConversationIds.insert(id)
        }
    }

    func selectAllConversations() {
        selectedConversationIds = Set(conversations.map(\.id))
    }

    func deselectAllConversations() {
        selectedConversationIds.removeAll()
    }

    // Bulk actions

    func bulkDelete() {
        for id in selectedConversationIds {
            conversationService.delete(id: id)
            if currentConversation?.id == id {
                currentConversation = nil
                streamingText = ""
            }
        }
        let count = selectedConversationIds.count
        selectedConversationIds.removeAll()
        isMultiSelectMode = false
        loadConversations()
        Log.app.info("Bulk deleted \(count) conversations")
    }

    func bulkMoveToFolder(folderId: UUID?) {
        for id in selectedConversationIds {
            guard var conversation = conversationService.load(id: id) else { continue }
            conversation.folderId = folderId
            conversationService.save(conversation: conversation)
            if currentConversation?.id == id {
                currentConversation?.folderId = folderId
            }
        }
        loadConversations()
        Log.app.info("Bulk moved \(self.selectedConversationIds.count) conversations to folder \(folderId?.uuidString ?? "none")")
    }

    func bulkSetFavorite(_ isFavorite: Bool) {
        for id in selectedConversationIds {
            guard var conversation = conversationService.load(id: id) else { continue }
            conversation.isFavorite = isFavorite
            conversationService.save(conversation: conversation)
            if currentConversation?.id == id {
                currentConversation?.isFavorite = isFavorite
            }
        }
        loadConversations()
        Log.app.info("Bulk set favorite=\(isFavorite) for \(self.selectedConversationIds.count) conversations")
    }

    func bulkAddTag(tagName: String) {
        for id in selectedConversationIds {
            guard var conversation = conversationService.load(id: id) else { continue }
            if !conversation.tags.contains(tagName) {
                conversation.tags.append(tagName)
                conversationService.save(conversation: conversation)
                if currentConversation?.id == id {
                    currentConversation?.tags = conversation.tags
                }
            }
        }
        loadConversations()
        Log.app.info("Bulk added tag '\(tagName)' to \(self.selectedConversationIds.count) conversations")
    }

    // MARK: - Tool Execution (UX-7)

    /// Toggle all tool cards collapsed/expanded state.
    func toggleAllToolCards() {
        allToolCardsCollapsed.toggle()
        Log.app.info("Tool cards all \(self.allToolCardsCollapsed ? "collapsed" : "expanded")")
    }

    // MARK: - Memory Toast (UX-8)

    func showMemoryToast(scope: MemoryToastEvent.Scope, action: MemoryToastEvent.Action, contentPreview: String) {
        let event = MemoryToastEvent(scope: scope, action: action, contentPreview: contentPreview)
        memoryToastEvents.append(event)
        Log.app.info("Memory toast: \(scope.rawValue) \(action.rawValue)")
    }

    func dismissMemoryToast(id: UUID) {
        memoryToastEvents.removeAll { $0.id == id }
    }

    // MARK: - Memory Consolidation (I-2)

    /// 대화 전환/종료 시 메모리 자동 정리 트리거 (fire-and-forget)
    private func triggerMemoryConsolidation(for conversation: Conversation?) {
        guard let conversation,
              let consolidator = memoryConsolidator,
              conversation.id != lastConsolidatedConversationId else { return }

        lastConsolidatedConversationId = conversation.id

        Task { [weak self] in
            guard let self else { return }
            await consolidator.consolidate(
                conversation: conversation,
                sessionContext: self.sessionContext,
                settings: self.settings
            )
        }
    }

    /// 수동 메모리 정리 실행 (커맨드 팔레트에서 호출)
    func manualConsolidateMemory() {
        guard let conversation = currentConversation else { return }
        guard let consolidator = memoryConsolidator else { return }

        // 수동 실행 시에는 이전 정리 ID를 무시
        Task { [weak self] in
            guard let self else { return }
            await consolidator.consolidate(
                conversation: conversation,
                sessionContext: self.sessionContext,
                settings: self.settings
            )
        }
    }

    /// 메모리 정리 배너 닫기
    func dismissConsolidationBanner() {
        memoryConsolidator?.dismissBanner()
    }

    /// 현재 컨텍스트에서 MemoryContextInfo 생성
    func buildMemoryContextInfo() -> MemoryContextInfo {
        let wsId = sessionContext.workspaceId
        let agentName = settings.activeAgentName

        let systemPrompt = contextService.loadBaseSystemPrompt() ?? ""
        let persona = contextService.loadAgentPersona(workspaceId: wsId, agentName: agentName) ?? ""
        let wsMem = contextService.loadWorkspaceMemory(workspaceId: wsId) ?? ""
        let agentMem = contextService.loadAgentMemory(workspaceId: wsId, agentName: agentName) ?? ""
        let personalMem: String
        if let userId = sessionContext.currentUserId {
            personalMem = contextService.loadUserMemory(userId: userId) ?? ""
        } else {
            personalMem = ""
        }

        return MemoryContextInfo(
            systemPromptLength: systemPrompt.count,
            agentPersonaLength: persona.count,
            workspaceMemoryLength: wsMem.count,
            agentMemoryLength: agentMem.count,
            personalMemoryLength: personalMem.count
        )
    }

    // MARK: - Voice Actions

    /// Start listening via STT (triggered by wake word or UI button).
    func startListening() {
        recordUserActivity()

        guard interactionState == .idle else {
            Log.app.warning("Cannot start listening: not idle")
            return
        }

        guard speechService.isAuthorized else {
            Task {
                let granted = await speechService.requestAuthorization()
                if granted {
                    startListening()
                } else {
                    errorMessage = "마이크 및 음성 인식 권한이 필요합니다. 시스템 설정에서 허용해주세요."
                }
            }
            return
        }

        partialTranscript = ""
        errorMessage = nil

        if sessionState == .inactive {
            setSessionState(.active)
            soundService.playWakeWordDetected()
        }

        ensureConversation()
        transition(to: .listening)

        speechService.startListening(
            silenceTimeout: settings.sttSilenceTimeout,
            onPartialResult: { [weak self] text in
                self?.partialTranscript = text
            },
            onFinalResult: { [weak self] text in
                self?.handleSpeechFinalResult(text)
            },
            onError: { [weak self] error in
                self?.handleSpeechError(error)
            }
        )
    }

    /// Stop listening manually.
    func stopListening() {
        speechService.stopListening()
        partialTranscript = ""
        if interactionState == .listening {
            transition(to: .idle)
        }
    }

    /// Handle barge-in: user speaks or types while TTS is playing.
    func handleBargeIn() {
        guard interactionState == .speaking else { return }

        ttsService.stopAndClear()
        transition(to: .idle)
        Log.app.info("Barge-in: TTS stopped")

        // If in voice mode, start listening for new input
        if isVoiceMode {
            startListening()
        }
    }

    // MARK: - Tool Confirmation

    /// Show confirmation UI for a sensitive tool and wait for user response.
    private func requestToolConfirmation(toolName: String, toolDescription: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            self.pendingToolConfirmation = ToolConfirmation(
                toolName: toolName,
                toolDescription: toolDescription,
                continuation: continuation
            )

            // Safety-net timeout — banner UI handles the primary countdown + timeout
            // message display (~32s total). This fires only if the banner somehow
            // fails to call onDeny (e.g., view removed from hierarchy).
            self.confirmationTimeoutTask?.cancel()
            self.confirmationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.toolConfirmationTimeout + 5))
                guard !Task.isCancelled else { return }
                if self?.pendingToolConfirmation?.toolName == toolName {
                    Log.tool.warning("Tool confirmation safety-net timeout: \(toolName)")
                    self?.respondToToolConfirmation(approved: false)
                }
            }
        }
    }

    /// Called by UI when user approves or denies a sensitive tool.
    func respondToToolConfirmation(approved: Bool) {
        guard let confirmation = pendingToolConfirmation else { return }
        confirmationTimeoutTask?.cancel()
        confirmationTimeoutTask = nil
        pendingToolConfirmation = nil
        confirmation.continuation.resume(returning: approved)
        Log.tool.info("Tool confirmation \(approved ? "approved" : "denied"): \(confirmation.toolName)")
    }

    /// End the voice session manually.
    func endVoiceSession() {
        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = nil
        speechService.stopListening()
        ttsService.stopAndClear()
        partialTranscript = ""

        if interactionState != .idle {
            // Force to idle
            interactionState = .idle
            processingSubState = nil
            currentToolName = nil
        }

        setSessionState(.inactive)
        saveConversation()
        newConversation()
        Log.app.info("Voice session ended")
    }

    /// Load TTS engine for voice mode.
    func prepareTTSEngine() {
        Task {
            do {
                try await ttsService.loadEngine()
                Log.tts.info("TTS engine loaded")
            } catch {
                Log.tts.error("TTS engine load failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Speech Callbacks

    private func handleSpeechFinalResult(_ text: String) {
        partialTranscript = ""

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.stt.debug("Empty STT result")
            transition(to: .idle)
            if sessionState == .active {
                // Keep listening silently in active voice session.
                startListening()
                return
            }
            return
        }

        soundService.playInputComplete()

        // Check for session end commands
        if isSessionEndCommand(trimmed) {
            beginSessionEnding()
            return
        }

        // Check for wake word + agent routing
        handleWakeWordRouting(in: trimmed)

        // Strip wake word prefix from text if present
        let cleanedText = stripWakeWord(from: trimmed)
        guard !cleanedText.isEmpty else {
            // Only wake word was spoken, start listening again
            if sessionState == .active {
                startListening()
            } else {
                transition(to: .idle)
            }
            return
        }

        // Budget check: block if monthly budget exceeded
        if metricsCollector.isBudgetExceeded {
            errorMessage = "월 예산을 초과했습니다. 설정 > 사용량에서 예산을 조정하거나 차단을 해제하세요."
            Log.app.warning("LLM request blocked (voice): monthly budget exceeded")
            transition(to: .idle)
            return
        }

        ensureConversation()
        appendUserMessage(cleanedText)
        markCurrentNativeSessionActive()

        transition(to: .processing)
        processingSubState = .streaming

        processingTask = Task {
            await processPrimaryLLMPath(
                input: cleanedText,
                includesImages: false,
                channel: .voice
            )
        }
    }

    private func handleSpeechError(_ error: Error) {
        partialTranscript = ""
        Log.stt.error("Speech error: \(error.localizedDescription)")
        errorMessage = "음성 입력 실패: \(error.localizedDescription)"

        if interactionState == .listening {
            transition(to: .idle)
        }

        let shouldRetry: Bool
        if let speechError = error as? SpeechServiceError {
            switch speechError {
            case .audioEngineFailure, .recognizerUnavailable, .noInputDevice, .noSpeechDetected:
                shouldRetry = false
            case .recognitionFailed:
                shouldRetry = true
            }
        } else {
            shouldRetry = true
        }

        if sessionState == .active && shouldRetry {
            // Stay in session, try again
            startListening()
        }
    }

    // MARK: - TTS Integration

    private func handleTTSComplete() {
        guard interactionState == .speaking else { return }


        if sessionState == .active {
            // Continuous conversation: speaking → idle → listening
            transition(to: .idle)
            startListening()
        } else if sessionState == .ending {
            // Wait for response to "종료할까요?"
            transition(to: .idle)
            startListening()
        } else {
            // Text mode or inactive session: speaking → idle
            transition(to: .idle)
        }
    }

    private func enqueueTTS(_ text: String) {
        guard isVoiceMode else { return }

        if interactionState == .idle || interactionState == .processing {
            // For standalone TTS (e.g., empty STT retry), transition through processing → speaking
            if interactionState == .idle {
                transition(to: .processing)
            }
            processingSubState = .complete
            transition(to: .speaking)
        }

        ttsService.enqueueSentence(text)
    }

    // MARK: - Session Management

    private func isSessionEndCommand(_ text: String) -> Bool {
        let endPhrases = ["대화 종료", "그만할게", "그만 할게", "끝낼게", "종료"]
        return endPhrases.contains(where: { text.contains($0) })
    }

    private func beginSessionEnding() {
        setSessionState(.ending)
        enqueueTTS("대화를 종료할까요?")

        // Start ending timeout
        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(Self.sessionEndingTimeout))
            guard !Task.isCancelled else { return }
            // No response after timeout → end session
            endVoiceSession()
        }
    }

    // MARK: - Wake Word

    private func handleWakeWordRouting(in text: String) {
        let wsId = sessionContext.workspaceId
        let agents = contextService.listAgents(workspaceId: wsId)

        for agentName in agents {
            guard let config = contextService.loadAgentConfig(workspaceId: wsId, agentName: agentName),
                  let wakeWord = config.wakeWord else { continue }

            if JamoMatcher.isMatch(transcript: text, wakeWord: wakeWord) {
                if agentName != self.settings.activeAgentName {
                    Log.app.info("Agent switch via wake word: \(self.settings.activeAgentName) → \(agentName)")
                    settings.activeAgentName = agentName
                    toolService.resetRegistry()
                    // Start new conversation for new agent
                    saveConversation()
                    newConversation()
                    ensureConversation()
                }
                return
            }
        }

        // Check app-level wake word
        if settings.wakeWordEnabled {
            let appWakeWord = settings.wakeWord
            if JamoMatcher.isMatch(transcript: text, wakeWord: appWakeWord) {
                // Default agent, no switch needed
                return
            }
        }
    }

    private func stripWakeWord(from text: String) -> String {
        // Simple prefix stripping: remove wake word from start of text
        let wakeWord = settings.wakeWord
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try removing the wake word from the beginning
        if stripped.hasPrefix(wakeWord) {
            let remaining = String(stripped.dropFirst(wakeWord.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Also try comma/space after wake word
            if remaining.hasPrefix(",") || remaining.hasPrefix("，") {
                return String(remaining.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return remaining
        }

        return stripped
    }

    // MARK: - Proactive Message Injection

    /// Inject a proactive message from the heartbeat service into the current conversation.
    func injectProactiveMessage(_ message: String) {
        guard var conversation = currentConversation else { return }
        let systemMessage = Message(role: .assistant, content: message)
        conversation.messages.append(systemMessage)
        conversation.updatedAt = Date()
        currentConversation = conversation
        conversationService.save(conversation: conversation)
        Log.app.info("Injected proactive message into conversation")
    }

    // MARK: - Notification Reply Handling (H-3)

    /// Handle user reply from a notification action.
    /// Injects the original notification as assistant context and the user's reply, then sends to LLM.
    /// If no current conversation exists, one is created first to preserve the notification context.
    func handleNotificationReply(text: String, category: String, originalBody: String) {
        Log.app.info("Notification reply from category \(category): \(text)")

        // Ensure a conversation exists so the notification context is not lost
        ensureConversation()

        // Inject original notification body as assistant context
        injectProactiveMessage("[알림] \(originalBody)")

        // Set user input and send
        inputText = text
        sendMessage()
    }

    /// Handle "Open App" action from a notification.
    /// Activates the app and navigates based on notification category.
    func handleNotificationOpenApp(category: String) {
        Log.app.info("Notification open app for category: \(category)")

        // Bring app to foreground
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        // Navigate based on category by setting observable properties
        // ContentView observes these and performs the actual UI navigation.
        switch category {
        case NotificationManager.Category.calendar.rawValue:
            notificationRequestedSection = "chat"
            Log.app.info("Notification: navigating to conversation for calendar")
        case NotificationManager.Category.kanban.rawValue:
            notificationRequestedSection = "kanban"
            Log.app.info("Notification: navigating to kanban")
        case NotificationManager.Category.reminder.rawValue:
            notificationRequestedSection = "chat"
            Log.app.info("Notification: navigating to conversation for reminders")
        case NotificationManager.Category.memory.rawValue:
            notificationRequestedSection = "chat"
            notificationShowMemoryPanel = true
            Log.app.info("Notification: navigating to memory panel")
        case NotificationManager.Category.proactive.rawValue:
            notificationRequestedSection = "chat"
            Log.app.info("Notification: navigating to conversation for proactive suggestion")
        case NotificationManager.Category.change.rawValue:
            notificationRequestedSection = "chat"
            Log.app.info("Notification: navigating to conversation for heartbeat change alert")
        default:
            break
        }
    }

    // MARK: - Telegram Message Handling

    func handleTelegramMessage(_ update: TelegramUpdate) async {
        Log.telegram.info("Processing Telegram message from \(update.senderUsername ?? "unknown")")

        let route = TelegramBridgeCommandParser.route(update.text)
        switch route {
        case .notCommand:
            break
        case .usageError(let usage):
            await persistAndReplyTelegramCommand(
                update: update,
                userInput: update.text,
                replyText: usage
            )
            return
        case .command(let command):
            await handleTelegramBridgeCommand(command, update: update)
            return
        }

        // Find or create a persistent conversation for this chat
        var conversation = findOrCreateTelegramConversation(
            chatId: update.chatId,
            username: update.senderUsername
        )

        // Append user message
        let userMessage = Message(role: .user, content: update.text)
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

        do {
            let request = try buildNativeLLMRequestFromConversation(
                conversation: conversation,
                channelMetadata: "telegram:\(update.chatId)"
            )
            let toolRefreshContext = makeNativeToolRefreshContext(
                provider: request.provider,
                model: request.model,
                conversation: conversation
            )
            let hookContext = NativeAgentLoopHookContext(
                sessionId: conversation.id.uuidString,
                workspaceId: sessionContext.workspaceId.uuidString,
                agentId: settings.activeAgentName
            )

            var accumulatedText = ""
            var streamMessageId: Int64?
            var pendingStreamSnapshot: String?
            var streamFlushTask: Task<Void, Never>?
            var lastEditLength = 0
            let useStreaming = settings.telegramStreamReplies

            for try await event in nativeAgentLoopService.run(
                request: request,
                hookContext: hookContext,
                toolRefreshContext: toolRefreshContext
            ) {
                switch event.kind {
                case .partial:
                    if let delta = event.text {
                        accumulatedText += delta

                        if useStreaming, let tg = getTelegramService() {
                            let currentLength = accumulatedText.count
                            if currentLength - lastEditLength >= 50 || streamMessageId == nil {
                                let textSnapshot = accumulatedText + " ▍"
                                lastEditLength = currentLength
                                pendingStreamSnapshot = textSnapshot

                                if streamFlushTask == nil {
                                    streamFlushTask = Task { @MainActor in
                                        defer { streamFlushTask = nil }
                                        while let snapshot = pendingStreamSnapshot {
                                            pendingStreamSnapshot = nil
                                            do {
                                                if let msgId = streamMessageId {
                                                    try await tg.editMessage(chatId: update.chatId, messageId: msgId, text: snapshot)
                                                } else {
                                                    streamMessageId = try await tg.sendMessage(chatId: update.chatId, text: snapshot)
                                                }
                                            } catch {
                                                Log.telegram.debug("Streaming edit skipped: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                case .toolUse, .toolResult:
                    continue

                case .done:
                    let finalText = (event.text ?? accumulatedText).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !finalText.isEmpty else {
                        Log.telegram.warning("Empty response for Telegram message")
                        if useStreaming {
                            await streamFlushTask?.value
                        }
                        return
                    }

                    conversation.messages.append(Message(role: .assistant, content: finalText))
                    conversation.updatedAt = Date()

                    // Auto-title from first user message
                    if conversation.title == "새 대화",
                       let firstUser = conversation.messages.first(where: { $0.role == .user }) {
                        let title = String(firstUser.content.prefix(40))
                        conversation.title = title.count < firstUser.content.count ? title + "…" : title
                    }

                    conversationService.save(conversation: conversation)
                    loadConversations()

                    if useStreaming {
                        await streamFlushTask?.value
                    }
                    if let tg = getTelegramService() {
                        if useStreaming, let msgId = streamMessageId {
                            try await tg.editMessage(chatId: update.chatId, messageId: msgId, text: finalText)
                        } else {
                            _ = try await tg.sendMessage(chatId: update.chatId, text: finalText)
                        }
                    }
                    Log.telegram.info("Sent Telegram response to chat \(update.chatId)")
                    return

                case .error:
                    let reason = event.error?.message ?? "알 수 없는 오류"
                    Log.telegram.error("Native loop failed for Telegram: \(reason)")
                    if useStreaming {
                        await streamFlushTask?.value
                    }
                    if let tg = getTelegramService() {
                        _ = try? await tg.sendMessage(chatId: update.chatId, text: "오류가 발생했습니다: \(reason)")
                    }
                    return
                }
            }
        } catch {
            Log.telegram.error("Telegram response failed: \(error.localizedDescription)")
            if let tg = getTelegramService() {
                _ = try? await tg.sendMessage(
                    chatId: update.chatId,
                    text: "요청 처리 중 오류가 발생했습니다: \(error.localizedDescription)"
                )
            }
        }
    }

    private func handleTelegramBridgeCommand(_ command: TelegramBridgeCommand, update: TelegramUpdate) async {
        guard let manager = externalToolManager else {
            await persistAndReplyTelegramCommand(
                update: update,
                userInput: update.text,
                replyText: "브리지 서비스가 아직 준비되지 않았습니다. 잠시 후 다시 시도해주세요."
            )
            return
        }

        let result: LocalControlPlaneMethodResult
        switch command {
        case .bridgeOpen(let agent, let profileName, let workingDirectory, let forceWorkingDirectory):
            var params: [String: Any] = ["agent": agent]
            if let profileName {
                params["profile_name"] = profileName
            }
            if let workingDirectory {
                params["working_directory"] = workingDirectory
            }
            if forceWorkingDirectory {
                params["force_working_directory"] = true
            }
            result = await DochiApp.handleBridgeOpen(
                params: params,
                externalToolManager: manager
            )

        case .bridgeRoots(let limit, let searchPaths):
            var params: [String: Any] = ["limit": limit]
            if !searchPaths.isEmpty {
                params["search_paths"] = searchPaths
            }
            result = await DochiApp.handleBridgeRoots(
                params: params,
                externalToolManager: manager
            )

        case .bridgeStatus(let sessionId):
            var params: [String: Any] = [:]
            if let sessionId {
                params["session_id"] = sessionId
            }
            result = await DochiApp.handleBridgeStatus(
                params: params,
                externalToolManager: manager
            )

        case .bridgeSend(let sessionId, let command):
            result = await DochiApp.handleBridgeSend(
                params: [
                    "session_id": sessionId,
                    "command": command,
                ],
                externalToolManager: manager
            )

        case .bridgeRead(let sessionId, let lines):
            result = await DochiApp.handleBridgeRead(
                params: [
                    "session_id": sessionId,
                    "lines": lines,
                ],
                externalToolManager: manager
            )

        case .bridgeRepoList:
            result = await DochiApp.handleBridgeRepositoryList(
                externalToolManager: manager
            )

        case .bridgeRepoInit(let path, let defaultBranch, let createReadme, let createGitignore):
            result = await DochiApp.handleBridgeRepositoryInit(
                params: [
                    "path": path,
                    "default_branch": defaultBranch,
                    "create_readme": createReadme,
                    "create_gitignore": createGitignore,
                ],
                externalToolManager: manager
            )

        case .bridgeRepoClone(let remoteURL, let destinationPath, let branch):
            var params: [String: Any] = [
                "remote_url": remoteURL,
                "destination_path": destinationPath,
            ]
            if let branch {
                params["branch"] = branch
            }
            result = await DochiApp.handleBridgeRepositoryClone(
                params: params,
                externalToolManager: manager
            )

        case .bridgeRepoAttach(let path):
            result = await DochiApp.handleBridgeRepositoryAttach(
                params: ["path": path],
                externalToolManager: manager
            )

        case .bridgeRepoRemove(let repositoryId, let deleteDirectory):
            result = await DochiApp.handleBridgeRepositoryRemove(
                params: [
                    "repository_id": repositoryId,
                    "delete_directory": deleteDirectory,
                ],
                externalToolManager: manager
            )

        case .orchSelect(let repositoryRoot):
            var params: [String: Any] = [:]
            if let repositoryRoot {
                params["repository_root"] = repositoryRoot
            }
            result = await DochiApp.handleBridgeOrchestratorSelectSession(
                params: params,
                externalToolManager: manager
            )

        case .orchRequest(let command, let repositoryRoot, let ttlSeconds):
            var params: [String: Any] = [
                "command": command,
                "reveal_challenge_code": true,
            ]
            if let repositoryRoot {
                params["repository_root"] = repositoryRoot
            }
            if let ttlSeconds {
                params["ttl_seconds"] = ttlSeconds
            }
            result = await DochiApp.handleBridgeOrchestratorRequest(
                params: params,
                orchestrationApprovalStore: telegramOrchestrationApprovalStore
            )

        case .orchApprove(let approvalId, let challengeCode):
            result = await DochiApp.handleBridgeOrchestratorApprove(
                params: [
                    "approval_id": approvalId,
                    "challenge_code": challengeCode,
                ],
                orchestrationApprovalStore: telegramOrchestrationApprovalStore
            )

        case .orchExecute(let command, let repositoryRoot, let confirmed, let approvalId):
            var params: [String: Any] = ["command": command]
            if let repositoryRoot {
                params["repository_root"] = repositoryRoot
            }
            if confirmed {
                params["confirmed"] = true
            }
            if let approvalId {
                params["approval_id"] = approvalId
            }
            result = await DochiApp.handleBridgeOrchestratorExecute(
                params: params,
                externalToolManager: manager,
                orchestrationApprovalStore: telegramOrchestrationApprovalStore
            )

        case .orchStatus(let repositoryRoot, let sessionId, let lines):
            var params: [String: Any] = ["lines": lines]
            if let repositoryRoot {
                params["repository_root"] = repositoryRoot
            }
            if let sessionId {
                params["session_id"] = sessionId
            }
            result = await DochiApp.handleBridgeOrchestratorStatus(
                params: params,
                externalToolManager: manager,
                orchestrationSummaryService: telegramOrchestrationSummaryService
            )

        case .orchInterrupt(let repositoryRoot, let sessionId):
            var params: [String: Any] = [:]
            if let repositoryRoot {
                params["repository_root"] = repositoryRoot
            }
            if let sessionId {
                params["session_id"] = sessionId
            }
            result = await DochiApp.handleBridgeOrchestratorInterrupt(
                params: params,
                externalToolManager: manager
            )

        case .orchSummarize(let repositoryRoot, let sessionId, let lines):
            var params: [String: Any] = ["lines": lines]
            if let repositoryRoot {
                params["repository_root"] = repositoryRoot
            }
            if let sessionId {
                params["session_id"] = sessionId
            }
            result = await DochiApp.handleBridgeOrchestratorSummarize(
                params: params,
                externalToolManager: manager,
                orchestrationSummaryService: telegramOrchestrationSummaryService
            )
        }

        let replyText = formatTelegramBridgeCommandResult(command: command, result: result)
        await persistAndReplyTelegramCommand(
            update: update,
            userInput: update.text,
            replyText: replyText
        )
    }

    private func formatTelegramBridgeCommandResult(
        command: TelegramBridgeCommand,
        result: LocalControlPlaneMethodResult
    ) -> String {
        guard result.success else {
            return formatTelegramBridgeCommandError(
                code: result.errorCode ?? "unknown_error",
                message: result.errorMessage ?? "요청 처리에 실패했습니다."
            )
        }

        switch command {
        case .bridgeOpen:
            let profile = result.result["profile_name"] as? String ?? "-"
            let sessionId = result.result["session_id"] as? String ?? "-"
            let status = result.result["status"] as? String ?? "-"
            let workingDirectory = result.result["working_directory"] as? String ?? "-"
            let reason = result.result["selection_reason"] as? String ?? "-"
            let detail = result.result["selection_detail"] as? String ?? "-"
            let reused = (result.result["reused"] as? Bool == true) ? "재사용" : "새로 생성"
            return """
            브리지 채널 준비 완료 (\(reused))
            - profile: \(profile)
            - session_id: \(sessionId)
            - status: \(status)
            - working_directory: \(workingDirectory)
            - selection_reason: \(reason)
            - detail: \(detail)
            """

        case .bridgeRoots:
            let roots = result.result["roots"] as? [[String: Any]] ?? []
            if roots.isEmpty {
                return "발견된 Git 루트가 없습니다."
            }
            let lines = roots.prefix(10).map { root in
                let path = root["path"] as? String ?? "-"
                let branch = root["branch"] as? String ?? "-"
                let score = root["score"] as? Int ?? 0
                return "- \(path) (branch: \(branch), score: \(score))"
            }
            return lines.joined(separator: "\n")

        case .bridgeStatus:
            if let sessions = result.result["sessions"] as? [[String: Any]] {
                if sessions.isEmpty {
                    return "브리지/코딩 세션이 없습니다."
                }
                var lines = sessions.map { session in
                    let profile = session["profile_name"] as? String ?? "-"
                    let status = session["status"] as? String ?? "-"
                    let sessionId = session["session_id"] as? String ?? "-"
                    return "- \(profile): \(status) (\(sessionId))"
                }
                let unifiedCount = result.result["unified_count"] as? Int ?? 0
                if unifiedCount > 0 {
                    let unassigned = result.result["unassigned_count"] as? Int ?? 0
                    lines.append("통합 세션: \(unifiedCount) (unassigned: \(unassigned))")
                }
                return lines.joined(separator: "\n")
            }

            let profile = result.result["profile_name"] as? String ?? "-"
            let status = result.result["status"] as? String ?? "-"
            let sessionId = result.result["session_id"] as? String ?? "-"
            return "\(profile): \(status) (\(sessionId))"

        case .bridgeSend:
            let sessionId = result.result["session_id"] as? String ?? "-"
            let command = result.result["command"] as? String ?? "-"
            return """
            전송 완료
            - session_id: \(sessionId)
            - command: \(command)
            """

        case .bridgeRead:
            let lines = result.result["lines"] as? [String] ?? []
            if lines.isEmpty {
                return "(출력 없음)"
            }
            return lines.joined(separator: "\n")

        case .bridgeRepoList:
            let repositories = result.result["repositories"] as? [[String: Any]] ?? []
            if repositories.isEmpty {
                return "관리 중인 리포지토리가 없습니다."
            }
            return repositories.prefix(20).map { repository in
                let name = repository["name"] as? String ?? "-"
                let rootPath = repository["root_path"] as? String ?? "-"
                let source = repository["source"] as? String ?? "-"
                let repositoryId = repository["repository_id"] as? String ?? "-"
                return "- \(name) [\(source)] \(rootPath) (\(repositoryId))"
            }.joined(separator: "\n")

        case .bridgeRepoInit:
            return formatTelegramRepositoryMutationResult(
                title: "리포지토리를 초기화했습니다.",
                result: result
            )

        case .bridgeRepoClone:
            return formatTelegramRepositoryMutationResult(
                title: "리포지토리를 클론했습니다.",
                result: result
            )

        case .bridgeRepoAttach:
            return formatTelegramRepositoryMutationResult(
                title: "리포지토리를 연결했습니다.",
                result: result
            )

        case .bridgeRepoRemove:
            let repositoryId = result.result["repository_id"] as? String ?? "-"
            let deleteDirectory = result.result["delete_directory"] as? Bool ?? false
            return """
            리포지토리를 제거했습니다.
            - repository_id: \(repositoryId)
            - delete_directory: \(deleteDirectory)
            """

        case .orchSelect:
            let action = result.result["action"] as? String ?? "-"
            let reason = result.result["reason"] as? String ?? "-"
            let selected = result.result["selected_session"] as? [String: Any]
            let sessionId = selected?["runtime_session_id"] as? String ?? (selected?["native_session_id"] as? String ?? "-")
            let tier = selected?["controllability_tier"] as? String ?? "-"
            let workingDirectory = selected?["working_directory"] as? String ?? "-"
            return """
            오케스트레이션 세션 선택 결과
            - action: \(action)
            - reason: \(reason)
            - session_id: \(sessionId)
            - tier: \(tier)
            - working_directory: \(workingDirectory)
            """

        case .orchRequest:
            let approvalId = result.result["approval_id"] as? String ?? "-"
            let challengeCode = result.result["challenge_code"] as? String
            let expiresAt = result.result["expires_at"] as? String ?? "-"
            let codeLine: String
            if let challengeCode, !challengeCode.isEmpty {
                codeLine = "- challenge_code: \(challengeCode)"
            } else {
                codeLine = "- challenge_code: (보안 정책으로 별도 채널에서 확인)"
            }
            return """
            실행 승인 요청이 생성되었습니다.
            - approval_id: \(approvalId)
            \(codeLine)
            - expires_at: \(expiresAt)
            다음 단계:
            1) /orch approve \(approvalId) <challenge_code>
            2) /orch execute ... --approval-id \(approvalId)
            """

        case .orchApprove:
            let approvalId = result.result["approval_id"] as? String ?? "-"
            let status = result.result["status"] as? String ?? "-"
            let expiresAt = result.result["expires_at"] as? String ?? "-"
            return """
            실행 승인이 완료되었습니다.
            - approval_id: \(approvalId)
            - status: \(status)
            - expires_at: \(expiresAt)
            """

        case .orchExecute:
            let status = result.result["status"] as? String ?? "sent"
            let guardPayload = result.result["guard"] as? [String: Any]
            let policyCode = guardPayload?["policy_code"] as? String ?? "-"
            let reason = guardPayload?["reason"] as? String ?? "-"
            let approval = result.result["approval"] as? [String: Any]
            let approvalMode = approval?["mode"] as? String ?? "-"
            let approvalStatus = approval?["status"] as? String ?? "-"
            return """
            오케스트레이터 실행 명령을 전송했습니다.
            - status: \(status)
            - policy: \(policyCode)
            - reason: \(reason)
            - approval_mode: \(approvalMode)
            - approval_status: \(approvalStatus)
            """

        case .orchStatus:
            let kind = result.result["result_kind"] as? String ?? "unknown"
            let summary = result.result["summary"] as? String ?? "(요약 없음)"
            let highlights = result.result["highlights"] as? [String] ?? []
            if highlights.isEmpty {
                return "orchestrator.status kind=\(kind)\n\(summary)"
            }
            let highlightsText = highlights.prefix(5).map { "- \($0)" }.joined(separator: "\n")
            return "orchestrator.status kind=\(kind)\n\(summary)\n\(highlightsText)"

        case .orchInterrupt:
            let status = result.result["status"] as? String ?? "interrupted"
            let session = result.result["session"] as? [String: Any]
            let sessionId = session?["session_id"] as? String ?? "-"
            let profile = session?["profile_name"] as? String ?? "-"
            return """
            오케스트레이터 세션 중단 완료
            - status: \(status)
            - profile: \(profile)
            - session_id: \(sessionId)
            """

        case .orchSummarize:
            let kind = result.result["result_kind"] as? String ?? "unknown"
            let summary = result.result["summary"] as? String ?? "(요약 없음)"
            let highlights = result.result["highlights"] as? [String] ?? []
            if highlights.isEmpty {
                return "orchestrator.summarize kind=\(kind)\n\(summary)"
            }
            let highlightsText = highlights.prefix(5).map { "- \($0)" }.joined(separator: "\n")
            return "orchestrator.summarize kind=\(kind)\n\(summary)\n\(highlightsText)"
        }
    }

    private func formatTelegramRepositoryMutationResult(
        title: String,
        result: LocalControlPlaneMethodResult
    ) -> String {
        let repository = result.result["repository"] as? [String: Any]
        let repositoryId = repository?["repository_id"] as? String ?? "-"
        let name = repository?["name"] as? String ?? "-"
        let rootPath = repository?["root_path"] as? String ?? "-"
        let source = repository?["source"] as? String ?? "-"
        let branch = repository?["default_branch"] as? String ?? "-"
        return """
        \(title)
        - repository_id: \(repositoryId)
        - name: \(name)
        - root_path: \(rootPath)
        - source: \(source)
        - default_branch: \(branch)
        """
    }

    private func formatTelegramBridgeCommandError(code: String, message: String) -> String {
        switch code {
        case "approval_required":
            return """
            실행이 차단되었습니다(approval_required).
            - 먼저 /orch request COMMAND... 를 실행해 approval_id를 발급하세요.
            - 다음으로 /orch approve APPROVAL_ID CHALLENGE_CODE 를 실행하세요.
            """
        case "approval_expired":
            return "승인 토큰이 만료되었습니다. /orch request 로 새 승인 요청을 생성해주세요."
        case "approval_already_consumed":
            return "승인 토큰이 이미 사용되었습니다. /orch request 로 새 승인 요청을 생성해주세요."
        case "approval_not_approved":
            return "아직 승인되지 않은 요청입니다. /orch approve 로 먼저 승인해주세요."
        case "approval_context_mismatch":
            return "승인된 command/repository와 실행 요청이 일치하지 않습니다. 같은 값으로 다시 시도해주세요."
        case "approval_code_mismatch":
            return "challenge_code가 일치하지 않습니다. 코드를 확인한 뒤 다시 시도해주세요."
        case "approval_locked":
            return "challenge_code 시도 횟수를 초과했습니다. \(message)"
        default:
            return "요청 실패 (\(code)): \(message)"
        }
    }

    private func persistAndReplyTelegramCommand(
        update: TelegramUpdate,
        userInput: String,
        replyText: String
    ) async {
        var conversation = findOrCreateTelegramConversation(
            chatId: update.chatId,
            username: update.senderUsername
        )
        conversation.messages.append(Message(role: .user, content: userInput))
        conversation.messages.append(Message(role: .assistant, content: replyText))
        conversation.updatedAt = Date()

        if conversation.title == "새 대화",
           let firstUser = conversation.messages.first(where: { $0.role == .user }) {
            let title = String(firstUser.content.prefix(40))
            conversation.title = title.count < firstUser.content.count ? title + "…" : title
        }

        conversationService.save(conversation: conversation)
        loadConversations()

        guard let tg = getTelegramService() else { return }
        do {
            _ = try await tg.sendMessage(chatId: update.chatId, text: replyText)
            Log.telegram.info("Sent Telegram command response to chat \(update.chatId)")
        } catch {
            Log.telegram.error("Telegram command response failed: \(error.localizedDescription)")
        }
    }


    /// Find an existing telegram conversation by chatId, or create a new one.
    private func findOrCreateTelegramConversation(chatId: Int64, username: String?) -> Conversation {
        // Auto-register chat mapping
        let label = username.map { "@\($0)" } ?? "Chat \(chatId)"
        TelegramChatMappingStore.upsert(
            chatId: chatId,
            label: label,
            workspaceId: UUID(uuidString: settings.currentWorkspaceId),
            in: settings
        )

        // Check if mapping is disabled
        let mappings = TelegramChatMappingStore.loadMappings(from: settings)
        if let mapping = mappings.first(where: { $0.chatId == chatId }), !mapping.enabled {
            Log.telegram.info("Chat \(chatId) is disabled in mapping, skipping")
        }

        // Search existing conversations for matching telegramChatId
        if let existing = conversations.first(where: { $0.source == .telegram && $0.telegramChatId == chatId }) {
            // Load the full conversation (with all messages)
            if let loaded = conversationService.load(id: existing.id) {
                return loaded
            }
        }

        // Create new telegram conversation
        let displayName = label
        let conversation = Conversation(
            title: "\(displayName) 텔레그램 DM",
            source: .telegram,
            telegramChatId: chatId
        )
        Log.telegram.info("Created new Telegram conversation for chat \(chatId)")
        return conversation
    }

    /// Get telegram service reference - stored weakly to avoid circular deps
    private var _telegramService: TelegramServiceProtocol?

    func setTelegramService(_ service: TelegramServiceProtocol) {
        _telegramService = service
    }

    private func getTelegramService() -> TelegramServiceProtocol? {
        _telegramService
    }

    // MARK: - Background Wake Word Listener

    private var isBackgroundListening = false

    func startBackgroundWakeWordListener() {
        guard settings.wakeWordEnabled, settings.wakeWordAlwaysOn else { return }
        guard !isBackgroundListening else { return }
        guard interactionState == .idle else { return }
        guard speechService.isAuthorized else {
            Task { [weak self] in
                guard let self else { return }
                let granted = await self.speechService.requestAuthorization()
                if granted {
                    self.startBackgroundWakeWordListener()
                } else {
                    self.errorMessage = "웨이크워드를 사용하려면 마이크 및 음성 인식 권한이 필요합니다."
                }
            }
            return
        }

        isBackgroundListening = true
        Log.app.info("Starting background wake word listener")

        speechService.startContinuousRecognition(
            onPartialResult: { [weak self] text in
                guard let self else { return }
                if self.handleWakeWordDetection(in: text) {
                    self.stopBackgroundWakeWordListener()
                    self.startListening()
                }
            },
            onError: { [weak self] _ in
                guard let self, self.isBackgroundListening else { return }
                // Error handling is done inside SpeechService (auto-retry)
            }
        )
    }

    func stopBackgroundWakeWordListener() {
        guard isBackgroundListening else { return }
        isBackgroundListening = false
        speechService.stopContinuousRecognition()
        Log.app.info("Stopped background wake word listener")
    }

    private func handleWakeWordDetection(in text: String) -> Bool {
        guard settings.wakeWordEnabled else { return false }
        let wakeWord = settings.wakeWord
        return JamoMatcher.isMatch(transcript: text, wakeWord: wakeWord)
    }


    // MARK: - Context Composition

    private func composeSystemPrompt(
        workspaceMemoryOverride: String? = nil,
        agentMemoryOverride: String? = nil,
        personalMemoryOverride: String? = nil,
        additionalSections: [String] = []
    ) -> String {
        var parts: [String] = []

        // 1. Base system prompt
        if let base = contextService.loadBaseSystemPrompt(), !base.isEmpty {
            parts.append(base)
        }

        // 2. Agent persona
        let agentName = settings.activeAgentName
        let wsId = sessionContext.workspaceId
        if let persona = contextService.loadAgentPersona(workspaceId: wsId, agentName: agentName), !persona.isEmpty {
            parts.append("## 에이전트 페르소나\n\(persona)")
        }

        // 3. Current date/time
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy년 M월 d일 (E) a h:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        parts.append("현재 시각: \(formatter.string(from: Date()))")

        // 4. Current user info or identification prompt
        let profiles = contextService.loadProfiles()
        if let userId = sessionContext.currentUserId,
           let currentProfile = profiles.first(where: { $0.id.uuidString == userId }) {
            parts.append("## 현재 사용자\n현재 대화 중인 사용자: \(currentProfile.name)")
        } else if !profiles.isEmpty {
            let nameList = profiles.map(\.name).joined(separator: ", ")
            parts.append("## 사용자 식별\n현재 사용자가 설정되지 않았습니다. 대화 시작 시 자연스러운 방식으로 사용자를 식별하고, set_current_user 도구를 사용하세요.\n등록된 사용자: \(nameList)")
        }

        // 5. Workspace memory
        let workspaceMemory = workspaceMemoryOverride ?? (contextService.loadWorkspaceMemory(workspaceId: wsId) ?? "")
        if !workspaceMemory.isEmpty {
            let wsMem = workspaceMemory
            parts.append("## 워크스페이스 메모리\n\(wsMem)")
        }

        // 6. Agent memory
        let agentMemory = agentMemoryOverride ?? (
            contextService.loadAgentMemory(workspaceId: wsId, agentName: agentName) ?? ""
        )
        if !agentMemory.isEmpty {
            let agentMem = agentMemory
            parts.append("## 에이전트 메모리\n\(agentMem)")
        }

        // 7. Personal memory
        let personalMemory: String = {
            if let override = personalMemoryOverride { return override }
            guard let userId = sessionContext.currentUserId else { return "" }
            return contextService.loadUserMemory(userId: userId) ?? ""
        }()
        if !personalMemory.isEmpty {
            let personalMem = personalMemory
            parts.append("## 개인 메모리\n\(personalMem)")
        }

        // 8. Interest discovery (K-3)
        if let interestAddition = interestDiscoveryService?.buildDiscoverySystemPromptAddition() {
            parts.append(interestAddition)
        }

        // 9. External tool status (K-4)
        if let manager = externalToolManager, !manager.sessions.isEmpty {
            var lines: [String] = ["## 외부 AI 도구 세션"]
            for session in manager.sessions where session.status != .dead {
                let profileName = manager.profiles.first(where: { $0.id == session.profileId })?.name ?? "?"
                lines.append("- \(profileName): \(session.status.rawValue) (tmux: \(session.tmuxSessionName))")
            }
            if !lines.isEmpty {
                parts.append(lines.joined(separator: "\n"))
            }
        }

        // 10. Summary snapshot fallback (context compaction)
        if !additionalSections.isEmpty {
            parts.append(contentsOf: additionalSections)
        }

        // 11. Tool behavior hints
        parts.append(
            """
            ## 도구 사용 규칙
            - generate_image 호출 시 prompt는 반드시 영어로 작성하세요.
            - 사용자가 한국어로 요청하면 의미를 보존해 영어 이미지 프롬프트로 변환한 뒤 generate_image를 호출하세요.
            """
        )

        // 12. Non-baseline tool listing for LLM awareness
        let nonBaseline = toolService.nonBaselineToolSummaries
        if !nonBaseline.isEmpty {
            var lines: [String] = ["## 추가 도구", "필요 시 tools.enable으로 활성화할 수 있는 도구:"]
            for tool in nonBaseline {
                lines.append("- \(tool.name): \(tool.description) (\(tool.category.rawValue))")
            }
            lines.append("사용자가 관련 작업을 요청하면 tools.enable으로 먼저 활성화하세요.")
            lines.append("같은 tools.enable을 반복 호출하지 말고, 활성화 후에는 요청된 실제 도구를 바로 호출하세요.")
            parts.append(lines.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }

    private func buildNativeLLMRequestFromConversation(
        conversation: Conversation? = nil,
        channelMetadata: String? = nil,
        provider overrideProvider: LLMProvider? = nil,
        model overrideModel: String? = nil
    ) throws -> NativeLLMRequest {
        guard let conversation = conversation ?? currentConversation else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "현재 대화가 없습니다.",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        let provider = overrideProvider ?? settings.currentProvider
        let candidateModel = (overrideModel ?? settings.llmModel).trimmingCharacters(in: .whitespacesAndNewlines)
        let model = candidateModel.isEmpty ? provider.onboardingDefaultModel : candidateModel
        let capabilities = ProviderCapabilityMatrix.capabilities(
            for: provider,
            model: model
        )

        if !capabilities.supportsOutputTokenReporting || !capabilities.supportsStreamUsage {
            Log.runtime.debug(
                "Capability note: token usage metrics may be partial for \(provider.rawValue)/\(model)"
            )
        }

        let rawMessages = buildNativeMessages(from: conversation.messages)
        if rawMessages.isEmpty {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "네이티브 요청에 포함할 대화 메시지가 없습니다.",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        let workspaceMemory = contextService.loadWorkspaceMemory(workspaceId: sessionContext.workspaceId) ?? ""
        let agentMemory = contextService.loadAgentMemory(
            workspaceId: sessionContext.workspaceId,
            agentName: settings.activeAgentName
        ) ?? ""
        let personalMemory: String = {
            guard let userId = normalizedUserId(sessionContext.currentUserId) else { return "" }
            return contextService.loadUserMemory(userId: userId) ?? ""
        }()
        let requestedTools = buildNativeToolDefinitions(
            intentHint: latestUserIntentHint(in: conversation)
        )
        let shouldDisableToolsForCapability = !capabilities.supportsToolCalling && !requestedTools.isEmpty
        let enabledTools = shouldDisableToolsForCapability ? [] : requestedTools

        let contextWindow = provider.contextWindowTokens(for: model)
        let reservedOutputTokens = min(4_096, max(contextWindow / 5, 1_024))
        let configuredBudgetTokens = max(settings.contextMaxSize / 2, 1)
        let maxInputBudget = max(contextWindow - reservedOutputTokens, 1)
        let tokenBudget = min(maxInputBudget, configuredBudgetTokens)

        let fixedPrompt = composeSystemPrompt(
            workspaceMemoryOverride: "",
            agentMemoryOverride: "",
            personalMemoryOverride: ""
        )
        let fixedPromptTokens = contextCompactionService.estimateSystemPromptTokens(
            for: fixedPrompt,
            provider: provider,
            model: model
        )
        let fixedToolTokens = contextCompactionService.estimateTokens(
            for: enabledTools,
            provider: provider,
            model: model
        )

        let compaction = contextCompactionService.compact(
            request: ContextCompactionRequest(
                provider: provider,
                model: model,
                workspaceMemory: workspaceMemory,
                agentMemory: agentMemory,
                personalMemory: personalMemory,
                messages: rawMessages,
                tokenBudget: tokenBudget,
                fixedPromptTokens: fixedPromptTokens + fixedToolTokens,
                autoCompactEnabled: settings.contextAutoCompress,
                conversationSummary: conversation.summary
            )
        )
        metricsCollector.recordContextCompaction(compaction.metrics)
        persistContextSnapshotsIfCompacted(
            workspaceMemory: workspaceMemory,
            agentMemory: agentMemory,
            personalMemory: personalMemory,
            metrics: compaction.metrics
        )

        var additionalSections: [String] = []
        if let summarySnapshot = compaction.summarySnapshot, !summarySnapshot.isEmpty {
            additionalSections.append("## 컨텍스트 요약 스냅샷\n\(summarySnapshot)")
        }
        if let channelMetadata, !channelMetadata.isEmpty {
            additionalSections.append("## 채널 메타데이터\n\(channelMetadata)")
        }
        if shouldDisableToolsForCapability {
            additionalSections.append(
                "## 런타임 제약\n현재 선택한 모델은 도구 호출을 지원하지 않아 텍스트 응답만 제공합니다."
            )
            Log.runtime.notice(
                "Capability fallback applied: disabling tools for \(provider.rawValue)/\(model)"
            )
        }

        let compactedSystemPrompt = composeSystemPrompt(
            workspaceMemoryOverride: compaction.layers.workspaceMemory,
            agentMemoryOverride: compaction.layers.agentMemory,
            personalMemoryOverride: compaction.layers.personalMemory,
            additionalSections: additionalSections
        )
        let compactedInputTokens = contextCompactionService.estimateRequestInputTokens(
            systemPrompt: compactedSystemPrompt,
            messages: compaction.messages,
            tools: enabledTools,
            provider: provider,
            model: model
        )
        let outputTokenHeadroom = contextWindow - compactedInputTokens - 512
        guard outputTokenHeadroom > 0 else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "컨텍스트 예산이 부족합니다. contextMaxSize를 늘리거나 대화를 정리한 뒤 다시 시도해주세요.",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }
        let maxTokens = min(4_096, outputTokenHeadroom)

        return NativeLLMRequest(
            provider: provider,
            model: model,
            apiKey: loadNativeAPIKey(for: provider),
            systemPrompt: compactedSystemPrompt,
            messages: compaction.messages,
            tools: enabledTools,
            maxTokens: maxTokens,
            endpointURL: nativeEndpointURL(for: provider)
        )
    }

    private func persistContextSnapshotsIfCompacted(
        workspaceMemory: String,
        agentMemory: String,
        personalMemory: String,
        metrics: ContextCompactionMetrics
    ) {
        guard metrics.didCompact else { return }

        if metrics.truncatedWorkspaceMemory, !workspaceMemory.isEmpty {
            contextService.saveWorkspaceMemorySnapshot(
                workspaceId: sessionContext.workspaceId,
                content: workspaceMemory
            )
        }

        if metrics.truncatedAgentMemory, !agentMemory.isEmpty {
            contextService.saveAgentMemorySnapshot(
                workspaceId: sessionContext.workspaceId,
                agentName: settings.activeAgentName,
                content: agentMemory
            )
        }

        if metrics.truncatedPersonalMemory,
           let userId = normalizedUserId(sessionContext.currentUserId),
           !personalMemory.isEmpty {
            contextService.saveUserMemorySnapshot(
                userId: userId,
                content: personalMemory
            )
        }
    }

    private func buildNativeMessages(from messages: [Message]) -> [NativeLLMMessage] {
        messages.compactMap { message in
            switch message.role {
            case .system:
                return nil
            case .user:
                return NativeLLMMessage(role: .user, text: message.content)
            case .assistant:
                return NativeLLMMessage(role: .assistant, text: message.content)
            case .tool:
                return NativeLLMMessage(
                    role: .user,
                    contents: [.toolResult(
                        toolCallId: message.toolCallId ?? message.id.uuidString,
                        content: message.content,
                        isError: Self.isLikelyToolError(message.content)
                    )]
                )
            }
        }
    }

    private func buildNativeToolDefinitions(intentHint: String?) -> [NativeLLMToolDefinition] {
        let schemas = toolService.availableToolSchemas(
            for: currentAgentPermissions(),
            preferredToolGroups: currentAgentPreferredToolGroups(),
            intentHint: intentHint
        )
        selectedCapabilityLabel = toolService.selectedCapabilityLabel

        return schemas.compactMap { schema in
            guard let function = schema["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let description = function["description"] as? String,
                  let rawInputSchema = function["parameters"] as? [String: Any] else {
                return nil
            }

            let inputSchema = rawInputSchema.compactMapValues { Self.toAnyCodableValue($0) }
            return NativeLLMToolDefinition(
                name: name,
                description: description,
                inputSchema: inputSchema
            )
        }
    }

    private func latestUserIntentHint(in conversation: Conversation) -> String? {
        for message in conversation.messages.reversed() {
            guard message.role == .user else { continue }
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func makeNativeToolRefreshContext(
        provider: LLMProvider,
        model: String,
        conversation: Conversation?
    ) -> NativeAgentLoopToolRefreshContext {
        let capabilities = ProviderCapabilityMatrix.capabilities(
            for: provider,
            model: model
        )
        return NativeAgentLoopToolRefreshContext(
            permissions: currentAgentPermissions(),
            preferredToolGroups: currentAgentPreferredToolGroups(),
            intentHint: conversation.flatMap { latestUserIntentHint(in: $0) },
            supportsToolCalling: capabilities.supportsToolCalling
        )
    }

    private func nativeEndpointURL(for provider: LLMProvider) -> URL? {
        switch provider {
        case .ollama:
            return localChatCompletionsEndpoint(
                baseURLString: settings.ollamaBaseURL,
                fallback: provider.apiURL
            )
        case .lmStudio:
            return localChatCompletionsEndpoint(
                baseURLString: settings.lmStudioBaseURL,
                fallback: provider.apiURL
            )
        default:
            return nil
        }
    }

    private func localChatCompletionsEndpoint(baseURLString: String, fallback: URL) -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let baseURL = URL(string: trimmed) else {
            return fallback
        }

        let normalizedPath = baseURL.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("v1/chat/completions") {
            return baseURL
        }
        if normalizedPath.hasSuffix("chat/completions") {
            return baseURL
        }
        if normalizedPath.hasSuffix("v1/models") {
            return baseURL
                .deletingLastPathComponent()
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        if normalizedPath.hasSuffix("v1") {
            return baseURL
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        if normalizedPath.hasSuffix("api/tags") {
            return baseURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("v1")
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        return baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    private func loadNativeAPIKey(for provider: LLMProvider) -> String? {
        guard provider.requiresAPIKey else { return nil }

        if let key = keychainService.load(account: provider.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }

        if let legacyAccount = provider.legacyAPIKeyAccount,
           let legacy = keychainService.load(account: legacyAccount)?
           .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            return legacy
        }

        return nil
    }

    private static func toAnyCodableValue(_ value: Any) -> AnyCodableValue? {
        switch value {
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let doubleValue = number.doubleValue
            if floor(doubleValue) == doubleValue {
                return .int(number.intValue)
            }
            return .double(doubleValue)
        case let array as [Any]:
            let converted = array.compactMap(Self.toAnyCodableValue)
            return .array(converted)
        case let dictionary as [String: Any]:
            let converted = dictionary.compactMapValues(Self.toAnyCodableValue)
            return .object(converted)
        case _ as NSNull:
            return .null
        default:
            return nil
        }
    }

    private static func isLikelyToolError(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("오류") || trimmed.hasPrefix("error")
    }

    // MARK: - API Key Management

    var setupHealthReport: SetupHealthReport {
        let provider = settings.currentProvider
        let hasKey = !loadAPIKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasProviderAPIKey = !provider.requiresAPIKey || hasKey
        return settings.setupHealthReport(hasProviderAPIKey: hasProviderAPIKey)
    }

    func loadAPIKey(for provider: LLMProvider) -> String {
        keychainService.load(account: provider.keychainAccount) ?? ""
    }

    func saveAPIKey(_ key: String, for provider: LLMProvider) {
        if key.isEmpty {
            try? keychainService.delete(account: provider.keychainAccount)
        } else {
            try? keychainService.save(account: provider.keychainAccount, value: key)
        }
    }

    func maskedAPIKey(for provider: LLMProvider) -> String {
        guard let key = keychainService.load(account: provider.keychainAccount), !key.isEmpty else {
            return ""
        }
        return "\(key.prefix(6))****"
    }

    // MARK: - Export

    func exportConversation(id: UUID, format: ExportFormat, options: ExportOptions = .default) {
        guard let conversation = conversationService.load(id: id) else {
            Log.app.warning("Export failed: conversation not found \(id)")
            return
        }
        exportConversationToFile(conversation, format: format, options: options)
    }

    func exportConversationToFile(_ conversation: Conversation, format: ExportFormat, options: ExportOptions = .default) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ConversationExporter.suggestedFileName(for: conversation, format: format)
        panel.canCreateDirectories = true

        switch format {
        case .markdown:
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        case .json:
            panel.allowedContentTypes = [.json]
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        case .plainText:
            panel.allowedContentTypes = [.plainText]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            guard let data = ConversationExporter.exportToData(conversation, format: format, options: options) else {
                errorMessage = "내보내기 실패: 데이터 생성 실패"
                return
            }
            try data.write(to: url, options: .atomic)
            Log.app.info("Exported conversation \(conversation.id) as \(format.rawValue)")
        } catch {
            Log.app.error("Export failed: \(error.localizedDescription)")
            errorMessage = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    func exportConversationToClipboard(_ conversation: Conversation, format: ExportFormat, options: ExportOptions = .default) {
        if let text = ConversationExporter.exportToString(conversation, format: format, options: options) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            Log.app.info("Copied conversation \(conversation.id) to clipboard as \(format.rawValue)")
        } else if format == .pdf {
            errorMessage = "PDF는 클립보드에 복사할 수 없습니다"
        }
    }

    func bulkExportConversations(format: ExportFormat, options: ExportOptions = .default) {
        let selected = conversations.filter { selectedConversationIds.contains($0.id) }
        guard !selected.isEmpty else { return }

        for conversation in selected {
            exportConversationToFile(conversation, format: format, options: options)
        }
    }

    func bulkExportMerged(options: ExportOptions = .default) {
        let selected = conversations.filter { selectedConversationIds.contains($0.id) }
        guard !selected.isEmpty else { return }

        let merged = ConversationExporter.mergeToMarkdown(selected, options: options)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "대화모음_\(selected.count)개.md"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try merged.write(to: url, atomically: true, encoding: .utf8)
            Log.app.info("Exported \(selected.count) conversations merged")
        } catch {
            Log.app.error("Merged export failed: \(error.localizedDescription)")
            errorMessage = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Agent Permissions

    private func currentAgentPermissions() -> [String] {
        currentAgentConfig()?.effectivePermissions ?? ["safe"]
    }

    private func currentAgentPreferredToolGroups() -> [String] {
        currentAgentConfig()?.effectivePreferredToolGroups ?? []
    }

    private func currentAgentConfig() -> AgentConfig? {
        contextService.loadAgentConfig(
            workspaceId: sessionContext.workspaceId,
            agentName: settings.activeAgentName
        )
    }

    // MARK: - Conversation Management

    private func ensureConversation() {
        if currentConversation == nil {
            currentConversation = Conversation(userId: sessionContext.currentUserId)
        }
        if !isControlPlaneSecretExecutionActive {
            markCurrentNativeSessionActive()
        }
    }

    private func appendUserMessage(_ text: String, imageData: [ImageContent]? = nil) {
        currentConversation?.messages.append(Message(role: .user, content: text, imageData: imageData))
        currentConversation?.updatedAt = Date()
    }

    private func appendAssistantMessage(_ text: String, metadata: MessageMetadata? = nil, toolExecutionRecords: [ToolExecutionRecord]? = nil) {
        let memoryInfo = buildMemoryContextInfo()
        currentConversation?.messages.append(Message(role: .assistant, content: text, metadata: metadata, toolExecutionRecords: toolExecutionRecords, memoryContextInfo: memoryInfo.hasAnyMemory ? memoryInfo : nil, ragContextInfo: ragLastContextInfo))
        currentConversation?.updatedAt = Date()
    }

    private func buildNativeMessageMetadata(
        provider: LLMProvider,
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        totalLatency: TimeInterval,
        wasFallback: Bool
    ) -> MessageMetadata {
        MessageMetadata(
            provider: provider.rawValue,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalLatency: totalLatency,
            wasFallback: wasFallback
        )
    }

    private func recordNativeExchangeMetrics(
        provider: LLMProvider,
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        firstByteLatency: TimeInterval?,
        totalLatency: TimeInterval,
        wasFallback: Bool
    ) {
        let totalTokens: Int?
        if inputTokens == nil && outputTokens == nil {
            totalTokens = nil
        } else {
            totalTokens = (inputTokens ?? 0) + (outputTokens ?? 0)
        }

        metricsCollector.record(ExchangeMetrics(
            provider: provider.rawValue,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            firstByteLatency: firstByteLatency,
            totalLatency: totalLatency,
            timestamp: Date(),
            wasFallback: wasFallback,
            agentName: settings.activeAgentName
        ))
    }

    private func appendToolResultMessage(_ result: ToolResult) {
        let imageURLs = Self.extractImageURLs(from: result.content)
        currentConversation?.messages.append(
            Message(role: .tool, content: result.content, toolCallId: result.toolCallId, imageURLs: imageURLs.isEmpty ? nil : imageURLs)
        )
        currentConversation?.updatedAt = Date()
    }

    /// Extract image file URLs from tool result content.
    /// Matches markdown images `![...](path)` and plain file paths to images.
    private static func extractImageURLs(from content: String) -> [URL] {
        var urls: [URL] = []
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]

        // Match markdown image: ![...](path)
        let mdPattern = /!\[.*?\]\((.+?)\)/
        for match in content.matches(of: mdPattern) {
            let path = String(match.1)
            if imageExtensions.contains((path as NSString).pathExtension.lowercased()),
               FileManager.default.fileExists(atPath: path) {
                urls.append(URL(fileURLWithPath: path))
            }
        }

        // Match "경로: /path/to/file.ext" pattern from generate_image
        let pathPattern = /경로:\s*(.+)/
        for match in content.matches(of: pathPattern) {
            let path = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            if imageExtensions.contains((path as NSString).pathExtension.lowercased()),
               FileManager.default.fileExists(atPath: path) {
                urls.append(URL(fileURLWithPath: path))
            }
        }

        return urls
    }

    private func saveConversation() {
        guard let conversation = currentConversation else { return }
        guard !isControlPlaneSecretExecutionActive else {
            Log.app.debug("Secret control-plane execution: skip conversation persistence")
            return
        }
        markCurrentNativeSessionActive()

        if conversation.title == "새 대화",
           let firstUser = conversation.messages.first(where: { $0.role == .user }) {
            let title = String(firstUser.content.prefix(40))
            currentConversation?.title = title.count < firstUser.content.count ? title + "…" : title
        }

        conversationService.save(conversation: currentConversation!)
        loadConversations()
        indexCurrentConversationIfNeeded()
        Log.app.debug("Conversation saved: \(conversation.id)")
    }

    private func markCurrentNativeSessionActive() {
        guard !isControlPlaneSecretExecutionActive else { return }
        guard let conversation = currentConversation else { return }
        let workspaceId = sessionContext.workspaceId
        let agentId = settings.activeAgentName
        let ownerUserId = normalizedUserId(conversation.userId) ?? normalizedUserId(sessionContext.currentUserId)

        if nativeSessionStore.recoverIfInterrupted(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversation.id,
            userId: ownerUserId
        ) != nil {
            return
        }

        _ = nativeSessionStore.activate(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversation.id,
            userId: ownerUserId
        )
    }

    private func markCurrentNativeSessionInterrupted() {
        guard !isControlPlaneSecretExecutionActive else { return }
        guard let conversation = currentConversation else { return }
        let ownerUserId = normalizedUserId(conversation.userId) ?? normalizedUserId(sessionContext.currentUserId)
        _ = nativeSessionStore.interrupt(
            workspaceId: sessionContext.workspaceId,
            agentId: settings.activeAgentName,
            conversationId: conversation.id,
            userId: ownerUserId
        )
    }

    private func normalizedUserId(_ userId: String?) -> String? {
        guard let trimmed = userId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }


    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        errorMessage = "오류가 발생했습니다: \(error.localizedDescription)"
        Log.app.error("Error: \(error.localizedDescription, privacy: .public)")

        if !streamingText.isEmpty {
            appendAssistantMessage(streamingText)
            streamingText = ""
        }

        saveConversation()
        ttsService.stopAndClear()
        sentenceChunker = SentenceChunker()
        processingSubState = nil
        currentToolName = nil
        transition(to: .idle)
    }
}
