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
            if let cloudContext = contextService as? CloudContextService {
                await cloudContext.pullFromCloud()
                cloudContext.onContextChanged = { [weak self] in
                    // Context 변경 시 별도 처리 없이 다음 LLM 요청에 반영됨
                    Log.app.info("Realtime: 컨텍스트 변경 감지")
                    _ = self  // retain check
                }
                cloudContext.subscribeToRealtimeChanges()
            }
            if let cloudConversation = conversationService as? CloudConversationService {
                await cloudConversation.pullFromCloud()
                conversationManager.loadAll()
                cloudConversation.onConversationsChanged = { [weak self] in
                    self?.conversationManager.loadAll()
                }
                cloudConversation.subscribeToRealtimeChanges()
            }
            if case .signedIn = supabaseService.authState {
                do {
                    try await deviceService.registerDevice()
                } catch {
                    Log.cloud.warning("디바이스 등록 실패: \(error, privacy: .public)")
                }
                deviceService.startHeartbeat()
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
