import Foundation
@testable import Dochi

// MARK: - MockLLMService

@MainActor
final class MockLLMService: LLMServiceProtocol {
    var lastMetrics: ExchangeMetrics?
    var sendCallCount = 0
    var lastMessages: [Message]?
    var lastSystemPrompt: String?
    var lastModel: String?
    var lastProvider: LLMProvider?
    var lastAPIKey: String?
    var stubbedResponse: LLMResponse = .text("Mock response")
    var stubbedError: Error?
    var cancelCallCount = 0

    func send(
        messages: [Message],
        systemPrompt: String,
        model: String,
        provider: LLMProvider,
        apiKey: String,
        tools: [[String: Any]]?,
        onPartial: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> LLMResponse {
        sendCallCount += 1
        lastMessages = messages
        lastSystemPrompt = systemPrompt
        lastModel = model
        lastProvider = provider
        lastAPIKey = apiKey
        if let error = stubbedError { throw error }

        lastMetrics = ExchangeMetrics(
            provider: provider.rawValue,
            model: model,
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: 150,
            firstByteLatency: 0.5,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false
        )

        return stubbedResponse
    }

    func cancel() {
        cancelCallCount += 1
    }
}

// MARK: - MockContextService

@MainActor
final class MockContextService: ContextServiceProtocol {
    var baseSystemPrompt: String?
    var profiles: [UserProfile] = []
    var userMemory: [String: String] = [:]
    var workspaceMemory: [UUID: String] = [:]
    var agentPersonas: [String: String] = [:]
    var agentMemories: [String: String] = [:]
    var agentConfigs: [String: AgentConfig] = [:]
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
    var stubbedSchemas: [[String: Any]] = []
    var stubbedResult = ToolResult(toolCallId: "mock", content: "ok")
    var executeCallCount = 0
    var lastExecutedName: String?
    var lastArguments: [String: Any]?
    var enabledNames: [String] = []
    var resetCallCount = 0

    var nonBaselineToolSummaries: [(name: String, description: String, category: ToolCategory)] = []
    var allToolInfos: [ToolInfo] = []

    func availableToolSchemas(for permissions: [String]) -> [[String: Any]] {
        stubbedSchemas
    }

    func execute(name: String, arguments: [String: Any]) async -> ToolResult {
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

// MARK: - MockSlackService

@MainActor
final class MockSlackService: SlackServiceProtocol {
    var isConnected = false
    var onMessage: (@MainActor @Sendable (SlackMessage) -> Void)?

    var connectCalls: [(botToken: String, appToken: String)] = []
    var sentMessages: [(channelId: String, text: String, threadTs: String?)] = []
    var updatedMessages: [(channelId: String, ts: String, text: String)] = []
    var typingCalls: [String] = []
    var nextMessageTs: Int = 1000

    func connect(botToken: String, appToken: String) async throws {
        connectCalls.append((botToken: botToken, appToken: appToken))
        isConnected = true
    }

    func disconnect() {
        isConnected = false
    }

    func sendMessage(channelId: String, text: String, threadTs: String?) async throws -> String {
        let ts = "\(nextMessageTs)"
        nextMessageTs += 1
        sentMessages.append((channelId: channelId, text: text, threadTs: threadTs))
        return ts
    }

    func updateMessage(channelId: String, ts: String, text: String) async throws {
        updatedMessages.append((channelId: channelId, ts: ts, text: text))
    }

    func sendTyping(channelId: String) async throws {
        typingCalls.append(channelId)
    }

    func authTest(botToken: String) async throws -> SlackUser {
        SlackUser(id: "U123BOT", name: "test-bot", isBot: true)
    }
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
