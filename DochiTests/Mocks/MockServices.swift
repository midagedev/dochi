import Foundation
@testable import Dochi

// MARK: - MockContextService

@MainActor
final class MockContextService: ContextServiceProtocol {
    var baseSystemPrompt: String?
    var profiles: [UserProfile] = []
    var userMemory: [String: String] = [:]
    var workspaceMemory: [UUID: String] = [:]
    var projectsByWorkspace: [UUID: [String: ProjectContext]] = [:]
    var projectMemoriesByWorkspace: [UUID: [String: String]] = [:]
    var agentPersonas: [String: String] = [:]
    var agentMemories: [String: String] = [:]
    var agentConfigs: [String: AgentConfig] = [:]
    var agentConfigDataStore: [String: Data] = [:]
    var agents: [UUID: [String]] = [:]
    var migrateCallCount = 0
    var workspaceMemorySnapshots: [UUID: String] = [:]
    var agentMemorySnapshots: [String: String] = [:]
    var userMemorySnapshots: [String: String] = [:]
    var localWorkspaces: [UUID] = [UUID(uuidString: "00000000-0000-0000-0000-000000000000")!]
    var conversationTags: [ConversationTag] = []
    var conversationFolders: [ConversationFolder] = []
    var customTemplates: [AgentTemplate] = []

    func loadBaseSystemPrompt() -> String? { baseSystemPrompt }
    func saveBaseSystemPrompt(_ content: String) { baseSystemPrompt = content }

    func loadProfiles() -> [UserProfile] { profiles }
    func saveProfiles(_ p: [UserProfile]) { profiles = p }

    func loadUserMemory(userId: String) -> String? { userMemory[userId] }
    func saveUserMemory(userId: String, content: String) { userMemory[userId] = content }
    func appendUserMemory(userId: String, content: String) {
        userMemory[userId] = (userMemory[userId] ?? "") + "\n" + content
    }

    func loadWorkspaceMemory(workspaceId: UUID) -> String? { workspaceMemory[workspaceId] }
    func saveWorkspaceMemory(workspaceId: UUID, content: String) { workspaceMemory[workspaceId] = content }
    func appendWorkspaceMemory(workspaceId: UUID, content: String) {
        workspaceMemory[workspaceId] = (workspaceMemory[workspaceId] ?? "") + "\n" + content
    }

    func listProjects(workspaceId: UUID) -> [ProjectContext] {
        Array(projectsByWorkspace[workspaceId, default: [:]].values)
            .sorted { $0.displayName < $1.displayName }
    }

    func loadProject(workspaceId: UUID, projectId: String) -> ProjectContext? {
        projectsByWorkspace[workspaceId]?[projectId]
    }

    func saveProject(workspaceId: UUID, project: ProjectContext) {
        projectsByWorkspace[workspaceId, default: [:]][project.id] = project
    }

    func removeProject(workspaceId: UUID, projectId: String) {
        projectsByWorkspace[workspaceId]?[projectId] = nil
        projectMemoriesByWorkspace[workspaceId]?[projectId] = nil
    }

    func registerProject(workspaceId: UUID, repoRootPath: String, defaultBranch: String?) -> ProjectContext {
        let project = ProjectContext(repoRootPath: repoRootPath, defaultBranch: defaultBranch)
        saveProject(workspaceId: workspaceId, project: project)
        return project
    }

    func loadProjectMemory(workspaceId: UUID, projectId: String) -> String? {
        projectMemoriesByWorkspace[workspaceId]?[projectId]
    }

    func saveProjectMemory(workspaceId: UUID, projectId: String, content: String) {
        projectMemoriesByWorkspace[workspaceId, default: [:]][projectId] = content
    }

    func appendProjectMemory(workspaceId: UUID, projectId: String, content: String) {
        let current = loadProjectMemory(workspaceId: workspaceId, projectId: projectId) ?? ""
        saveProjectMemory(workspaceId: workspaceId, projectId: projectId, content: current + "\n" + content)
    }

    private func agentKey(_ wsId: UUID, _ name: String) -> String { "\(wsId)|\(name)" }

    func loadAgentPersona(workspaceId: UUID, agentName: String) -> String? {
        agentPersonas[agentKey(workspaceId, agentName)]
    }
    func saveAgentPersona(workspaceId: UUID, agentName: String, content: String) {
        agentPersonas[agentKey(workspaceId, agentName)] = content
    }

    func loadAgentMemory(workspaceId: UUID, agentName: String) -> String? {
        agentMemories[agentKey(workspaceId, agentName)]
    }
    func saveAgentMemory(workspaceId: UUID, agentName: String, content: String) {
        agentMemories[agentKey(workspaceId, agentName)] = content
    }
    func appendAgentMemory(workspaceId: UUID, agentName: String, content: String) {
        let key = agentKey(workspaceId, agentName)
        agentMemories[key] = (agentMemories[key] ?? "") + "\n" + content
    }

    func loadAgentConfig(workspaceId: UUID, agentName: String) -> AgentConfig? {
        agentConfigs[agentKey(workspaceId, agentName)]
    }
    func saveAgentConfig(workspaceId: UUID, config: AgentConfig) {
        agentConfigs[agentKey(workspaceId, config.name)] = config
    }
    func loadAgentConfigData(workspaceId: UUID, agentName: String) -> Data? {
        agentConfigDataStore[agentKey(workspaceId, agentName)]
    }
    func saveAgentConfigData(workspaceId: UUID, agentName: String, data: Data) {
        agentConfigDataStore[agentKey(workspaceId, agentName)] = data
    }
    func listAgents(workspaceId: UUID) -> [String] {
        agents[workspaceId] ?? []
    }
    func createAgent(workspaceId: UUID, name: String, wakeWord: String?, description: String?) {
        let config = AgentConfig(name: name, wakeWord: wakeWord, description: description)
        saveAgentConfig(workspaceId: workspaceId, config: config)
        agents[workspaceId, default: []].append(name)
    }

    func listLocalWorkspaces() -> [UUID] { localWorkspaces }
    func createLocalWorkspace(id: UUID) {
        if !localWorkspaces.contains(id) { localWorkspaces.append(id) }
    }
    func deleteLocalWorkspace(id: UUID) {
        localWorkspaces.removeAll { $0 == id }
    }
    func deleteAgent(workspaceId: UUID, name: String) {
        agents[workspaceId]?.removeAll { $0 == name }
        agentConfigs.removeValue(forKey: agentKey(workspaceId, name))
    }

    func saveWorkspaceMemorySnapshot(workspaceId: UUID, content: String) {
        workspaceMemorySnapshots[workspaceId] = content
    }

    func saveAgentMemorySnapshot(workspaceId: UUID, agentName: String, content: String) {
        agentMemorySnapshots[agentKey(workspaceId, agentName)] = content
    }

    func saveUserMemorySnapshot(userId: String, content: String) {
        userMemorySnapshots[userId] = content
    }

    func loadTags() -> [ConversationTag] { conversationTags }
    func saveTags(_ tags: [ConversationTag]) { conversationTags = tags }

    func loadFolders() -> [ConversationFolder] { conversationFolders }
    func saveFolders(_ folders: [ConversationFolder]) { conversationFolders = folders }

    func loadCustomTemplates() -> [AgentTemplate] { customTemplates }
    func saveCustomTemplates(_ templates: [AgentTemplate]) { customTemplates = templates }

    func migrateIfNeeded() { migrateCallCount += 1 }
}

// MARK: - MockConversationService

@MainActor
final class MockConversationService: ConversationServiceProtocol {
    var conversations: [UUID: Conversation] = [:]

    func list() -> [Conversation] {
        conversations.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func load(id: UUID) -> Conversation? {
        conversations[id]
    }

    func save(conversation: Conversation) {
        conversations[conversation.id] = conversation
    }

    func delete(id: UUID) {
        conversations.removeValue(forKey: id)
    }
}

// MARK: - MockKeychainService

@MainActor
final class MockKeychainService: KeychainServiceProtocol {
    var store: [String: String] = [:]

    func save(account: String, value: String) throws {
        store[account] = value
    }

    func load(account: String) -> String? {
        store[account]
    }

    func delete(account: String) throws {
        store.removeValue(forKey: account)
    }
}

// MARK: - MockBuiltInToolService

@MainActor
final class MockBuiltInToolService: BuiltInToolServiceProtocol {
    var confirmationHandler: ToolConfirmationHandler?
    var selectedCapabilityLabel: String?
    var stubbedSchemas: [[String: Any]] = []
    var stubbedResult = ToolResult(toolCallId: "mock", content: "ok")
    var executeCallCount = 0
    var lastExecutedName: String?
    var lastArguments: [String: Any]?
    var enabledNames: [String] = []
    var resetCallCount = 0
    var lastPreferredToolGroups: [String]?
    /// Optional delay injected before returning `stubbedResult` in `execute(name:arguments:)`.
    var executeDelay: Duration?

    var nonBaselineToolSummaries: [(name: String, description: String, category: ToolCategory)] = []
    var allToolInfos: [ToolInfo] = []

    func availableToolSchemas(for permissions: [String]) -> [[String: Any]] {
        lastPreferredToolGroups = nil
        return stubbedSchemas
    }

    func availableToolSchemas(for permissions: [String], preferredToolGroups: [String]) -> [[String: Any]] {
        lastPreferredToolGroups = preferredToolGroups
        return stubbedSchemas
    }

    func execute(name: String, arguments: [String: Any]) async -> ToolResult {
        if let delay = executeDelay {
            try? await Task.sleep(for: delay)
        }
        executeCallCount += 1
        lastExecutedName = name
        lastArguments = arguments
        return stubbedResult
    }

    func enableTools(names: [String]) {
        enabledNames.append(contentsOf: names)
    }

    func enableToolsTTL(minutes: Int) {}

    func resetRegistry() {
        resetCallCount += 1
        enabledNames.removeAll()
    }
}

// MARK: - MockSpeechService

@MainActor
final class MockSpeechService: SpeechServiceProtocol {
    var isAuthorized: Bool = true
    var isListening: Bool = false
    var stubbedAuthResult: Bool = true
    var lastSilenceTimeout: TimeInterval?
    var continuousRecognitionActive = false

    func requestAuthorization() async -> Bool { stubbedAuthResult }

    func startListening(
        silenceTimeout: TimeInterval,
        onPartialResult: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        lastSilenceTimeout = silenceTimeout
        isListening = true
    }

    func stopListening() {
        isListening = false
    }

    func startContinuousRecognition(
        onPartialResult: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        continuousRecognitionActive = true
        isListening = true
    }

    func stopContinuousRecognition() {
        continuousRecognitionActive = false
        isListening = false
    }
}

// MARK: - MockTTSService

@MainActor
final class MockTTSService: TTSServiceProtocol {
    var engineState: TTSEngineState = .ready
    var isSpeaking: Bool = false
    var onComplete: (@MainActor () -> Void)?

    var loadCallCount = 0
    var enqueuedSentences: [String] = []
    var stopCallCount = 0

    func loadEngine() async throws {
        loadCallCount += 1
        engineState = .ready
    }

    func unloadEngine() {
        engineState = .unloaded
    }

    func enqueueSentence(_ text: String) {
        enqueuedSentences.append(text)
        isSpeaking = true
    }

    func stopAndClear() {
        stopCallCount += 1
        enqueuedSentences.removeAll()
        isSpeaking = false
    }
}

// MARK: - MockSoundService

@MainActor
final class MockSoundService: SoundServiceProtocol {
    var wakeWordCount = 0
    var inputCompleteCount = 0

    func playWakeWordDetected() { wakeWordCount += 1 }
    func playInputComplete() { inputCompleteCount += 1 }
}

// MARK: - MockTelegramService

@MainActor
final class MockTelegramService: TelegramServiceProtocol {
    var isPolling = false
    var isWebhookActive = false
    var onMessage: (@MainActor @Sendable (TelegramUpdate) -> Void)?

    var sentMessages: [(chatId: Int64, text: String)] = []
    var editedMessages: [(chatId: Int64, messageId: Int64, text: String)] = []
    var chatActions: [(chatId: Int64, action: String)] = []
    var sentPhotos: [(chatId: Int64, filePath: String, caption: String?)] = []
    var sentMediaGroups: [(chatId: Int64, items: [TelegramMediaItem])] = []
    var webhookCalls: [(token: String, url: String)] = []
    var nextMessageId: Int64 = 1000
    var sendMessageDelayNanos: UInt64 = 0

    func startPolling(token: String) { isPolling = true }
    func stopPolling() { isPolling = false }

    func startWebhook(token: String, url: String, port: UInt16) async throws {
        isWebhookActive = true
        webhookCalls.append((token: token, url: url))
    }

    func stopWebhook() async throws {
        isWebhookActive = false
    }

    func setWebhook(token: String, url: String) async throws {
        webhookCalls.append((token: token, url: url))
    }

    func deleteWebhook(token: String) async throws {}

    func getWebhookInfo(token: String) async throws -> TelegramWebhookInfo {
        TelegramWebhookInfo(url: "", hasCustomCertificate: false, pendingUpdateCount: 0, lastErrorDate: nil, lastErrorMessage: nil)
    }

    func sendMessage(chatId: Int64, text: String) async throws -> Int64 {
        if sendMessageDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: sendMessageDelayNanos)
        }
        let msgId = nextMessageId
        nextMessageId += 1
        sentMessages.append((chatId: chatId, text: text))
        return msgId
    }

    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws {
        editedMessages.append((chatId: chatId, messageId: messageId, text: text))
    }

    func sendChatAction(chatId: Int64, action: String) async throws {
        chatActions.append((chatId: chatId, action: action))
    }

    func sendPhoto(chatId: Int64, filePath: String, caption: String?) async throws -> Int64 {
        let msgId = nextMessageId
        nextMessageId += 1
        sentPhotos.append((chatId: chatId, filePath: filePath, caption: caption))
        return msgId
    }

    func sendMediaGroup(chatId: Int64, items: [TelegramMediaItem]) async throws {
        sentMediaGroups.append((chatId: chatId, items: items))
    }

    func getMe(token: String) async throws -> TelegramUser {
        TelegramUser(id: 1, isBot: true, firstName: "TestBot", username: "test_bot")
    }
}

// MARK: - MockSupabaseService

@MainActor
final class MockSupabaseService: SupabaseServiceProtocol {
    var isConfigured: Bool = true
    var authState: AuthState = .signedIn(userId: UUID(), email: "test@test.com")

    var registeredDevices: [Device] = []
    var heartbeatCalls: [UUID] = []
    var removedDeviceIds: [UUID] = []

    func configure(url: URL, anonKey: String) {}
    func signInWithApple() async throws {}
    func signInWithEmail(email: String, password: String) async throws {}
    func signUpWithEmail(email: String, password: String) async throws {}
    func signOut() async throws { authState = .signedOut }
    func restoreSession() async {}

    func createWorkspace(name: String) async throws -> Workspace {
        Workspace(name: name, inviteCode: "ABC123", ownerId: authState.userId!)
    }
    func joinWorkspace(inviteCode: String) async throws -> Workspace {
        Workspace(name: "Joined", inviteCode: inviteCode, ownerId: UUID())
    }
    func leaveWorkspace(id: UUID) async throws {}
    func listWorkspaces() async throws -> [Workspace] { [] }
    func regenerateInviteCode(workspaceId: UUID) async throws -> String { "NEW123" }

    func registerDevice(name: String, workspaceIds: [UUID]) async throws -> Device {
        let device = Device(userId: authState.userId!, name: name, workspaceIds: workspaceIds)
        registeredDevices.append(device)
        return device
    }

    func updateDeviceHeartbeat(deviceId: UUID) async throws {
        heartbeatCalls.append(deviceId)
    }

    func updateDeviceWorkspaces(deviceId: UUID, workspaceIds: [UUID]) async throws {
        if let idx = registeredDevices.firstIndex(where: { $0.id == deviceId }) {
            registeredDevices[idx].workspaceIds = workspaceIds
        }
    }

    func listDevices() async throws -> [Device] {
        registeredDevices
    }

    func removeDevice(id: UUID) async throws {
        removedDeviceIds.append(id)
        registeredDevices.removeAll { $0.id == id }
    }

    func syncContext() async throws {}
    func syncConversations() async throws {}

    // G-3 enhanced sync
    var pushedEntities: [(type: SyncEntityType, payload: Data)] = []
    var pullResult: Data?
    var remoteTimestamps: [String: Date] = [:]

    func pushEntities(type: SyncEntityType, payload: Data) async throws {
        pushedEntities.append((type: type, payload: payload))
    }

    func pullEntities(type: SyncEntityType, since: Date?) async throws -> Data? {
        pullResult
    }

    func fetchRemoteTimestamps(type: SyncEntityType) async throws -> [String: Date] {
        remoteTimestamps
    }

    func acquireLock(resource: String, workspaceId: UUID) async throws -> Bool { true }
    func releaseLock(resource: String, workspaceId: UUID) async throws {}
    func refreshLock(resource: String, workspaceId: UUID) async throws {}
}

// MARK: - MockUsageStore

@MainActor
final class MockUsageStore: UsageStoreProtocol {
    var recordedMetrics: [ExchangeMetrics] = []
    var stubbedCost: Double = 0.0

    func record(_ metrics: ExchangeMetrics) async {
        recordedMetrics.append(metrics)
    }

    func dailyRecords(for month: String) async -> [DailyUsageRecord] {
        []
    }

    func monthlySummary(for month: String) async -> MonthlyUsageSummary {
        MonthlyUsageSummary(
            month: month,
            totalExchanges: recordedMetrics.count,
            totalInputTokens: recordedMetrics.compactMap(\.inputTokens).reduce(0, +),
            totalOutputTokens: recordedMetrics.compactMap(\.outputTokens).reduce(0, +),
            totalCostUSD: stubbedCost,
            days: []
        )
    }

    func allMonths() async -> [String] {
        []
    }

    func currentMonthCost() async -> Double {
        stubbedCost
    }
}

// MARK: - MockSpotlightIndexer

@MainActor
final class MockSpotlightIndexer: SpotlightIndexerProtocol {
    var indexedItemCount: Int = 0
    var isRebuilding: Bool = false
    var rebuildProgress: Double = 0.0
    var lastIndexedAt: Date? = nil

    var indexedConversations: [Conversation] = []
    var removedConversationIds: [UUID] = []
    var indexedMemories: [(scope: String, identifier: String, title: String, content: String)] = []
    var removedMemoryIdentifiers: [String] = []
    var rebuildCallCount = 0
    var clearCallCount = 0

    func indexConversation(_ conversation: Conversation) {
        indexedConversations.append(conversation)
        indexedItemCount += 1
        lastIndexedAt = Date()
    }

    func removeConversation(id: UUID) {
        removedConversationIds.append(id)
        indexedItemCount = max(0, indexedItemCount - 1)
    }

    func indexMemory(scope: String, identifier: String, title: String, content: String) {
        indexedMemories.append((scope: scope, identifier: identifier, title: title, content: content))
        indexedItemCount += 1
        lastIndexedAt = Date()
    }

    func removeMemory(identifier: String) {
        removedMemoryIdentifiers.append(identifier)
        indexedItemCount = max(0, indexedItemCount - 1)
    }

    func rebuildAllIndices(conversations: [Conversation], contextService: ContextServiceProtocol, sessionContext: SessionContext) async {
        rebuildCallCount += 1
        indexedItemCount = conversations.count
        lastIndexedAt = Date()
    }

    func clearAllIndices() async {
        clearCallCount += 1
        indexedItemCount = 0
        lastIndexedAt = nil
    }
}

// MARK: - MockDevicePolicyService (J-1)

@MainActor
final class MockDevicePolicyService: DevicePolicyServiceProtocol {
    var registeredDevices: [DeviceInfo] = []
    var currentDevice: DeviceInfo?
    var currentPolicy: DeviceSelectionPolicy = .priorityBased
    var manualDeviceId: UUID?

    var registerCallCount = 0
    var updateActivityCallCount = 0
    var removedIds: [UUID] = []
    var renamedDevices: [(id: UUID, name: String)] = []
    var reorderedIds: [[UUID]] = []

    func registerCurrentDevice() async {
        registerCallCount += 1
    }

    func updateCurrentDeviceActivity() {
        updateActivityCallCount += 1
    }

    func removeDevice(id: UUID) {
        removedIds.append(id)
        registeredDevices.removeAll { $0.id == id }
    }

    func renameDevice(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let finalName = String(trimmed.prefix(64))
        renamedDevices.append((id: id, name: finalName))
        if let idx = registeredDevices.firstIndex(where: { $0.id == id }) {
            registeredDevices[idx].name = finalName
        }
    }

    func reorderPriority(deviceIds: [UUID]) {
        reorderedIds.append(deviceIds)
        for (index, id) in deviceIds.enumerated() {
            if let idx = registeredDevices.firstIndex(where: { $0.id == id }) {
                registeredDevices[idx].priority = index
            }
        }
    }

    func evaluateResponder() -> DeviceNegotiationResult {
        let onlineDevices = registeredDevices.filter { $0.isOnline || $0.isCurrentDevice }
        guard !onlineDevices.isEmpty else { return .noDeviceAvailable }
        if onlineDevices.count == 1 { return .singleDevice }

        switch currentPolicy {
        case .priorityBased:
            let sorted = onlineDevices.sorted { $0.priority < $1.priority }
            guard let winner = sorted.first else { return .noDeviceAvailable }
            return winner.isCurrentDevice ? .thisDevice : .otherDevice(winner)
        case .lastActive:
            let sorted = onlineDevices.sorted { $0.lastSeen > $1.lastSeen }
            guard let winner = sorted.first else { return .noDeviceAvailable }
            return winner.isCurrentDevice ? .thisDevice : .otherDevice(winner)
        case .manual:
            if let manualId = manualDeviceId,
               let device = onlineDevices.first(where: { $0.id == manualId }) {
                return device.isCurrentDevice ? .thisDevice : .otherDevice(device)
            }
            // Fallback to current device if manual device not found online
            if onlineDevices.contains(where: { $0.isCurrentDevice }) {
                return .thisDevice
            }
            return .noDeviceAvailable
        }
    }

    func shouldThisDeviceRespond() -> Bool {
        let result = evaluateResponder()
        switch result {
        case .thisDevice, .singleDevice: return true
        case .otherDevice, .noDeviceAvailable: return false
        }
    }

    func setPolicy(_ policy: DeviceSelectionPolicy) {
        currentPolicy = policy
    }

    func setManualDevice(id: UUID) {
        manualDeviceId = id
    }
}

// MARK: - MockFeedbackStore (I-4)

@MainActor
final class MockFeedbackStore: FeedbackStoreProtocol {
    var entries: [FeedbackEntry] = []
    var addCallCount = 0
    var removeCallCount = 0

    func add(_ entry: FeedbackEntry) {
        entries.removeAll { $0.messageId == entry.messageId }
        entries.append(entry)
        addCallCount += 1
    }

    func remove(messageId: UUID) {
        entries.removeAll { $0.messageId == messageId }
        removeCallCount += 1
    }

    func rating(for messageId: UUID) -> FeedbackRating? {
        entries.first(where: { $0.messageId == messageId })?.rating
    }

    func satisfactionRate(model: String?, agent: String?) -> Double {
        var filtered = entries
        if let model { filtered = filtered.filter { $0.model == model } }
        if let agent { filtered = filtered.filter { $0.agentName == agent } }
        guard !filtered.isEmpty else { return 0.0 }
        let positive = filtered.filter { $0.rating == .positive }.count
        return Double(positive) / Double(filtered.count)
    }

    func recentNegative(limit: Int) -> [FeedbackEntry] {
        let negative = entries.filter { $0.rating == .negative }
        return Array(negative.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func modelBreakdown() -> [ModelSatisfaction] {
        let grouped = Dictionary(grouping: entries) { $0.model }
        return grouped.map { model, entries in
            let positive = entries.filter { $0.rating == .positive }.count
            return ModelSatisfaction(model: model, provider: entries.first?.provider ?? "", totalCount: entries.count, positiveCount: positive)
        }
    }

    func agentBreakdown() -> [AgentSatisfaction] {
        let grouped = Dictionary(grouping: entries) { $0.agentName }
        return grouped.map { agent, entries in
            let positive = entries.filter { $0.rating == .positive }.count
            return AgentSatisfaction(agentName: agent, totalCount: entries.count, positiveCount: positive)
        }
    }

    func categoryDistribution() -> [CategoryCount] {
        let categorized = entries.compactMap { entry -> (FeedbackCategory, FeedbackEntry)? in
            guard entry.rating == .negative, let category = entry.category else { return nil }
            return (category, entry)
        }
        let grouped = Dictionary(grouping: categorized) { $0.0 }
        return grouped.map { cat, pairs in CategoryCount(category: cat, count: pairs.count) }
    }
}

// MARK: - MockTerminalService (K-1)

@MainActor
final class MockTerminalService: TerminalServiceProtocol {
    var sessions: [TerminalSession] = []
    var activeSessionId: UUID?
    var maxSessions: Int = 8
    var onOutputUpdate: ((UUID) -> Void)?
    var onSessionClosed: ((UUID) -> Void)?

    var createSessionCallCount = 0
    var closeSessionCallCount = 0
    var executeCommandCallCount = 0
    var clearOutputCallCount = 0
    var interruptCallCount = 0
    var runCommandCallCount = 0
    var navigateHistoryCallCount = 0

    /// Stubbed result for runCommand
    var stubbedRunResult: (output: String, exitCode: Int32, isError: Bool) = (output: "", exitCode: 0, isError: false)

    /// Stubbed result for navigateHistory
    var stubbedHistoryResult: String? = nil

    @discardableResult
    func createSession(name: String?, shellPath: String?) -> UUID {
        createSessionCallCount += 1
        let id = UUID()
        let session = TerminalSession(
            id: id,
            name: name ?? "터미널 \(sessions.count + 1)",
            isRunning: true
        )
        sessions.append(session)
        activeSessionId = id
        return id
    }

    func closeSession(id: UUID) {
        closeSessionCallCount += 1
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.last?.id
        }
        onSessionClosed?(id)
    }

    func executeCommand(_ command: String, in sessionId: UUID) {
        executeCommandCallCount += 1
    }

    func clearOutput(for sessionId: UUID) {
        clearOutputCallCount += 1
    }

    func interrupt(sessionId: UUID) {
        interruptCallCount += 1
    }

    func navigateHistory(sessionId: UUID, direction: Int) -> String? {
        navigateHistoryCallCount += 1
        return stubbedHistoryResult
    }

    func runCommand(_ command: String, timeout: Int?) async -> (output: String, exitCode: Int32, isError: Bool) {
        runCommandCallCount += 1
        return stubbedRunResult
    }
}

// MARK: - MockInterestDiscoveryService (K-3)

@MainActor
final class MockInterestDiscoveryService: InterestDiscoveryServiceProtocol {
    var profile = InterestProfile()
    var currentAggressiveness: DiscoveryAggressiveness = .passive

    var loadProfileCallCount = 0
    var saveProfileCallCount = 0
    var addInterestCallCount = 0
    var updateInterestCallCount = 0
    var confirmInterestCallCount = 0
    var restoreInterestCallCount = 0
    var removeInterestCallCount = 0
    var analyzeMessageCallCount = 0
    var checkExpirationsCallCount = 0
    var syncToMemoryCallCount = 0

    var lastAnalyzedMessage: String?
    var stubbedSystemPromptAddition: String?

    func loadProfile(userId: String) {
        loadProfileCallCount += 1
    }

    func saveProfile(userId: String) {
        saveProfileCallCount += 1
    }

    func addInterest(_ entry: InterestEntry) {
        addInterestCallCount += 1
        profile.interests.append(entry)
    }

    func updateInterest(id: UUID, topic: String?, tags: [String]?) {
        updateInterestCallCount += 1
        guard let index = profile.interests.firstIndex(where: { $0.id == id }) else { return }
        if let topic { profile.interests[index].topic = topic }
        if let tags { profile.interests[index].tags = tags }
    }

    func confirmInterest(id: UUID) {
        confirmInterestCallCount += 1
        guard let index = profile.interests.firstIndex(where: { $0.id == id }) else { return }
        profile.interests[index].status = .confirmed
    }

    func restoreInterest(id: UUID) {
        restoreInterestCallCount += 1
        guard let index = profile.interests.firstIndex(where: { $0.id == id }) else { return }
        profile.interests[index].status = .confirmed
    }

    func removeInterest(id: UUID) {
        removeInterestCallCount += 1
        profile.interests.removeAll { $0.id == id }
    }

    func analyzeMessage(_ content: String, conversationId: UUID) {
        analyzeMessageCallCount += 1
        lastAnalyzedMessage = content
    }

    func buildDiscoverySystemPromptAddition() -> String? {
        return stubbedSystemPromptAddition
    }

    func checkExpirations() {
        checkExpirationsCallCount += 1
    }

    func syncToMemory(contextService: ContextServiceProtocol, userId: String) {
        syncToMemoryCallCount += 1
    }
}

// MARK: - MockProactiveSuggestionService

@MainActor
final class MockProactiveSuggestionService: ProactiveSuggestionServiceProtocol {
    var currentSuggestion: ProactiveSuggestion?
    var suggestionHistory: [ProactiveSuggestion] = []
    var state: ProactiveSuggestionState = .disabled
    var isPaused: Bool = false
    var toastEvents: [SuggestionToastEvent] = []

    var recordActivityCallCount = 0
    var acceptSuggestionCallCount = 0
    var deferSuggestionCallCount = 0
    var dismissSuggestionTypeCallCount = 0
    var dismissToastCallCount = 0
    var startCallCount = 0
    var stopCallCount = 0

    var lastAcceptedSuggestion: ProactiveSuggestion?
    var lastDeferredSuggestion: ProactiveSuggestion?
    var lastDismissedSuggestion: ProactiveSuggestion?

    func recordActivity() {
        recordActivityCallCount += 1
    }

    func acceptSuggestion(_ suggestion: ProactiveSuggestion) {
        acceptSuggestionCallCount += 1
        lastAcceptedSuggestion = suggestion
        if let index = suggestionHistory.firstIndex(where: { $0.id == suggestion.id }) {
            suggestionHistory[index].status = .accepted
        }
        currentSuggestion = nil
    }

    func deferSuggestion(_ suggestion: ProactiveSuggestion) {
        deferSuggestionCallCount += 1
        lastDeferredSuggestion = suggestion
        if let index = suggestionHistory.firstIndex(where: { $0.id == suggestion.id }) {
            suggestionHistory[index].status = .deferred
        }
        currentSuggestion = nil
    }

    func dismissSuggestionType(_ suggestion: ProactiveSuggestion) {
        dismissSuggestionTypeCallCount += 1
        lastDismissedSuggestion = suggestion
        if let index = suggestionHistory.firstIndex(where: { $0.id == suggestion.id }) {
            suggestionHistory[index].status = .dismissed
        }
        currentSuggestion = nil
    }

    func dismissToast(id: UUID) {
        dismissToastCallCount += 1
        toastEvents.removeAll { $0.id == id }
    }

    func start() {
        startCallCount += 1
        state = .idle
    }

    func stop() {
        stopCallCount += 1
        state = .disabled
    }
}

// MARK: - MockExternalToolSessionManager (K-4)

@MainActor
final class MockExternalToolSessionManager: ExternalToolSessionManagerProtocol {
    var profiles: [ExternalToolProfile] = []
    var sessions: [ExternalToolSession] = []
    var isTmuxAvailable: Bool = true
    var managedRepositories: [ManagedGitRepository] = []

    var loadProfilesCallCount = 0
    var saveProfileCallCount = 0
    var deleteProfileCallCount = 0
    var startSessionCallCount = 0
    var stopSessionCallCount = 0
    var restartSessionCallCount = 0
    var openInTerminalCallCount = 0
    var sendCommandCallCount = 0
    var interruptSessionCallCount = 0
    var checkHealthCallCount = 0
    var checkAllHealthCallCount = 0
    var captureOutputCallCount = 0
    var initializeRepositoryCallCount = 0
    var cloneRepositoryCallCount = 0
    var attachRepositoryCallCount = 0
    var removeManagedRepositoryCallCount = 0
    var setManualRepositoryBindingCallCount = 0
    var selectSessionForOrchestrationCallCount = 0
    var orchestrationGuardPolicyRulesCallCount = 0
    var evaluateOrchestrationExecutionGuardCallCount = 0
    var sessionHistoryMaskingRulesCallCount = 0
    var recordActivityClassificationFeedbackCallCount = 0
    var sessionManagementKPIReportCallCount = 0
    var sessionHistoryIndexStatusCallCount = 0
    var rebuildSessionHistoryIndexCallCount = 0
    var searchSessionHistoryCallCount = 0
    var listUnifiedCodingSessionsCallCount = 0
    var listUnifiedCodingSessionsForObservabilityCallCount = 0

    var lastSavedProfile: ExternalToolProfile?
    var lastSentCommand: String?
    var mockOutputLines: [String] = ["line1", "line2"]
    var mockGitRepositoryInsights: [GitRepositoryInsight] = []
    var mockOrchestrationSelection = OrchestrationSessionSelection(
        action: .none,
        reason: "mock",
        repositoryRoot: nil,
        selectedSession: nil
    )
    var mockOrchestrationDecision = OrchestrationExecutionDecision(
        kind: .allowed,
        policyCode: .t0AllowAll,
        commandClass: .nonDestructive,
        reason: "mock",
        isDestructiveCommand: false
    )
    var mockOrchestrationPolicyRules: [OrchestrationGuardPolicyRule] = []
    var mockSessionHistoryMaskingRules: [SessionHistoryMaskingRule] = []
    var mockSessionManagementKPIReport = SessionManagementKPIReport(
        generatedAt: Date(timeIntervalSince1970: 0),
        repositoryAssignmentSuccessRate: 0,
        dedupCorrectionRate: 0,
        activityClassificationAccuracy: nil,
        sessionSelectionFailureRate: 0,
        historySearchHitRate: 0,
        counters: SessionManagementKPICounters()
    )
    var mockSessionHistoryResults: [SessionHistorySearchResult] = []
    var mockUnifiedCodingSessions: [UnifiedCodingSession] = []
    var mockSessionHistoryIndexStatus = SessionHistoryIndexStatus(
        chunkCount: 0,
        lastIndexedAt: nil,
        latestChunkEndAt: nil
    )

    func loadProfiles() {
        loadProfilesCallCount += 1
    }

    func saveProfile(_ profile: ExternalToolProfile) {
        saveProfileCallCount += 1
        lastSavedProfile = profile
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
    }

    func deleteProfile(id: UUID) {
        deleteProfileCallCount += 1
        profiles.removeAll { $0.id == id }
    }

    func startSession(profileId: UUID) async throws {
        startSessionCallCount += 1
        guard let profile = profiles.first(where: { $0.id == profileId }) else {
            throw ExternalToolError.profileNotFound(profileId)
        }
        let session = ExternalToolSession(
            profileId: profileId,
            tmuxSessionName: "mock-\(profile.name)",
            status: .idle,
            startedAt: Date()
        )
        sessions.append(session)
    }

    func stopSession(id: UUID) async {
        stopSessionCallCount += 1
        if let session = sessions.first(where: { $0.id == id }) {
            session.status = .dead
        }
    }

    func restartSession(id: UUID) async throws {
        restartSessionCallCount += 1
        guard let session = sessions.first(where: { $0.id == id }) else {
            throw ExternalToolError.sessionNotFound(id)
        }
        let profileId = session.profileId
        await stopSession(id: id)
        sessions.removeAll { $0.id == id }
        try await startSession(profileId: profileId)
    }

    func activeSession(for profileId: UUID) -> ExternalToolSession? {
        sessions.first { $0.profileId == profileId && $0.status != .dead }
    }

    func openInTerminal(sessionId: UUID) async throws {
        openInTerminalCallCount += 1
        guard sessions.contains(where: { $0.id == sessionId }) else {
            throw ExternalToolError.sessionNotFound(sessionId)
        }
    }

    func sendCommand(sessionId: UUID, command: String) async throws {
        sendCommandCallCount += 1
        lastSentCommand = command
        guard sessions.contains(where: { $0.id == sessionId }) else {
            throw ExternalToolError.sessionNotFound(sessionId)
        }
    }

    func interruptSession(sessionId: UUID) async throws {
        interruptSessionCallCount += 1
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            throw ExternalToolError.sessionNotFound(sessionId)
        }
        session.status = .unknown
        session.lastActivityText = "^C interrupt"
        session.lastCommandDate = Date()
    }

    func checkHealth(sessionId: UUID) async {
        checkHealthCallCount += 1
    }

    func checkAllHealth() async {
        checkAllHealthCallCount += 1
    }

    func captureOutput(sessionId: UUID, lines: Int) async -> [String] {
        captureOutputCallCount += 1
        return Array(mockOutputLines.prefix(lines))
    }

    func discoverGitRepositoryInsights(searchPaths: [String]?, limit: Int) async -> [GitRepositoryInsight] {
        Array(mockGitRepositoryInsights.prefix(max(1, limit)))
    }

    func initializeRepository(
        path: String,
        defaultBranch: String,
        createReadme: Bool,
        createGitignore: Bool
    ) async throws -> ManagedGitRepository {
        initializeRepositoryCallCount += 1
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let repository = ManagedGitRepository(
            name: URL(fileURLWithPath: normalizedPath).lastPathComponent,
            rootPath: normalizedPath,
            source: .initialized,
            originURL: nil,
            defaultBranch: defaultBranch
        )
        managedRepositories.insert(repository, at: 0)
        return repository
    }

    func cloneRepository(
        remoteURL: String,
        destinationPath: String,
        branch: String?
    ) async throws -> ManagedGitRepository {
        cloneRepositoryCallCount += 1
        let normalizedPath = URL(fileURLWithPath: destinationPath).standardizedFileURL.path
        let repository = ManagedGitRepository(
            name: URL(fileURLWithPath: normalizedPath).lastPathComponent,
            rootPath: normalizedPath,
            source: .cloned,
            originURL: remoteURL,
            defaultBranch: branch ?? "main"
        )
        managedRepositories.insert(repository, at: 0)
        return repository
    }

    func attachRepository(path: String) async throws -> ManagedGitRepository {
        attachRepositoryCallCount += 1
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let repository = ManagedGitRepository(
            name: URL(fileURLWithPath: normalizedPath).lastPathComponent,
            rootPath: normalizedPath,
            source: .attached,
            originURL: nil,
            defaultBranch: "main"
        )
        managedRepositories.insert(repository, at: 0)
        return repository
    }

    func removeManagedRepository(id: UUID, deleteDirectory: Bool) async throws {
        _ = deleteDirectory
        removeManagedRepositoryCallCount += 1
        guard let index = managedRepositories.firstIndex(where: { $0.id == id }) else {
            throw ExternalToolError.repositoryNotFound(id)
        }
        var repository = managedRepositories[index]
        repository.isArchived = true
        repository.updatedAt = Date()
        managedRepositories[index] = repository
    }

    func setManualRepositoryBinding(
        provider: String,
        nativeSessionId: String,
        path: String,
        repositoryRoot: String?
    ) {
        _ = (provider, nativeSessionId, path, repositoryRoot)
        setManualRepositoryBindingCallCount += 1
    }

    func listUnifiedCodingSessions(limit: Int) async -> [UnifiedCodingSession] {
        listUnifiedCodingSessionsCallCount += 1
        return Array(mockUnifiedCodingSessions.prefix(max(1, limit)))
    }

    func listUnifiedCodingSessionsForObservability(limit: Int) async -> [UnifiedCodingSession] {
        listUnifiedCodingSessionsForObservabilityCallCount += 1
        return Array(mockUnifiedCodingSessions.prefix(max(1, limit)))
    }

    func selectSessionForOrchestration(repositoryRoot: String?) async -> OrchestrationSessionSelection {
        _ = repositoryRoot
        selectSessionForOrchestrationCallCount += 1
        return mockOrchestrationSelection
    }

    func orchestrationGuardPolicyRules() -> [OrchestrationGuardPolicyRule] {
        orchestrationGuardPolicyRulesCallCount += 1
        return mockOrchestrationPolicyRules
    }

    func evaluateOrchestrationExecutionGuard(
        tier: CodingSessionControllabilityTier,
        command: String
    ) -> OrchestrationExecutionDecision {
        _ = (tier, command)
        evaluateOrchestrationExecutionGuardCallCount += 1
        return mockOrchestrationDecision
    }

    func sessionHistoryMaskingRules() -> [SessionHistoryMaskingRule] {
        sessionHistoryMaskingRulesCallCount += 1
        return mockSessionHistoryMaskingRules
    }

    func recordActivityClassificationFeedback(
        expected: CodingSessionActivityState,
        observed: CodingSessionActivityState
    ) {
        _ = (expected, observed)
        recordActivityClassificationFeedbackCallCount += 1
    }

    func sessionManagementKPIReport() -> SessionManagementKPIReport {
        sessionManagementKPIReportCallCount += 1
        return mockSessionManagementKPIReport
    }

    func sessionHistoryIndexStatus() -> SessionHistoryIndexStatus {
        sessionHistoryIndexStatusCallCount += 1
        return mockSessionHistoryIndexStatus
    }

    func rebuildSessionHistoryIndex(limit: Int) async -> Int {
        _ = limit
        rebuildSessionHistoryIndexCallCount += 1
        return mockSessionHistoryResults.count
    }

    func searchSessionHistory(query: SessionHistorySearchQuery) async -> [SessionHistorySearchResult] {
        _ = query
        searchSessionHistoryCallCount += 1
        return mockSessionHistoryResults
    }
}

// MARK: - MockTelegramProactiveRelay (K-6)

@MainActor
final class MockTelegramProactiveRelay: TelegramProactiveRelayProtocol {
    var isActive: Bool = false
    var todayTelegramNotificationCount: Int = 0

    var startCallCount = 0
    var stopCallCount = 0
    var sendHeartbeatAlertCallCount = 0
    var sendSuggestionCallCount = 0

    var lastHeartbeatCalendar: String?
    var lastHeartbeatKanban: String?
    var lastHeartbeatReminder: String?
    var lastHeartbeatMemory: String?
    var lastSuggestion: ProactiveSuggestion?

    func start() {
        startCallCount += 1
        isActive = true
    }

    func stop() {
        stopCallCount += 1
        isActive = false
    }

    func sendHeartbeatAlert(
        calendar: String,
        kanban: String,
        reminder: String,
        memory: String?
    ) async {
        sendHeartbeatAlertCallCount += 1
        lastHeartbeatCalendar = calendar
        lastHeartbeatKanban = kanban
        lastHeartbeatReminder = reminder
        lastHeartbeatMemory = memory
        todayTelegramNotificationCount += 1
    }

    func sendSuggestion(_ suggestion: ProactiveSuggestion) async {
        sendSuggestionCallCount += 1
        lastSuggestion = suggestion
        todayTelegramNotificationCount += 1
    }
}

// MARK: - MockRuntimeBridgeService (#281)

@MainActor
final class MockRuntimeBridgeService: RuntimeBridgeProtocol {
    var runtimeState: RuntimeState = .notStarted
    var stubbedHealthResponse: RuntimeHealthResponse?
    var stubbedError: Error?

    var startCallCount = 0
    var stopCallCount = 0
    var healthCallCount = 0

    // Tool dispatch
    var configureToolDispatchCallCount = 0
    var lastToolService: (any BuiltInToolServiceProtocol)?

    // Approval handler
    var setApprovalHandlerCallCount = 0
    var lastApprovalHandler: ToolApprovalHandler?

    // Context snapshot
    var configureContextSnapshotCallCount = 0
    var buildContextSnapshotCallCount = 0
    var resolveContextSnapshotCallCount = 0
    var lastContextService: (any ContextServiceProtocol)?
    var storedSnapshots: [String: ContextSnapshot] = [:]
    var stubbedSnapshotRef: String?

    // Session stubs
    var stubbedOpenResult: SessionOpenResult?
    var stubbedSessionEvents: [BridgeEvent] = []
    var stubbedInterruptResult: SessionInterruptResult?
    var stubbedCloseResult: SessionCloseResult?

    var openCallCount = 0
    var runCallCount = 0
    var interruptCallCount = 0
    var closeCallCount = 0
    var lastRunParams: SessionRunParams?

    func startRuntime() async throws {
        startCallCount += 1
        if let error = stubbedError { throw error }
        runtimeState = .ready
    }

    func stopRuntime() async {
        stopCallCount += 1
        runtimeState = .notStarted
    }

    func health() async throws -> RuntimeHealthResponse {
        healthCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedHealthResponse ?? RuntimeHealthResponse(
            alive: true,
            uptimeMs: 1000,
            activeSessions: 0,
            lastError: nil
        )
    }

    func configureToolDispatch(toolService: any BuiltInToolServiceProtocol) {
        configureToolDispatchCallCount += 1
        lastToolService = toolService
    }

    func setApprovalHandler(_ handler: ToolApprovalHandler?) {
        setApprovalHandlerCallCount += 1
        lastApprovalHandler = handler
    }

    func configureContextSnapshot(contextService: any ContextServiceProtocol) {
        configureContextSnapshotCallCount += 1
        lastContextService = contextService
    }

    func buildContextSnapshot(
        workspaceId: UUID,
        agentId: String,
        userId: String?,
        channelMetadata: String?,
        tokenBudget: Int
    ) -> String? {
        buildContextSnapshotCallCount += 1
        if let ref = stubbedSnapshotRef {
            return ref
        }
        // Build a real snapshot using stored context service if configured
        let ref = "mock-snapshot-\(UUID().uuidString.prefix(8))"
        let snapshot = ContextSnapshot(
            id: ref,
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            userId: userId ?? "",
            layers: ContextLayers(
                systemLayer: ContextLayer(name: .system, content: ""),
                workspaceLayer: ContextLayer(name: .workspace, content: ""),
                agentLayer: ContextLayer(name: .agent, content: ""),
                personalLayer: ContextLayer(name: .personal, content: "")
            ),
            tokenEstimate: 0,
            createdAt: Date(),
            sourceRevision: "mock"
        )
        storedSnapshots[ref] = snapshot
        return ref
    }

    func resolveContextSnapshot(ref: String) -> ContextSnapshot? {
        resolveContextSnapshotCallCount += 1
        return storedSnapshots[ref]
    }

    func openSession(params: SessionOpenParams) async throws -> SessionOpenResult {
        openCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedOpenResult ?? SessionOpenResult(
            sessionId: "mock-session",
            sdkSessionId: "mock-sdk",
            created: true
        )
    }

    func runSession(params: SessionRunParams) -> AsyncThrowingStream<BridgeEvent, Error> {
        runCallCount += 1
        lastRunParams = params
        let events = stubbedSessionEvents
        let error = stubbedError
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func interruptSession(sessionId: String) async throws -> SessionInterruptResult {
        interruptCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedInterruptResult ?? SessionInterruptResult(
            interrupted: true,
            sessionId: sessionId
        )
    }

    func closeSession(sessionId: String) async throws -> SessionCloseResult {
        closeCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedCloseResult ?? SessionCloseResult(
            closed: true,
            sessionId: sessionId
        )
    }
}

// MARK: - MockMemoryPipelineService (#288)

@MainActor
final class MockMemoryPipelineService: MemoryPipelineProtocol {
    var auditLog: [MemoryAuditEvent] = []
    var currentProjections: [MemoryTargetLayer: MemoryProjection] = [:]
    var submittedCandidates: [MemoryCandidate] = []
    var processedCandidates: [MemoryCandidate] = []
    var submitCallCount = 0
    var processCallCount = 0
    var processConversationEndCallCount = 0
    var processToolResultCallCount = 0
    var regenerateProjectionsCallCount = 0
    var stubbedClassification: MemoryClassification?
    var stubbedError: Error?
    var stubbedPipelineResult: MemoryPipelineResult = .empty
    var retryQueueCount = 0

    func submitCandidate(_ candidate: MemoryCandidate) async {
        submitCallCount += 1
        submittedCandidates.append(candidate)
    }

    func classifyCandidate(_ candidate: MemoryCandidate) -> MemoryClassification {
        if let stubbed = stubbedClassification { return stubbed }
        return MemoryClassification(
            candidateId: candidate.id,
            targetLayer: .workspace,
            confidence: 0.5,
            reason: "mock classification"
        )
    }

    func processAndStore(_ candidate: MemoryCandidate) async throws {
        processCallCount += 1
        processedCandidates.append(candidate)
        if let error = stubbedError { throw error }
    }

    func pendingCount() -> Int {
        retryQueueCount
    }

    func processConversationEnd(
        messages: [Message],
        sessionId: String,
        sessionContext: SessionContext,
        settings: AppSettings
    ) async -> MemoryPipelineResult {
        processConversationEndCallCount += 1
        return stubbedPipelineResult
    }

    func processToolResult(
        toolName: String,
        result: String,
        sessionId: String,
        sessionContext: SessionContext,
        settings: AppSettings
    ) async -> MemoryPipelineResult {
        processToolResultCallCount += 1
        return stubbedPipelineResult
    }

    func regenerateProjections(
        workspaceId: UUID,
        agentName: String,
        userId: String?
    ) -> [MemoryTargetLayer: MemoryProjection] {
        regenerateProjectionsCallCount += 1
        return currentProjections
    }
}

// MARK: - MockExecutionLeaseService (#290)

@MainActor
final class MockExecutionLeaseService: ExecutionLeaseServiceProtocol {
    var leases: [UUID: ExecutionLease] = [:]
    var conversationLeaseMap: [String: UUID] = [:]
    var records: [SessionRoutingRecord] = []

    var acquireCallCount = 0
    var renewCallCount = 0
    var releaseCallCount = 0
    var reassignCallCount = 0
    var expireCallCount = 0

    var stubbedError: Error?
    var lastAcquireConversationId: String?
    var lastRequiredCapabilities: DeviceCapabilities?

    private var nextDeviceId = UUID()

    /// Set the device ID that will be assigned on the next acquireLease call.
    func setNextDeviceId(_ id: UUID) {
        nextDeviceId = id
    }

    func acquireLease(
        workspaceId: UUID,
        agentId: String,
        conversationId: String,
        requiredCapabilities: DeviceCapabilities?
    ) async throws -> ExecutionLease {
        acquireCallCount += 1
        lastAcquireConversationId = conversationId
        lastRequiredCapabilities = requiredCapabilities
        if let error = stubbedError { throw error }

        let lease = ExecutionLease(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            assignedDeviceId: nextDeviceId
        )
        leases[lease.leaseId] = lease
        conversationLeaseMap[conversationId] = lease.leaseId

        let record = SessionRoutingRecord(
            leaseId: lease.leaseId,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            toDeviceId: nextDeviceId,
            reason: .initialAssignment
        )
        records.append(record)
        return lease
    }

    func renewLease(leaseId: UUID) throws -> ExecutionLease {
        renewCallCount += 1
        if let error = stubbedError { throw error }
        guard var lease = leases[leaseId] else {
            throw ExecutionLeaseError.leaseNotFound(leaseId)
        }
        lease.expiresAt = Date().addingTimeInterval(ExecutionLease.defaultTTL)
        lease.renewedAt = Date()
        leases[leaseId] = lease
        return lease
    }

    func releaseLease(leaseId: UUID) throws {
        releaseCallCount += 1
        if let error = stubbedError { throw error }
        guard var lease = leases[leaseId] else {
            throw ExecutionLeaseError.leaseNotFound(leaseId)
        }
        lease.status = .released
        leases[leaseId] = lease
        conversationLeaseMap.removeValue(forKey: lease.conversationId)
    }

    func reassignLease(leaseId: UUID, reason: LeaseRoutingReason) throws -> ExecutionLease {
        reassignCallCount += 1
        if let error = stubbedError { throw error }
        guard var oldLease = leases[leaseId] else {
            throw ExecutionLeaseError.leaseNotFound(leaseId)
        }
        let previousDeviceId = oldLease.assignedDeviceId
        oldLease.status = .reassigned
        leases[leaseId] = oldLease

        let newLease = ExecutionLease(
            workspaceId: oldLease.workspaceId,
            agentId: oldLease.agentId,
            conversationId: oldLease.conversationId,
            assignedDeviceId: nextDeviceId,
            previousDeviceId: previousDeviceId
        )
        leases[newLease.leaseId] = newLease
        conversationLeaseMap[oldLease.conversationId] = newLease.leaseId

        let record = SessionRoutingRecord(
            leaseId: newLease.leaseId,
            workspaceId: oldLease.workspaceId,
            agentId: oldLease.agentId,
            conversationId: oldLease.conversationId,
            fromDeviceId: previousDeviceId,
            toDeviceId: nextDeviceId,
            reason: reason
        )
        records.append(record)
        return newLease
    }

    func activeLease(for conversationId: String) -> ExecutionLease? {
        guard let leaseId = conversationLeaseMap[conversationId],
              let lease = leases[leaseId],
              lease.status == .active,
              !lease.isExpired else {
            return nil
        }
        return lease
    }

    func routingHistory(for conversationId: String) -> [SessionRoutingRecord] {
        records.filter { $0.conversationId == conversationId }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func expireStaleLeases() {
        expireCallCount += 1
    }
}

// MARK: - MockCrossDeviceResumeService (#291)

@MainActor
final class MockCrossDeviceResumeService: CrossDeviceResumeServiceProtocol {
    var transferHistory: [DeviceTransferRecord] = []

    var resolveCallCount = 0
    var recordTransferCallCount = 0
    var lastResolveWorkspaceId: String?
    var lastResolveAgentId: String?
    var lastResolveConversationId: String?
    var lastResolveDeviceId: String?

    var stubbedResult: CrossDeviceResumeResult = .created(sessionId: "mock-session", sdkSessionId: "mock-sdk")

    func resolveSession(
        workspaceId: String,
        agentId: String,
        conversationId: String,
        userId: String,
        deviceId: String
    ) async -> CrossDeviceResumeResult {
        resolveCallCount += 1
        lastResolveWorkspaceId = workspaceId
        lastResolveAgentId = agentId
        lastResolveConversationId = conversationId
        lastResolveDeviceId = deviceId
        return stubbedResult
    }

    func recordDeviceTransfer(sessionId: String, fromDeviceId: String, toDeviceId: String) {
        recordTransferCallCount += 1
        let record = DeviceTransferRecord(
            sessionId: sessionId,
            fromDeviceId: fromDeviceId,
            toDeviceId: toDeviceId
        )
        transferHistory.append(record)
    }
}

// MARK: - MockSessionResumeService (#291)

@MainActor
final class MockSessionResumeService: SessionResumeServiceProtocol {
    var resumeCallCount = 0
    var canResumeCallCount = 0
    var normalizeCallCount = 0

    var lastRequest: SessionResumeRequest?
    var stubbedResult: SessionResumeResult = .newSession(
        sessionId: "mock-session",
        deviceId: UUID(),
        reason: .sessionNotFound
    )
    var stubbedCanResume: Bool = false

    func resumeSession(_ request: SessionResumeRequest) async throws -> SessionResumeResult {
        resumeCallCount += 1
        lastRequest = request
        return stubbedResult
    }

    func canResume(conversationId: String) -> Bool {
        canResumeCallCount += 1
        return stubbedCanResume
    }

    func normalizeSessionKey(workspaceId: UUID, agentId: String, conversationId: String) -> String {
        normalizeCallCount += 1
        return "\(workspaceId.uuidString):\(agentId):\(conversationId)"
    }
}

// MARK: - MockTraceContextManager (#292)

@MainActor
final class MockTraceContextManager: TraceContextProtocol {
    var traces: [TraceContext] = []
    var spanStore: [UUID: [TraceSpan]] = [:]

    var startTraceCallCount = 0
    var startSpanCallCount = 0
    var endSpanCallCount = 0

    func startTrace(name: String, metadata: [String: String]) -> TraceContext {
        startTraceCallCount += 1
        let traceId = UUID()
        let rootSpanId = UUID()
        let rootSpan = TraceSpan(id: rootSpanId, traceId: traceId, name: name, attributes: metadata)
        let context = TraceContext(id: traceId, name: name, metadata: metadata, rootSpanId: rootSpanId)
        traces.append(context)
        spanStore[traceId] = [rootSpan]
        return context
    }

    func startSpan(name: String, traceId: UUID, parentSpanId: UUID?, attributes: [String: String]) -> TraceSpan {
        startSpanCallCount += 1
        let span = TraceSpan(traceId: traceId, parentSpanId: parentSpanId, name: name, attributes: attributes)
        spanStore[traceId, default: []].append(span)
        return span
    }

    func endSpan(_ span: TraceSpan, status: TraceSpanStatus) {
        endSpanCallCount += 1
        guard var spans = spanStore[span.traceId],
              let index = spans.firstIndex(where: { $0.id == span.id }) else { return }
        spans[index].endTime = Date()
        spans[index].status = status
        spanStore[span.traceId] = spans
    }

    func spans(for traceId: UUID) -> [TraceSpan] {
        spanStore[traceId] ?? []
    }

    var activeTraces: [TraceContext] {
        traces.filter(\.isActive)
    }

    var allTraces: [TraceContext] {
        traces
    }
}

// MARK: - MockRuntimeMetrics (#292)

@MainActor
final class MockRuntimeMetrics: RuntimeMetricsProtocol {
    var counterValues: [String: Double] = [:]
    var gaugeValues: [String: Double] = [:]
    var histogramValues: [String: [Double]] = [:]

    var incrementCallCount = 0
    var recordHistogramCallCount = 0
    var setGaugeCallCount = 0
    var snapshotCallCount = 0
    var resetCallCount = 0

    func incrementCounter(name: String, labels: [String: String], delta: Double) {
        incrementCallCount += 1
        let key = labels.isEmpty ? name : "\(name)|\(labels.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ","))"
        counterValues[key, default: 0.0] += delta
    }

    func recordHistogram(name: String, labels: [String: String], value: Double) {
        recordHistogramCallCount += 1
        let key = labels.isEmpty ? name : "\(name)|\(labels.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ","))"
        histogramValues[key, default: []].append(value)
    }

    func setGauge(name: String, labels: [String: String], value: Double) {
        setGaugeCallCount += 1
        let key = labels.isEmpty ? name : "\(name)|\(labels.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ","))"
        gaugeValues[key] = value
    }

    func snapshot() -> MetricsSnapshot {
        snapshotCallCount += 1
        return MetricsSnapshot(timestamp: Date(), counters: counterValues, gauges: gaugeValues, histograms: [:])
    }

    func reset() {
        resetCallCount += 1
        counterValues.removeAll()
        gaugeValues.removeAll()
        histogramValues.removeAll()
    }
}

// MARK: - MockStructuredEventLogger (#292)

@MainActor
final class MockStructuredEventLogger: StructuredEventLoggerProtocol {
    var loggedEvents: [StructuredEvent] = []
    var logCallCount = 0
    var exportCallCount = 0

    func log(event: StructuredEvent) {
        logCallCount += 1
        loggedEvents.append(event)
    }

    func events(for traceId: UUID) -> [StructuredEvent] {
        loggedEvents.filter { $0.traceId == traceId }
    }

    func events(for sessionId: String) -> [StructuredEvent] {
        loggedEvents.filter { $0.sessionId == sessionId }
    }

    var allEvents: [StructuredEvent] { loggedEvents }

    func exportJSON(to url: URL) throws {
        exportCallCount += 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(loggedEvents)
        try data.write(to: url)
    }
}

// MARK: - MockSLOEvaluator (#292)

@MainActor
final class MockSLOEvaluator: SLOEvaluatorProtocol {
    var definitions: [SLODefinition] = SLOEvaluator.defaultDefinitions()
    var stubbedResult: SLOResult?
    var evaluateCallCount = 0

    func evaluate(snapshot: MetricsSnapshot) -> SLOResult {
        evaluateCallCount += 1
        if let stubbed = stubbedResult { return stubbed }
        return SLOResult(passed: true, timestamp: Date(), items: [])
    }

    static func defaultDefinitions() -> [SLODefinition] {
        SLOEvaluator.defaultDefinitions()
    }
}

// MARK: - MockRegressionEvaluator (#292)

@MainActor
final class MockRegressionEvaluator: RegressionEvaluatorProtocol {
    var scenarios: [RegressionScenario] = []
    var lastReport: RegressionReport?
    var registerCallCount = 0
    var runAllCallCount = 0
    var runCategoryCallCount = 0
    var stubbedReport: RegressionReport?

    func registerScenario(_ scenario: RegressionScenario) {
        registerCallCount += 1
        scenarios.append(scenario)
    }

    func runAll() async -> RegressionReport {
        runAllCallCount += 1
        let report = stubbedReport ?? RegressionReport(
            results: [],
            categorySummaries: [],
            overallPassRate: 1.0,
            totalDurationMs: 0
        )
        lastReport = report
        return report
    }

    func run(category: RegressionCategory) async -> RegressionReport {
        runCategoryCallCount += 1
        let report = stubbedReport ?? RegressionReport(
            results: [],
            categorySummaries: [],
            overallPassRate: 1.0,
            totalDurationMs: 0
        )
        lastReport = report
        return report
    }
}

// MARK: - MockShadowSubAgentOrchestrator (#280)

@MainActor
final class MockShadowSubAgentOrchestrator: ShadowSubAgentOrchestratorProtocol {
    var config: ShadowSubAgentConfig = .forTesting
    var currentState: ShadowPlannerState = .idle
    var recentTraceEnvelopes: [TraceEnvelope] = []
    var recentDebugBundles: [DebugBundle] = []

    var shouldSpawnCallCount = 0
    var runPlannerCallCount = 0
    var mergeDecisionCallCount = 0
    var updateConfigCallCount = 0
    var resetStateCallCount = 0

    var stubbedShouldSpawn: (spawn: Bool, triggerCode: ShadowTriggerCode?) = (false, nil)
    var stubbedPlannerResult: ShadowPlannerResult = .error("Mock not configured")
    var stubbedMergeResult: ShadowMergeResult?

    func shouldSpawn(context: ShadowTriggerContext) -> (spawn: Bool, triggerCode: ShadowTriggerCode?) {
        shouldSpawnCallCount += 1
        return stubbedShouldSpawn
    }

    func runPlanner(input: ShadowPlannerInput) async -> ShadowPlannerResult {
        runPlannerCallCount += 1
        return stubbedPlannerResult
    }

    func mergeDecision(decision: ShadowDecision, traceEnvelopeId: UUID) -> ShadowMergeResult {
        mergeDecisionCallCount += 1
        if let stubbed = stubbedMergeResult { return stubbed }
        return ShadowMergeResult(
            selectedTool: decision.primaryTool,
            alternatives: decision.alternatives,
            reasonSummary: decision.reasonSummary,
            accepted: decision.isValid && decision.confidence > 0.3,
            traceEnvelopeId: traceEnvelopeId
        )
    }

    func updateConfig(_ newConfig: ShadowSubAgentConfig) {
        updateConfigCallCount += 1
        config = newConfig
    }

    func resetState() {
        resetStateCallCount += 1
        currentState = .idle
    }
}

// MARK: - MockSessionMappingService (#297)

@MainActor
final class MockSessionMappingService: SessionMappingServiceProtocol {
    var mappings: [SessionMapping] = []

    var findActiveCallCount = 0
    var findBySessionIdCallCount = 0
    var insertCallCount = 0
    var updateStatusCallCount = 0
    var updateDeviceIdCallCount = 0
    var touchCallCount = 0
    var pruneStaleCallCount = 0

    var lastInsertedMapping: SessionMapping?
    var lastUpdatedSessionId: String?
    var lastUpdatedStatus: SessionMappingStatus?
    var lastUpdatedDeviceId: String?
    var lastTouchedSessionId: String?
    var lastPruneInterval: TimeInterval?

    func findActive(
        workspaceId: String,
        agentId: String,
        conversationId: String
    ) -> SessionMapping? {
        findActiveCallCount += 1
        return mappings.first { mapping in
            mapping.workspaceId == workspaceId
            && mapping.agentId == agentId
            && mapping.conversationId == conversationId
            && mapping.status == .active
        }
    }

    func findBySessionId(_ sessionId: String) -> SessionMapping? {
        findBySessionIdCallCount += 1
        return mappings.first { $0.sessionId == sessionId }
    }

    func insert(_ mapping: SessionMapping) {
        insertCallCount += 1
        lastInsertedMapping = mapping
        mappings.append(mapping)
    }

    func updateStatus(sessionId: String, status: SessionMappingStatus) {
        updateStatusCallCount += 1
        lastUpdatedSessionId = sessionId
        lastUpdatedStatus = status
        if let idx = mappings.firstIndex(where: { $0.sessionId == sessionId }) {
            mappings[idx].status = status
            mappings[idx].lastActiveAt = Date()
        }
    }

    func updateDeviceId(sessionId: String, newDeviceId: String) {
        updateDeviceIdCallCount += 1
        lastUpdatedDeviceId = newDeviceId
        if let idx = mappings.firstIndex(where: { $0.sessionId == sessionId }) {
            mappings[idx].deviceId = newDeviceId
            mappings[idx].lastActiveAt = Date()
        }
    }

    func touch(sessionId: String) {
        touchCallCount += 1
        lastTouchedSessionId = sessionId
        if let idx = mappings.firstIndex(where: { $0.sessionId == sessionId }) {
            mappings[idx].lastActiveAt = Date()
        }
    }

    var allMappings: [SessionMapping] {
        mappings
    }

    var activeMappings: [SessionMapping] {
        mappings.filter { $0.status == .active }
    }

    func pruneStale(olderThan interval: TimeInterval) {
        pruneStaleCallCount += 1
        lastPruneInterval = interval
        let cutoff = Date().addingTimeInterval(-interval)
        mappings.removeAll { mapping in
            mapping.status != .active && mapping.lastActiveAt < cutoff
        }
    }

    func flushPendingSave() async {
        // No-op for mock -- in-memory only, no pending saves.
    }
}
