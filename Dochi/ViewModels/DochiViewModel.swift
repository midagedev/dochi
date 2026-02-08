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
    private let conversationService: ConversationServiceProtocol

    // Tool loop 관련
    @Published var currentToolExecution: String?
    var toolLoopMessages: [Message] = []

    private var cancellables = Set<AnyCancellable>()
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

    var isConnected: Bool {
        supertonicService.state == .ready || state != .idle
    }

    // MARK: - Init

    init(
        settings: AppSettings,
        contextService: ContextServiceProtocol = ContextService(),
        conversationService: ConversationServiceProtocol = ConversationService(),
        mcpService: MCPServiceProtocol? = nil
    ) {
        self.settings = settings
        self.contextService = contextService
        self.conversationService = conversationService
        self.speechService = SpeechService()
        self.llmService = LLMService()
        self.supertonicService = SupertonicService()
        self.mcpService = mcpService ?? MCPService()
        self.builtInToolService = BuiltInToolService()

        setupCallbacks()
        setupChangeForwarding()
        setupProfileCallback()
        loadConversations()
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        speechService.onWakeWordDetected = { [weak self] transcript in
            guard let self else { return }
            self.isSessionActive = true
            self.state = .listening
            self.sessionManager.identifyUserFromTranscript(transcript)
            Log.app.info("세션 시작 (사용자: \(self.currentUserName ?? Constants.Session.unknownUserLabel))")
        }

        speechService.onQueryCaptured = { [weak self] query in
            guard let self else { return }

            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.sessionManager.handleEndSessionResponse(query)
                return
            }

            if self.isSessionActive && self.sessionManager.isEndSessionRequest(query) {
                self.sessionManager.confirmAndEndSession()
                return
            }

            self.handleQuery(query)
        }

        speechService.onListeningCancelled = { [weak self] in
            guard let self, self.state == .listening else { return }
            Log.app.info("리스닝 취소 — 상태 리셋")
            self.state = .idle
            self.sessionManager.startWakeWordIfNeeded()
        }

        speechService.onSilenceTimeout = { [weak self] in
            guard let self, self.isSessionActive else { return }

            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.sessionManager.endSession()
                return
            }

            if self.autoEndSession {
                self.sessionManager.askToEndSession()
            } else {
                self.sessionManager.startContinuousListening()
            }
        }

        llmService.onSentenceReady = { [weak self] sentence in
            guard let self else { return }
            if self.supertonicService.state == .ready || self.supertonicService.state == .synthesizing || self.supertonicService.state == .playing {
                if self.state != .speaking {
                    self.speechService.stopListening()
                    self.speechService.stopWakeWordDetection()
                }
                self.state = .speaking
                self.supertonicService.speed = self.settings.ttsSpeed
                self.supertonicService.diffusionSteps = self.settings.ttsDiffusionSteps
                let cleaned = Self.sanitizeForTTS(sentence)
                guard !cleaned.isEmpty else { return }
                self.supertonicService.enqueueSentence(cleaned, voice: self.settings.supertonicVoice)
            }
        }

        llmService.onResponseComplete = { [weak self] response in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: response))
            self.sessionManager.recoverIfTTSDidNotPlay()
        }

        llmService.onToolCallsReceived = { [weak self] toolCalls in
            guard let self else { return }
            Task {
                await self.toolExecutor.executeToolLoop(toolCalls: toolCalls)
            }
        }

        supertonicService.onSpeakingComplete = { [weak self] in
            guard let self else { return }
            self.state = .idle

            Task {
                // Task 취소 시 에코 방지 딜레이 스킵은 의도된 동작
                try? await Task.sleep(for: .milliseconds(Constants.Timing.echoPreventionDelayMs))
                guard self.state == .idle else { return }

                if self.isSessionActive {
                    self.sessionManager.startContinuousListening()
                } else {
                    self.sessionManager.startWakeWordIfNeeded()
                }
            }
        }

        builtInToolService.onAlarmFired = { [weak self] message in
            guard let self else { return }
            Log.app.info("알람 발동: \(message), 현재 상태: \(String(describing: self.state)), TTS 상태: \(String(describing: self.supertonicService.state))")
            if self.state == .speaking {
                self.supertonicService.stopPlayback()
            }
            if self.state == .listening {
                self.speechService.stopListening()
            }
            self.state = .speaking
            self.supertonicService.speed = self.settings.ttsSpeed
            self.supertonicService.diffusionSteps = self.settings.ttsDiffusionSteps
            self.supertonicService.speak("알람이에요! \(message)", voice: self.settings.supertonicVoice)
        }

        supertonicService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ttsState in
                guard let self, ttsState == .ready, self.state == .idle else { return }
                self.sessionManager.startWakeWordIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func setupChangeForwarding() {
        speechService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        llmService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        supertonicService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func setupProfileCallback() {
        builtInToolService.profileTool.onUserIdentified = { [weak self] profile in
            guard let self else { return }
            self.currentUserId = profile.id
            self.currentUserName = profile.name
            Log.app.info("사용자 설정됨 (tool): \(profile.name)")
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

        let recentSummaries = buildRecentSummaries(for: currentUserId, limit: 5)

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

    func setupLLMCallbacks() {
        llmService.onResponseComplete = { [weak self] response in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: response))
            self.sessionManager.recoverIfTTSDidNotPlay()
        }

        llmService.onToolCallsReceived = { [weak self] toolCalls in
            guard let self else { return }
            Task {
                await self.toolExecutor.executeToolLoop(toolCalls: toolCalls)
            }
        }
    }

    // MARK: - TTS Sanitization

    /// 마크다운 서식 기호를 제거하여 TTS에 적합한 텍스트로 변환
    static func sanitizeForTTS(_ text: String) -> String {
        var s = text

        if s.hasPrefix("```") { return "" }

        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`([^`]*)`"#, with: "$1", options: .regularExpression)

        s = s.replacingOccurrences(of: #"\*{1,3}([^*]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"_{1,3}([^_]+)_{1,3}"#, with: "$1", options: .regularExpression)

        s = s.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[-*+]\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[-*_]{3,}$"#, with: "", options: .regularExpression)

        s = s.replacingOccurrences(of: "*", with: "")
        s = s.replacingOccurrences(of: ":", with: ",")

        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Conversation History

    private func loadConversations() {
        conversations = conversationService.list()
    }

    func loadConversation(_ conversation: Conversation) {
        if !messages.isEmpty {
            let sessionMessages = messages
            let sessionUserId = currentUserId
            Task {
                await contextAnalyzer.saveAndAnalyzeConversation(sessionMessages, userId: sessionUserId)
            }
        }

        currentConversationId = conversation.id
        messages = conversation.messages
    }

    func deleteConversation(id: UUID) {
        conversationService.delete(id: id)
        conversations.removeAll { $0.id == id }

        if currentConversationId == id {
            currentConversationId = nil
            messages.removeAll()
        }
    }

    func saveConversationWithTitle(_ title: String, summary: String?, userId: UUID?, messages: [Message]) {
        let id = currentConversationId ?? UUID()
        let now = Date()

        let conversation = Conversation(
            id: id,
            title: title,
            messages: messages,
            createdAt: conversations.first(where: { $0.id == id })?.createdAt ?? now,
            updatedAt: now,
            userId: userId?.uuidString,
            summary: summary
        )

        conversationService.save(conversation)
        loadConversations()
        Log.app.info("대화 저장됨: \(title)")
    }

    // MARK: - Helpers

    private func buildRecentSummaries(for userId: UUID?, limit: Int) -> String? {
        let allConversations = conversationService.list()
        let userIdString = userId?.uuidString

        let relevant: [Conversation]
        if let userIdString {
            relevant = allConversations.filter { $0.userId == userIdString && $0.summary != nil }
        } else {
            relevant = allConversations.filter { $0.summary != nil }
        }

        let recent = relevant.prefix(limit)
        guard !recent.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"

        return recent.map { conv in
            let date = formatter.string(from: conv.updatedAt)
            return "- [\(date)] \(conv.summary ?? conv.title)"
        }.joined(separator: "\n")
    }
}
