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
