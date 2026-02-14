import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
    var pendingToolConfirmation: ToolConfirmation?
    var userProfiles: [UserProfile] = []
    var currentUserName: String = "(사용자 없음)"

    // MARK: - Conversation Organization
    var conversationTags: [ConversationTag] = []
    var conversationFolders: [ConversationFolder] = []
    var isMultiSelectMode: Bool = false
    var selectedConversationIds: Set<UUID> = []

    // MARK: - Services

    private let llmService: LLMServiceProtocol
    private var toolService: BuiltInToolServiceProtocol
    var allToolInfos: [ToolInfo] { toolService.allToolInfos }
    let contextService: ContextServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let speechService: SpeechServiceProtocol
    private var ttsService: TTSServiceProtocol
    private let soundService: SoundServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    let metricsCollector: MetricsCollector

    // MARK: - Internal

    private var processingTask: Task<Void, Never>?
    private var sessionTimeoutTask: Task<Void, Never>?
    private var confirmationTimeoutTask: Task<Void, Never>?
    private var sentenceChunker = SentenceChunker()
    private var llmStreamActive = false
    private static let maxToolLoopIterations = 10
    private static let maxRecentMessages = 30
    private static let sessionEndingTimeout: TimeInterval = 10
    private static let toolConfirmationTimeout: TimeInterval = 30
    private static let compressionModel = "gpt-4o-mini"
    private static let compressionSummaryPrompt = "다음 메모리를 핵심 사실만 보존하여 50% 이하로 요약하세요. 라인 단위(`- ...`) 형식 유지."

    // MARK: - Computed

    var isVoiceMode: Bool {
        settings.currentInteractionMode == .voiceAndText
    }

    var isMicAuthorized: Bool {
        speechService.isAuthorized
    }

    /// Token usage from the most recent LLM exchange (input tokens sent).
    var lastInputTokens: Int? {
        llmService.lastMetrics?.inputTokens
    }

    /// Token usage from the most recent LLM exchange (output tokens received).
    var lastOutputTokens: Int? {
        llmService.lastMetrics?.outputTokens
    }

    /// Context window size (tokens) for the currently selected model.
    var contextWindowTokens: Int {
        settings.currentProvider.contextWindowTokens(for: settings.llmModel)
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
        sessionContext: SessionContext,
        metricsCollector: MetricsCollector = MetricsCollector()
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
        self.metricsCollector = metricsCollector

        // Wire TTS completion callback
        self.ttsService.onComplete = { [weak self] in
            self?.handleTTSComplete()
        }

        // Wire sensitive tool confirmation handler
        self.toolService.confirmationHandler = { [weak self] toolName, toolDescription in
            guard let self else { return false }
            return await self.requestToolConfirmation(toolName: toolName, toolDescription: toolDescription)
        }

        // Load user profiles
        reloadProfiles()

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
        llmStreamActive = true

        processingTask = Task {
            await processLLMLoop()
        }
    }

    func cancelRequest() {
        processingTask?.cancel()
        processingTask = nil
        llmService.cancel()
        llmStreamActive = false
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
        sessionContext.currentUserId = profile.id.uuidString
        settings.defaultUserId = profile.id.uuidString
        currentUserName = profile.name
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

    // MARK: - Tool Confirmation

    /// Show confirmation UI for a sensitive tool and wait for user response.
    private func requestToolConfirmation(toolName: String, toolDescription: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            self.pendingToolConfirmation = ToolConfirmation(
                toolName: toolName,
                toolDescription: toolDescription,
                continuation: continuation
            )

            // Start 30s timeout — auto-deny if no response
            self.confirmationTimeoutTask?.cancel()
            self.confirmationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.toolConfirmationTimeout))
                guard !Task.isCancelled else { return }
                if self?.pendingToolConfirmation?.toolName == toolName {
                    Log.tool.warning("Tool confirmation timed out: \(toolName)")
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

        // LLM is still streaming — TTS queue just temporarily emptied.
        // More sentences will arrive; don't transition yet.
        if llmStreamActive { return }

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

    // MARK: - Telegram Message Handling

    func handleTelegramMessage(_ update: TelegramUpdate) async {
        Log.telegram.info("Processing Telegram message from \(update.senderUsername ?? "unknown")")

        // Find or create a persistent conversation for this chat
        var conversation = findOrCreateTelegramConversation(
            chatId: update.chatId,
            username: update.senderUsername
        )

        // Append user message
        let userMessage = Message(role: .user, content: update.text)
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

        let systemPrompt = composeSystemPrompt()
        let messages = prepareMessages(from: conversation)

        // Resolve model (agent config applies to Telegram too)
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let telegramAgentConfig = contextService.loadAgentConfig(
            workspaceId: sessionContext.workspaceId,
            agentName: settings.activeAgentName
        )
        guard let model = router.resolvePrimary(agentConfig: telegramAgentConfig) else {
            Log.telegram.error("No API key configured for Telegram response")
            return
        }

        let useStreaming = settings.telegramStreamReplies

        do {
            var accumulatedText = ""
            var streamMessageId: Int64?
            var lastEditLength = 0

            // For non-streaming mode, send typing indicator
            if !useStreaming, let tg = getTelegramService() {
                try? await tg.sendChatAction(chatId: update.chatId, action: "typing")
            }

            let onPartial: @MainActor @Sendable (String) -> Void = { [weak self] partial in
                accumulatedText += partial

                guard useStreaming, let self, let tg = self.getTelegramService() else { return }

                // Throttle edits: only update every 50+ chars or first chunk
                let currentLength = accumulatedText.count
                guard currentLength - lastEditLength >= 50 || streamMessageId == nil else { return }

                let textSnapshot = accumulatedText + " ▍"
                lastEditLength = currentLength

                Task { @MainActor in
                    do {
                        if let msgId = streamMessageId {
                            try await tg.editMessage(chatId: update.chatId, messageId: msgId, text: textSnapshot)
                        } else {
                            streamMessageId = try await tg.sendMessage(chatId: update.chatId, text: textSnapshot)
                        }
                    } catch {
                        Log.telegram.debug("Streaming edit skipped: \(error.localizedDescription)")
                    }
                }
            }

            let response = try await llmService.send(
                messages: messages,
                systemPrompt: systemPrompt,
                model: model.model,
                provider: model.provider,
                apiKey: model.apiKey,
                tools: nil,
                onPartial: onPartial
            )

            let finalText: String
            switch response {
            case .text(let text):
                finalText = text.isEmpty ? accumulatedText : text
            default:
                finalText = accumulatedText
            }

            guard !finalText.isEmpty else {
                Log.telegram.warning("Empty response for Telegram message")
                return
            }

            // Append assistant response to conversation
            let assistantMessage = Message(role: .assistant, content: finalText)
            conversation.messages.append(assistantMessage)
            conversation.updatedAt = Date()

            // Auto-title from first user message
            if conversation.title == "새 대화",
               let firstUser = conversation.messages.first(where: { $0.role == .user }) {
                let title = String(firstUser.content.prefix(40))
                conversation.title = title.count < firstUser.content.count ? title + "…" : title
            }

            // Persist conversation and refresh sidebar
            conversationService.save(conversation: conversation)
            loadConversations()

            // Send/finalize response via Telegram
            if let tg = getTelegramService() {
                if useStreaming, let msgId = streamMessageId {
                    // Final edit to remove cursor and show complete text
                    try await tg.editMessage(chatId: update.chatId, messageId: msgId, text: finalText)
                    Log.telegram.info("Finalized streaming response to chat \(update.chatId)")
                } else {
                    // Non-streaming: send complete response in single message
                    _ = try await tg.sendMessage(chatId: update.chatId, text: finalText)
                    Log.telegram.info("Sent Telegram response to chat \(update.chatId)")
                }
            }
        } catch {
            Log.telegram.error("Telegram response failed: \(error.localizedDescription)")
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

    // MARK: - LLM Processing Loop

    private func processLLMLoop() async {
        guard var conversation = currentConversation else { return }

        // Resolve model via router (primary + optional fallback)
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let agentConfig = contextService.loadAgentConfig(
            workspaceId: sessionContext.workspaceId,
            agentName: settings.activeAgentName
        )

        // Classify task complexity from last user message
        let lastUserText = conversation.messages.last(where: { $0.role == .user })?.content ?? ""
        let complexity = TaskComplexityClassifier.classify(lastUserText)

        guard let primaryModel = router.resolveForComplexity(complexity, agentConfig: agentConfig) else {
            handleError(LLMError.noAPIKey)
            return
        }
        let fallbackModel = router.resolveFallback()

        // Compress context if needed (before composing final prompt)
        await compressContextIfNeeded()

        // Compose context (after potential compression)
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
                response = try await sendWithFallback(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    primary: primaryModel,
                    fallback: fallbackModel,
                    tools: tools
                )
            } catch {
                if Task.isCancelled { return }
                handleError(error)
                return
            }

            guard !Task.isCancelled else { return }

            switch response {
            case .text(let text):
                llmStreamActive = false

                let finalText = text.isEmpty ? streamingText : text
                if finalText.isEmpty {
                    handleError(LLMError.emptyResponse)
                    return
                }
                streamingText = ""
                appendAssistantMessage(finalText, metadata: buildMessageMetadata())
                conversation = currentConversation!
                saveConversation()

                // Flush remaining TTS text from sentence chunker
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

    // MARK: - LLM Send with Fallback

    /// Send to the primary model, falling back to alternate model on transient failure.
    private func sendWithFallback(
        messages: [Message],
        systemPrompt: String,
        primary: ResolvedModel,
        fallback: ResolvedModel?,
        tools: [[String: Any]]
    ) async throws -> LLMResponse {
        let onPartial: @MainActor @Sendable (String) -> Void = { [weak self] partial in
            guard let self else { return }
            self.streamingText += partial

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

        do {
            let response = try await llmService.send(
                messages: messages,
                systemPrompt: systemPrompt,
                model: primary.model,
                provider: primary.provider,
                apiKey: primary.apiKey,
                tools: tools.isEmpty ? nil : tools,
                onPartial: onPartial
            )
            recordMetrics(wasFallback: false)
            return response
        } catch {
            // Try fallback if available and the error is eligible
            guard let fallback, ModelRouter.shouldFallback(for: error) else {
                throw error
            }

            Log.llm.warning("Primary model failed, trying fallback: \(fallback.provider.displayName)/\(fallback.model)")
            streamingText = ""
            sentenceChunker = SentenceChunker()

            let response = try await llmService.send(
                messages: messages,
                systemPrompt: systemPrompt,
                model: fallback.model,
                provider: fallback.provider,
                apiKey: fallback.apiKey,
                tools: tools.isEmpty ? nil : tools,
                onPartial: onPartial
            )
            recordMetrics(wasFallback: true)
            return response
        }
    }

    /// Record metrics from the most recent LLM exchange.
    private func recordMetrics(wasFallback: Bool) {
        guard var metrics = llmService.lastMetrics else { return }
        if wasFallback {
            // Override the wasFallback flag since LLMService doesn't know about fallback
            metrics = ExchangeMetrics(
                provider: metrics.provider,
                model: metrics.model,
                inputTokens: metrics.inputTokens,
                outputTokens: metrics.outputTokens,
                totalTokens: metrics.totalTokens,
                firstByteLatency: metrics.firstByteLatency,
                totalLatency: metrics.totalLatency,
                timestamp: metrics.timestamp,
                wasFallback: true
            )
        }
        metricsCollector.record(metrics)
    }

    // MARK: - Context Auto-Compression

    /// Compress context memories if total context exceeds model's context window.
    /// Priority order: workspace+agent memory first, then personal memory.
    /// Base prompt and agent persona are NEVER compressed.
    private func compressContextIfNeeded() async {
        guard settings.contextAutoCompress else { return }
        guard let conversation = currentConversation else { return }

        let systemPrompt = composeSystemPrompt()
        let messageChars = conversation.messages.reduce(0) { $0 + $1.content.count }
        let totalChars = systemPrompt.count + messageChars
        // Estimate max chars from model token window (Korean ~2 chars/token, use 80% budget)
        let charLimit = Int(Double(contextWindowTokens) * 2.0 * 0.8)

        guard totalChars > charLimit else {
            Log.app.debug("Context size \(totalChars) within limit \(charLimit), no compression needed")
            return
        }

        Log.app.info("Context size \(totalChars) exceeds limit \(charLimit), starting compression")

        // Check for OpenAI API key (required for compression model)
        guard let openAIKey = keychainService.load(account: LLMProvider.openai.keychainAccount),
              !openAIKey.isEmpty else {
            Log.app.warning("OpenAI API key not available, skipping context compression")
            return
        }

        let wsId = sessionContext.workspaceId
        let agentName = settings.activeAgentName

        // Step 2: Compress workspace memory + agent memory
        if let wsMem = contextService.loadWorkspaceMemory(workspaceId: wsId), !wsMem.isEmpty {
            if let summary = await summarizeText(wsMem, apiKey: openAIKey) {
                contextService.saveWorkspaceMemorySnapshot(workspaceId: wsId, content: wsMem)
                contextService.saveWorkspaceMemory(workspaceId: wsId, content: summary)
                Log.app.info("Compressed workspace memory: \(wsMem.count) → \(summary.count) chars")
            }
        }

        if let agentMem = contextService.loadAgentMemory(workspaceId: wsId, agentName: agentName), !agentMem.isEmpty {
            if let summary = await summarizeText(agentMem, apiKey: openAIKey) {
                contextService.saveAgentMemorySnapshot(workspaceId: wsId, agentName: agentName, content: agentMem)
                contextService.saveAgentMemory(workspaceId: wsId, agentName: agentName, content: summary)
                Log.app.info("Compressed agent memory: \(agentMem.count) → \(summary.count) chars")
            }
        }

        // Re-check if still over limit after workspace+agent compression
        let afterStep2 = composeSystemPrompt().count + messageChars
        guard afterStep2 > charLimit else {
            Log.app.info("Context within limit after workspace+agent compression (\(afterStep2))")
            return
        }

        // Step 3: Compress personal memory
        if let userId = sessionContext.currentUserId,
           let personalMem = contextService.loadUserMemory(userId: userId), !personalMem.isEmpty {
            if let summary = await summarizeText(personalMem, apiKey: openAIKey) {
                contextService.saveUserMemorySnapshot(userId: userId, content: personalMem)
                contextService.saveUserMemory(userId: userId, content: summary)
                Log.app.info("Compressed personal memory: \(personalMem.count) → \(summary.count) chars")
            }
        }

        let afterStep3 = composeSystemPrompt().count + messageChars
        Log.app.info("Context compression complete. Final size: \(afterStep3)")
    }

    /// Summarize text using a fixed lightweight model (gpt-4o-mini via OpenAI).
    /// Returns the summary if shorter than the original, otherwise returns nil.
    private func summarizeText(_ text: String, apiKey: String) async -> String? {
        let userMessage = Message(role: .user, content: text)
        let noopPartial: @MainActor @Sendable (String) -> Void = { _ in }

        do {
            let response = try await llmService.send(
                messages: [userMessage],
                systemPrompt: Self.compressionSummaryPrompt,
                model: Self.compressionModel,
                provider: .openai,
                apiKey: apiKey,
                tools: nil,
                onPartial: noopPartial
            )

            switch response {
            case .text(let summary):
                let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    Log.app.warning("Compression returned empty summary, keeping original")
                    return nil
                }
                // Safety: if summary is not shorter, keep original
                if trimmed.count >= text.count {
                    Log.app.warning("Compression summary (\(trimmed.count)) not shorter than original (\(text.count)), keeping original")
                    return nil
                }
                return trimmed
            default:
                Log.app.warning("Compression returned unexpected response type, keeping original")
                return nil
            }
        } catch {
            Log.app.error("Context compression LLM call failed: \(error.localizedDescription)")
            return nil
        }
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
        if let wsMem = contextService.loadWorkspaceMemory(workspaceId: wsId), !wsMem.isEmpty {
            parts.append("## 워크스페이스 메모리\n\(wsMem)")
        }

        // 6. Agent memory
        if let agentMem = contextService.loadAgentMemory(workspaceId: wsId, agentName: agentName), !agentMem.isEmpty {
            parts.append("## 에이전트 메모리\n\(agentMem)")
        }

        // 7. Personal memory
        if let userId = sessionContext.currentUserId,
           let personalMem = contextService.loadUserMemory(userId: userId), !personalMem.isEmpty {
            parts.append("## 개인 메모리\n\(personalMem)")
        }

        // 8. Non-baseline tool listing for LLM awareness
        let nonBaseline = toolService.nonBaselineToolSummaries
        if !nonBaseline.isEmpty {
            var lines: [String] = ["## 추가 도구", "필요 시 tools.enable으로 활성화할 수 있는 도구:"]
            for tool in nonBaseline {
                lines.append("- \(tool.name): \(tool.description) (\(tool.category.rawValue))")
            }
            lines.append("사용자가 관련 작업을 요청하면 tools.enable으로 먼저 활성화하세요.")
            parts.append(lines.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Message Preparation

    private func prepareMessages(from conversation: Conversation) -> [Message] {
        var messages = conversation.messages

        if messages.count > Self.maxRecentMessages {
            messages = Array(messages.suffix(Self.maxRecentMessages))
        }

        // Estimate max chars from model's token window.
        // Korean text averages ~2 chars/token; use 80% of window to leave room for system prompt + response.
        let maxChars = Int(Double(contextWindowTokens) * 2.0 * 0.8)
        var totalChars = messages.reduce(0) { $0 + $1.content.count }

        while totalChars > maxChars && messages.count > 5 {
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

    // MARK: - Export

    func exportConversation(id: UUID, format: ExportFormat) {
        guard let conversation = conversationService.load(id: id) else {
            Log.app.warning("Export failed: conversation not found \(id)")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = ConversationExporter.suggestedFileName(for: conversation, format: format)
        panel.canCreateDirectories = true

        switch format {
        case .markdown:
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        case .json:
            panel.allowedContentTypes = [.json]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch format {
            case .markdown:
                let markdown = ConversationExporter.toMarkdown(conversation)
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            case .json:
                let data = try ConversationExporter.toJSON(conversation)
                try data.write(to: url, options: .atomic)
            }
            Log.app.info("Exported conversation \(id) as \(format == .markdown ? "markdown" : "json")")
        } catch {
            Log.app.error("Export failed: \(error.localizedDescription)")
            errorMessage = "내보내기 실패: \(error.localizedDescription)"
        }
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

    private func appendAssistantMessage(_ text: String, metadata: MessageMetadata? = nil) {
        currentConversation?.messages.append(Message(role: .assistant, content: text, metadata: metadata))
        currentConversation?.updatedAt = Date()
    }

    /// Build MessageMetadata from the most recent LLM exchange metrics.
    private func buildMessageMetadata() -> MessageMetadata? {
        guard let metrics = llmService.lastMetrics else { return nil }
        return MessageMetadata(
            provider: metrics.provider,
            model: metrics.model,
            inputTokens: metrics.inputTokens,
            outputTokens: metrics.outputTokens,
            totalLatency: metrics.totalLatency,
            wasFallback: metrics.wasFallback
        )
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
            Log.app.error("LLM error: \(error.localizedDescription, privacy: .public)")
        }

        if !streamingText.isEmpty {
            appendAssistantMessage(streamingText)
            streamingText = ""
        }

        saveConversation()
        llmStreamActive = false
        ttsService.stopAndClear()
        sentenceChunker = SentenceChunker()
        processingSubState = nil
        currentToolName = nil
        transition(to: .idle)
    }
}
