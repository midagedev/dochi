import Foundation
import SwiftUI

@MainActor
@Observable
final class DochiViewModel {
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

    // MARK: - Services

    private let llmService: LLMServiceProtocol
    private let toolService: BuiltInToolServiceProtocol
    private let contextService: ContextServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let speechService: SpeechServiceProtocol
    private var ttsService: TTSServiceProtocol
    private let soundService: SoundServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext

    // MARK: - Internal

    private var processingTask: Task<Void, Never>?
    private var sessionTimeoutTask: Task<Void, Never>?
    private var sentenceChunker = SentenceChunker()
    private static let maxToolLoopIterations = 10
    private static let maxRecentMessages = 30
    private static let sessionEndingTimeout: TimeInterval = 10

    // MARK: - Computed

    var isVoiceMode: Bool {
        settings.currentInteractionMode == .voiceAndText
    }

    var isMicAuthorized: Bool {
        speechService.isAuthorized
    }

    // MARK: - Init

    init(
        llmService: LLMServiceProtocol,
        toolService: BuiltInToolServiceProtocol,
        contextService: ContextServiceProtocol,
        conversationService: ConversationServiceProtocol,
        keychainService: KeychainServiceProtocol,
        speechService: SpeechServiceProtocol,
        ttsService: TTSServiceProtocol,
        soundService: SoundServiceProtocol,
        settings: AppSettings,
        sessionContext: SessionContext
    ) {
        self.llmService = llmService
        self.toolService = toolService
        self.contextService = contextService
        self.conversationService = conversationService
        self.keychainService = keychainService
        self.speechService = speechService
        self.ttsService = ttsService
        self.soundService = soundService
        self.settings = settings
        self.sessionContext = sessionContext

        // Wire TTS completion callback
        self.ttsService.onComplete = { [weak self] in
            self?.handleTTSComplete()
        }

        Log.app.info("DochiViewModel initialized")
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
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard interactionState == .idle else {
            Log.app.warning("Cannot send message: not idle (current: \(String(describing: self.interactionState)))")
            return
        }

        // Barge-in: if TTS is playing in text mode, stop it
        ttsService.stopAndClear()

        inputText = ""
        errorMessage = nil

        ensureConversation()
        appendUserMessage(text)

        transition(to: .processing)
        processingSubState = .streaming

        processingTask = Task {
            await processLLMLoop()
        }
    }

    func cancelRequest() {
        processingTask?.cancel()
        processingTask = nil
        llmService.cancel()
        ttsService.stopAndClear()
        sentenceChunker = SentenceChunker()

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

    func newConversation() {
        currentConversation = nil
        streamingText = ""
        errorMessage = nil
        toolService.resetRegistry()
    }

    func loadConversations() {
        conversations = conversationService.list()
        Log.app.debug("Loaded \(self.conversations.count) conversations")
    }

    func selectConversation(id: UUID) {
        guard interactionState == .idle else { return }
        if let conversation = conversationService.load(id: id) {
            currentConversation = conversation
            streamingText = ""
            errorMessage = nil
            toolService.resetRegistry()
            Log.app.info("Selected conversation: \(id)")
        }
    }

    func deleteConversation(id: UUID) {
        conversationService.delete(id: id)
        if currentConversation?.id == id {
            currentConversation = nil
            streamingText = ""
        }
        loadConversations()
        Log.app.info("Deleted conversation: \(id)")
    }

    // MARK: - Voice Actions

    /// Start listening via STT (triggered by wake word or UI button).
    func startListening() {
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
                    errorMessage = "마이크 권한이 필요합니다. 시스템 설정에서 허용해주세요."
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
        soundService.playInputComplete()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.stt.warning("Empty STT result, returning to idle")
            transition(to: .idle)
            // Check if we should prompt for retry
            if sessionState == .active {
                enqueueTTS("잘 못 들었어요, 다시 말해주세요.")
                return
            }
            return
        }

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

        appendUserMessage(cleanedText)

        transition(to: .processing)
        processingSubState = .streaming

        processingTask = Task {
            await processLLMLoop()
        }
    }

    private func handleSpeechError(_ error: Error) {
        partialTranscript = ""
        Log.stt.error("Speech error: \(error.localizedDescription)")

        if interactionState == .listening {
            transition(to: .idle)
        }

        if sessionState == .active {
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

    // MARK: - LLM Processing Loop

    private func processLLMLoop() async {
        guard var conversation = currentConversation else { return }

        let provider = settings.currentProvider
        let model = settings.llmModel

        // Check API key before calling LLM
        guard let apiKey = keychainService.load(account: provider.keychainAccount), !apiKey.isEmpty else {
            handleError(LLMError.noAPIKey)
            return
        }

        // Compose context
        let systemPrompt = composeSystemPrompt()

        // Get available tool schemas
        let agentPermissions = currentAgentPermissions()
        let tools = toolService.availableToolSchemas(for: agentPermissions)

        // Reset sentence chunker for TTS streaming
        sentenceChunker = SentenceChunker()

        var toolLoopCount = 0

        while toolLoopCount <= Self.maxToolLoopIterations + 1 {
            guard !Task.isCancelled else { return }

            // Prepare messages (trim to recent + respect context size)
            let messages = prepareMessages(from: conversation)

            processingSubState = .streaming
            streamingText = ""

            let response: LLMResponse
            do {
                response = try await llmService.send(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    model: model,
                    provider: provider,
                    apiKey: apiKey,
                    tools: tools.isEmpty ? nil : tools,
                    onPartial: { [weak self] partial in
                        guard let self else { return }
                        self.streamingText += partial

                        // Feed TTS sentence chunker for voice mode
                        if self.isVoiceMode {
                            let sentences = self.sentenceChunker.append(partial)
                            for sentence in sentences {
                                if self.interactionState == .processing {
                                    self.processingSubState = .complete
                                    self.transition(to: .speaking)
                                }
                                self.ttsService.enqueueSentence(sentence)
                            }
                        }
                    }
                )
            } catch {
                if Task.isCancelled { return }
                handleError(error)
                return
            }

            guard !Task.isCancelled else { return }

            switch response {
            case .text(let text):
                let finalText = text.isEmpty ? streamingText : text
                if finalText.isEmpty {
                    handleError(LLMError.emptyResponse)
                    return
                }
                streamingText = ""
                appendAssistantMessage(finalText)
                conversation = currentConversation!
                saveConversation()

                // Flush remaining TTS text
                if isVoiceMode, let remaining = sentenceChunker.flush() {
                    if interactionState == .processing {
                        processingSubState = .complete
                        transition(to: .speaking)
                    }
                    ttsService.enqueueSentence(remaining)
                }

                processingSubState = .complete

                if isVoiceMode && ttsService.isSpeaking {
                    // TTS is playing — stay in speaking, handleTTSComplete will transition
                    if interactionState != .speaking {
                        transition(to: .speaking)
                    }
                } else if isVoiceMode && sessionState == .active {
                    // No TTS to play, go directly to listening
                    transition(to: .idle)
                    startListening()
                } else {
                    transition(to: .idle)
                }
                return

            case .partial(let text):
                streamingText = text

            case .toolCalls(let toolCalls):
                toolLoopCount += 1

                let assistantMsg = Message(
                    role: .assistant,
                    content: streamingText,
                    toolCalls: toolCalls
                )
                currentConversation?.messages.append(assistantMsg)
                conversation = currentConversation!
                streamingText = ""

                // Check tool loop limit
                if toolLoopCount > Self.maxToolLoopIterations {
                    let errorResult = ToolResult(
                        toolCallId: toolCalls.first?.id ?? "",
                        content: "도구 호출이 너무 많습니다 (최대 \(Self.maxToolLoopIterations)회). 최종 응답을 생성해주세요.",
                        isError: true
                    )
                    appendToolResultMessage(errorResult)
                    conversation = currentConversation!
                    continue
                }

                // Execute tools
                processingSubState = .toolCalling
                for codableCall in toolCalls {
                    guard !Task.isCancelled else { return }
                    currentToolName = codableCall.name
                    Log.tool.info("Executing tool: \(codableCall.name) (loop \(toolLoopCount))")

                    let call = ToolCall(
                        id: codableCall.id,
                        name: codableCall.name,
                        arguments: codableCall.arguments
                    )

                    let result = await toolService.execute(
                        name: call.name,
                        arguments: call.arguments
                    )

                    let toolResult = ToolResult(
                        toolCallId: call.id,
                        content: result.content,
                        isError: result.isError
                    )
                    appendToolResultMessage(toolResult)

                    if result.isError {
                        processingSubState = .toolError
                        Log.tool.warning("Tool error: \(call.name) — \(result.content)")
                    }
                }

                currentToolName = nil
                conversation = currentConversation!
            }
        }

        // Exceeded max loops
        Log.tool.warning("Tool loop exceeded max iterations")
        processingSubState = .complete
        if !streamingText.isEmpty {
            appendAssistantMessage(streamingText)
            streamingText = ""
        }
        saveConversation()
        transition(to: .idle)
    }

    // MARK: - Context Composition

    private func composeSystemPrompt() -> String {
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

        // 4. Workspace memory
        if let wsMem = contextService.loadWorkspaceMemory(workspaceId: wsId), !wsMem.isEmpty {
            parts.append("## 워크스페이스 메모리\n\(wsMem)")
        }

        // 5. Agent memory
        if let agentMem = contextService.loadAgentMemory(workspaceId: wsId, agentName: agentName), !agentMem.isEmpty {
            parts.append("## 에이전트 메모리\n\(agentMem)")
        }

        // 6. Personal memory
        if let userId = sessionContext.currentUserId,
           let personalMem = contextService.loadUserMemory(userId: userId), !personalMem.isEmpty {
            parts.append("## 개인 메모리\n\(personalMem)")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Message Preparation

    private func prepareMessages(from conversation: Conversation) -> [Message] {
        var messages = conversation.messages

        if messages.count > Self.maxRecentMessages {
            messages = Array(messages.suffix(Self.maxRecentMessages))
        }

        let maxSize = settings.contextMaxSize
        var totalChars = messages.reduce(0) { $0 + $1.content.count }

        while totalChars > maxSize && messages.count > 5 {
            let removed = messages.removeFirst()
            totalChars -= removed.content.count
        }

        return messages
    }

    // MARK: - API Key Management

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

    // MARK: - Agent Permissions

    private func currentAgentPermissions() -> [String] {
        let agentName = settings.activeAgentName
        let wsId = sessionContext.workspaceId
        if let config = contextService.loadAgentConfig(workspaceId: wsId, agentName: agentName) {
            return config.effectivePermissions
        }
        return ["safe"]
    }

    // MARK: - Conversation Management

    private func ensureConversation() {
        if currentConversation == nil {
            currentConversation = Conversation(userId: sessionContext.currentUserId)
        }
    }

    private func appendUserMessage(_ text: String) {
        currentConversation?.messages.append(Message(role: .user, content: text))
        currentConversation?.updatedAt = Date()
    }

    private func appendAssistantMessage(_ text: String) {
        currentConversation?.messages.append(Message(role: .assistant, content: text))
        currentConversation?.updatedAt = Date()
    }

    private func appendToolResultMessage(_ result: ToolResult) {
        currentConversation?.messages.append(
            Message(role: .tool, content: result.content, toolCallId: result.toolCallId)
        )
        currentConversation?.updatedAt = Date()
    }

    private func saveConversation() {
        guard let conversation = currentConversation else { return }

        if conversation.title == "새 대화",
           let firstUser = conversation.messages.first(where: { $0.role == .user }) {
            let title = String(firstUser.content.prefix(40))
            currentConversation?.title = title.count < firstUser.content.count ? title + "…" : title
        }

        conversationService.save(conversation: currentConversation!)
        loadConversations()
        Log.app.debug("Conversation saved: \(conversation.id)")
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        let llmError = error as? LLMError

        switch llmError {
        case .noAPIKey:
            errorMessage = "API 키가 설정되지 않았습니다. 설정에서 \(settings.currentProvider.displayName) API 키를 등록해주세요."
        case .authenticationFailed:
            errorMessage = "API 키를 확인해주세요. \(settings.currentProvider.displayName) 키가 유효하지 않습니다."
        case .timeout:
            errorMessage = "응답 시간이 초과되었습니다. 다른 모델로 변경하거나 잠시 후 다시 시도해주세요."
        case .emptyResponse:
            errorMessage = "응답을 생성하지 못했습니다. 다시 시도해주세요."
        case .rateLimited:
            errorMessage = "요청 한도를 초과했습니다. 잠시 후 다시 시도해주세요."
        case .cancelled:
            break
        case .modelNotFound(let model):
            errorMessage = "모델 '\(model)'을(를) 찾을 수 없습니다. 설정에서 모델을 변경해주세요."
        case .networkError(let msg):
            errorMessage = "네트워크 오류: \(msg)"
        case .serverError(let code, let msg):
            errorMessage = "서버 오류 (\(code)): \(msg)"
        case .invalidResponse(let msg):
            errorMessage = "잘못된 응답: \(msg)"
        case .none:
            errorMessage = "오류가 발생했습니다: \(error.localizedDescription)"
        }

        if case .cancelled = llmError {
            // skip logging
        } else {
            Log.app.error("LLM error: \(error.localizedDescription)")
        }

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
