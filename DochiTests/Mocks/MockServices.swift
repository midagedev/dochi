import Foundation
@testable import Dochi

// MARK: - MockLLMService

@MainActor
final class MockLLMService: LLMServiceProtocol {
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
    var stubbedSchemas: [[String: Any]] = []
    var stubbedResult = ToolResult(toolCallId: "mock", content: "ok")
    var executeCallCount = 0
    var lastExecutedName: String?
    var lastArguments: [String: Any]?
    var enabledNames: [String] = []
    var resetCallCount = 0

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
