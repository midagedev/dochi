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
    // UI overlays
    @Published var showCommandPalette: Bool = false
    @Published var showSettingsSheet: Bool = false

    // Modules
    private(set) lazy var sessionManager = SessionManager(viewModel: self)
    private(set) lazy var toolExecutor = ToolExecutor(viewModel: self)
    private(set) lazy var contextAnalyzer = ContextAnalyzer(viewModel: self)
    private(set) lazy var conversationManager = ConversationManager(
        viewModel: self, conversationService: conversationService
    )

    let conversationService: ConversationServiceProtocol
    var telegramService: TelegramService?
    // Controllers
    private(set) lazy var cloud = CloudController()
    private(set) lazy var integrations = IntegrationsController()
    private(set) lazy var flow = ConversationFlowController()

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

        // Inject settings to built-in tools that need it
        builtInToolService.configureSettings(settings)
        builtInToolService.configureConversations(conversationService)
        builtInToolService.configureSupabase(supa)

        // Initialize Telegram service
        self.telegramService = TelegramService(
            conversationService: conversationService,
            onConversationsChanged: { [weak self] in
                self?.conversationManager.loadAll()
            }
        )
        integrations.setupTelegramBindings(self)
        // Provide Telegram to built-in tools
        if let telegramService { builtInToolService.configureTelegram(telegramService) }
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

    private func setupCloudServices() { cloud.setupCloudServices(self) }

    private func cleanupCloudServices() { cloud.cleanupCloudServices(self) }

    private func setupTelegramBindings() { integrations.setupTelegramBindings(self) }

    private func updateTelegramService() { integrations.updateTelegramService(self) }

    // MARK: - Telegram processing

    private func llmApiKey() -> String { settings.apiKey(for: settings.llmProvider) }

    private func llmModels() -> (provider: LLMProvider, model: String) { (settings.llmProvider, settings.llmModel) }

    private func appendAndSave(_ conv: inout Conversation, message: Message) {
        conv.messages.append(message)
        conv.updatedAt = Date()
        conversationService.save(conv)
        conversationManager.loadAll()
    }

    private func sanitizeForTelegram(_ text: String) -> String { text.replacingOccurrences(of: "\u{0000}", with: "") }

    private func streamReply(to chatId: Int64, initialText: String) async -> Int? { await telegramService?.sendMessage(chatId: chatId, text: initialText) }

    private func updateReply(chatId: Int64, messageId: Int, text: String) async { await telegramService?.editMessageText(chatId: chatId, messageId: messageId, text: text) }

    func processTelegramDM(chatId: Int64, username: String?, text: String) async { await integrations.processTelegramDM(self, chatId: chatId, username: username, text: text) }

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

    func sendLLMRequest(messages: [Message], toolResults: [ToolResult]?) { flow.sendLLMRequest(self, messages: messages, toolResults: toolResults) }

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
        // Auto-reset enabled admin/advanced tools at session end to save tokens
        if settings.toolsRegistryAutoReset {
            builtInToolService.setEnabledToolNames(nil)
        }
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
