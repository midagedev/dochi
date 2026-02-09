import Foundation
import SwiftUI
import Combine
import os

@MainActor
final class DochiViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case listening              // STT 활성
        case processing             // LLM 응답 생성 중
        case executingTool(String)  // MCP 도구 실행 중 (도구 이름)
        case speaking               // TTS 재생 중
    }

    @Published var messages: [Message] = []
    @Published var errorMessage: String?
    @Published var state: State = .idle

    // 대화 히스토리
    @Published var currentConversationId: UUID?
    @Published var conversations: [Conversation] = []

    var settings: AppSettings
    let speechService: SpeechService
    let llmService: LLMService
    let supertonicService: SupertonicService
    let mcpService: MCPServiceProtocol
    let builtInToolService: BuiltInToolService

    // Dependencies
    let contextService: ContextServiceProtocol
    let supabaseService: any SupabaseServiceProtocol
    let deviceService: any DeviceServiceProtocol

    // Tool loop 관련
    @Published var currentToolExecution: String?
    var toolLoopMessages: [Message] = []

    var cancellables = Set<AnyCancellable>()
    // 연속 대화 모드
    @Published var isSessionActive: Bool = false
    @Published var autoEndSession: Bool = true
    var isAskingToEndSession: Bool = false

    // 다중 사용자
    @Published var currentUserId: UUID?
    @Published var currentUserName: String?

    // Modules
    private(set) lazy var sessionManager = SessionManager(viewModel: self)
    private(set) lazy var toolExecutor = ToolExecutor(viewModel: self)
    private(set) lazy var contextAnalyzer = ContextAnalyzer(viewModel: self)
    private(set) lazy var conversationManager = ConversationManager(
        viewModel: self, conversationService: conversationService
    )

    private let conversationService: ConversationServiceProtocol
    private var telegramService: TelegramService?

    /// Concrete accessors for views that need @ObservedObject
    var supabaseServiceForView: SupabaseService? {
        supabaseService as? SupabaseService
    }

    var deviceServiceForView: DeviceService? {
        deviceService as? DeviceService
    }

    var isConnected: Bool {
        supertonicService.state == .ready || state != .idle
    }

    // MARK: - Init

    init(
        settings: AppSettings,
        contextService: ContextServiceProtocol = ContextService(),
        conversationService: ConversationServiceProtocol = ConversationService(),
        mcpService: MCPServiceProtocol? = nil,
        supabaseService: (any SupabaseServiceProtocol)? = nil,
        deviceService: (any DeviceServiceProtocol)? = nil
    ) {
        self.settings = settings
        self.contextService = contextService
        self.conversationService = conversationService
        self.speechService = SpeechService()
        self.llmService = LLMService()
        self.supertonicService = SupertonicService()
        self.mcpService = mcpService ?? MCPService()
        self.builtInToolService = BuiltInToolService()
        let supa = supabaseService ?? SupabaseService(keychainService: settings.keychainServiceRef)
        self.supabaseService = supa
        if let deviceService {
            self.deviceService = deviceService
        } else if let concreteSupa = supa as? SupabaseService {
            self.deviceService = DeviceService(supabaseService: concreteSupa, keychainService: settings.keychainServiceRef)
        } else {
            self.deviceService = DeviceService(supabaseService: SupabaseService(keychainService: settings.keychainServiceRef), keychainService: settings.keychainServiceRef)
        }

        setupCallbacks()
        setupChangeForwarding()
        setupProfileCallback()
        setupTerminationHandler()
        conversationManager.loadAll()

        // Initialize Telegram service
        self.telegramService = TelegramService(
            conversationService: conversationService,
            onConversationsChanged: { [weak self] in
                self?.conversationManager.loadAll()
            }
        )
        setupTelegramBindings()
    }

    private func setupTerminationHandler() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deviceService.stopHeartbeat()
            }
        }
    }

    // MARK: - Wake Word (forwarding to SessionManager)

    func startWakeWordIfNeeded() {
        sessionManager.startWakeWordIfNeeded()
    }

    func stopWakeWord() {
        sessionManager.stopWakeWord()
    }

    // MARK: - Connection

    func connectOnLaunch() {
        Task {
            let granted = await speechService.requestAuthorization()
            if granted {
                self.sessionManager.startWakeWordIfNeeded()
            } else {
                Log.app.warning("마이크/음성인식 권한 거부됨")
            }
        }

        if supertonicService.state == .unloaded {
            connect()
        }

        // Restore cloud session, sync context/conversations, register device, start Realtime
        Task {
            await supabaseService.restoreSession()
            setupCloudServices()
        }

        // Cleanup Realtime on logout, re-setup on login
        supabaseService.onAuthStateChanged = { [weak self] state in
            guard let self else { return }
            switch state {
            case .signedOut:
                self.cleanupCloudServices()
            case .signedIn:
                Task {
                    self.setupCloudServices()
                }
            }
        }
    }

    func toggleConnection() {
        if supertonicService.state == .ready {
            sessionManager.stopWakeWord()
            supertonicService.tearDown()
            state = .idle
        } else if supertonicService.state == .unloaded {
            connect()
        }
    }

    private func setupCloudServices() {
        if let cloudContext = contextService as? CloudContextService {
            Task {
                await cloudContext.pullFromCloud()
            }
            cloudContext.onContextChanged = {
                Log.app.info("Realtime: 컨텍스트 변경 감지")
            }
            cloudContext.subscribeToRealtimeChanges()
        }
        if let cloudConversation = conversationService as? CloudConversationService {
            Task {
                await cloudConversation.pullFromCloud()
                conversationManager.loadAll()
            }
            cloudConversation.onConversationsChanged = { [weak self] in
                self?.conversationManager.loadAll()
            }
            cloudConversation.subscribeToRealtimeChanges()
        }
        if case .signedIn = supabaseService.authState {
            Task {
                do {
                    try await deviceService.registerDevice()
                } catch {
                    Log.cloud.warning("디바이스 등록 실패: \(error, privacy: .public)")
                }
                deviceService.startHeartbeat()
            }
        }
    }

    private func cleanupCloudServices() {
        if let cloudContext = contextService as? CloudContextService {
            cloudContext.unsubscribeFromRealtime()
            cloudContext.onContextChanged = nil
        }
        if let cloudConversation = conversationService as? CloudConversationService {
            cloudConversation.unsubscribeFromRealtime()
            cloudConversation.onConversationsChanged = nil
        }
        deviceService.stopHeartbeat()
        Log.app.info("클라우드 서비스 정리 완료")
    }

    private func setupTelegramBindings() {
        // Start/stop on settings changes
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTelegramService()
            }
            .store(in: &cancellables)
        // Initial
        updateTelegramService()

        // DM handling via LLM with streaming edits
        telegramService?.onDM = { [weak self] event in
            Task { @MainActor in
                await self?.processTelegramDM(chatId: event.chatId, username: event.username, text: event.text)
            }
        }
    }

    private func updateTelegramService() {
        guard let telegramService else { return }
        let enabled = settings.telegramEnabled
        let token = settings.telegramBotToken
        if enabled && !token.isEmpty {
            telegramService.start(token: token)
        } else {
            telegramService.stop()
        }
    }

    // MARK: - Telegram processing

    private func loadOrCreateTelegramConversation(chatId: Int64, username: String?) -> Conversation {
        let userKey = "tg:\(chatId)"
        if let existing = conversationService.list().first(where: { $0.userId == userKey }) {
            return existing
        }
        return Conversation(title: "Telegram DM \(username ?? String(chatId))", messages: [], userId: userKey)
    }

    private func buildSystemPromptForTelegram() -> String {
        let recent = conversationManager.buildRecentSummaries(for: nil, limit: 5)
        return settings.buildInstructions(currentUserName: nil, currentUserId: nil, recentSummaries: recent)
    }

    private func llmApiKey() -> String { settings.apiKey(for: settings.llmProvider) }

    private func llmModels() -> (provider: LLMProvider, model: String) { (settings.llmProvider, settings.llmModel) }

    private func appendAndSave(_ conv: inout Conversation, message: Message) {
        conv.messages.append(message)
        conv.updatedAt = Date()
        conversationService.save(conv)
        conversationManager.loadAll()
    }

    private func sanitizeForTelegram(_ text: String) -> String {
        // Telegram supports Markdown/HTML but we'll send plain text for safety in MVP
        text.replacingOccurrences(of: "\u{0000}", with: "")
    }

    private func streamReply(to chatId: Int64, initialText: String) async -> Int? {
        guard let telegramService else { return nil }
        return await telegramService.sendMessage(chatId: chatId, text: initialText)
    }

    private func updateReply(chatId: Int64, messageId: Int, text: String) async {
        await telegramService?.editMessageText(chatId: chatId, messageId: messageId, text: text)
    }

    func processTelegramDM(chatId: Int64, username: String?, text: String) async {
        var conversation = loadOrCreateTelegramConversation(chatId: chatId, username: username)
        appendAndSave(&conversation, message: Message(role: .user, content: text))

        let (provider, model) = llmModels()
        let apiKey = llmApiKey()
        guard !apiKey.isEmpty else {
            // If no API key, notify user
            let warning = "LLM API 키가 설정되지 않았습니다. 설정에서 키를 추가해주세요."
            _ = await streamReply(to: chatId, initialText: warning)
            return
        }

        let systemPrompt = buildSystemPromptForTelegram()

        // Local LLMService instance to avoid interfering with UI state
        let llm = LLMService()
        var streamedText = ""
        var lastEditTime = Date.distantPast
        let editInterval: TimeInterval = 0.4
        var replyMessageId: Int?

        llm.onSentenceReady = { [weak self] sentence in
            guard let self else { return }
            streamedText += sentence
            let now = Date()
            if replyMessageId == nil {
                Task { @MainActor in
                    replyMessageId = await self.streamReply(to: chatId, initialText: self.sanitizeForTelegram(streamedText))
                }
                lastEditTime = now
            } else if now.timeIntervalSince(lastEditTime) >= editInterval, let msgId = replyMessageId {
                lastEditTime = now
                Task { [weak self] in
                    await self?.updateReply(chatId: chatId, messageId: msgId, text: self?.sanitizeForTelegram(streamedText) ?? streamedText)
                }
            }
        }

        llm.onResponseComplete = { [weak self] finalText in
            guard let self else { return }
            let clean = self.sanitizeForTelegram(finalText.isEmpty ? streamedText : finalText)
            if let msgId = replyMessageId, !clean.isEmpty {
                Task { [weak self] in
                    await self?.updateReply(chatId: chatId, messageId: msgId, text: clean)
                }
            } else if replyMessageId == nil {
                Task { [weak self] in
                    _ = await self?.streamReply(to: chatId, initialText: clean)
                }
            }

            var conv = conversation
            conv.messages.append(Message(role: .assistant, content: clean))
            conv.updatedAt = Date()
            self.conversationService.save(conv)
            self.conversationManager.loadAll()
        }

        // Send request
        llm.sendMessage(
            messages: conversation.messages,
            systemPrompt: systemPrompt,
            provider: provider,
            model: model,
            apiKey: apiKey,
            tools: nil,
            toolResults: nil
        )
    }

    private func connect() {
        let provider = settings.llmProvider
        let apiKey = settings.apiKey(for: provider)
        guard !apiKey.isEmpty else {
            errorMessage = "\(provider.displayName) API 키를 설정해주세요."
            return
        }
        errorMessage = nil
        supertonicService.loadIfNeeded(voice: settings.supertonicVoice)
    }

    // MARK: - Text Input

    func sendMessage(_ text: String) {
        handleQuery(text)
    }

    func handleQuery(_ query: String) {
        speechService.stopWakeWordDetection()

        messages.append(Message(role: .user, content: query))
        state = .processing

        toolLoopMessages = messages

        sendLLMRequest(messages: messages, toolResults: nil)
    }

    func sendLLMRequest(messages: [Message], toolResults: [ToolResult]?) {
        let provider = settings.llmProvider
        let model = settings.llmModel
        let apiKey = settings.apiKey(for: provider)

        let hasProfiles = !contextService.loadProfiles().isEmpty
        builtInToolService.configureUserContext(
            contextService: hasProfiles ? contextService : nil,
            currentUserId: currentUserId
        )

        let recentSummaries = conversationManager.buildRecentSummaries(for: currentUserId, limit: 5)

        let systemPrompt = settings.buildInstructions(
            currentUserName: currentUserName,
            currentUserId: currentUserId,
            recentSummaries: recentSummaries
        )

        builtInToolService.configure(tavilyApiKey: settings.tavilyApiKey, falaiApiKey: settings.falaiApiKey)

        let tools: [[String: Any]]? = {
            var allTools: [MCPToolInfo] = []
            allTools.append(contentsOf: builtInToolService.availableTools)
            allTools.append(contentsOf: mcpService.availableTools)
            return allTools.isEmpty ? nil : allTools.map { $0.asDictionary }
        }()

        llmService.sendMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            provider: provider,
            model: model,
            apiKey: apiKey,
            tools: tools,
            toolResults: toolResults
        )
    }

    // MARK: - Push-to-Talk

    func startListening() {
        switch state {
        case .speaking:
            supertonicService.stopPlayback()
            llmService.cancel()
        case .processing, .executingTool:
            llmService.cancel()
            supertonicService.stopPlayback()
            currentToolExecution = nil
        case .listening:
            return
        case .idle:
            break
        }
        sessionManager.stopWakeWord()
        isSessionActive = true

        sessionManager.assignDefaultUserIfNeeded()

        state = .listening
        speechService.silenceTimeout = settings.sttSilenceTimeout
        speechService.startListening()
    }

    func stopListening() {
        guard state == .listening else { return }
        speechService.stopListening()
    }

    func cancelResponse() {
        llmService.cancel()
        supertonicService.stopPlayback()
        speechService.stopListening()
        currentToolExecution = nil

        if let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) {
            messages.removeSubrange(lastUserIndex...)
        }

        state = .idle
        sessionManager.startWakeWordIfNeeded()
    }

    // MARK: - Conversation (forwarding to ConversationManager)

    func clearConversation() {
        if !messages.isEmpty {
            let sessionMessages = messages
            let sessionUserId = currentUserId
            Task {
                await contextAnalyzer.saveAndAnalyzeConversation(sessionMessages, userId: sessionUserId)
            }
        }
        messages.removeAll()
        currentConversationId = nil
    }

    func loadConversation(_ conversation: Conversation) {
        conversationManager.load(conversation)
    }

    func deleteConversation(id: UUID) {
        conversationManager.delete(id: id)
    }

    func saveConversationWithTitle(_ title: String, summary: String?, userId: UUID?, messages: [Message]) {
        conversationManager.save(title: title, summary: summary, userId: userId, messages: messages)
    }
}
