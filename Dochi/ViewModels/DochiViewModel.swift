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

    // MARK: - Services

    private let llmService: LLMServiceProtocol
    private let toolService: BuiltInToolServiceProtocol
    private let contextService: ContextServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let keychainService: KeychainServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext

    // MARK: - Internal

    private var processingTask: Task<Void, Never>?
    private static let maxToolLoopIterations = 10
    private static let maxRecentMessages = 30

    // MARK: - Init

    init(
        llmService: LLMServiceProtocol,
        toolService: BuiltInToolServiceProtocol,
        contextService: ContextServiceProtocol,
        conversationService: ConversationServiceProtocol,
        keychainService: KeychainServiceProtocol,
        settings: AppSettings,
        sessionContext: SessionContext
    ) {
        self.llmService = llmService
        self.toolService = toolService
        self.contextService = contextService
        self.conversationService = conversationService
        self.keychainService = keychainService
        self.settings = settings
        self.sessionContext = sessionContext

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

    // MARK: - Public Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard interactionState == .idle else {
            let current = String(describing: interactionState)
            Log.app.warning("Cannot send message: not idle (current: \(current))")
            return
        }

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
        let count = conversations.count
        Log.app.debug("Loaded \(count) conversations")
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
                        self?.streamingText += partial
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
                processingSubState = .complete
                transition(to: .idle)
                return

            case .partial(let text):
                // Shouldn't reach here normally — partials go through onPartial
                streamingText = text

            case .toolCalls(let toolCalls):
                toolLoopCount += 1

                // Append the assistant message with tool calls (no text content)
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
                    // One final LLM call to summarize
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
                // Continue loop — re-call LLM with tool results
            }
        }

        // Exceeded max loops — force final response
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

    /// Composes the system prompt following the 7-step order from flows.md §7.
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

    /// Trims messages to fit context size. Step 7 from flows.md:
    /// recent messages (default 30), with compression if exceeding contextMaxSize.
    private func prepareMessages(from conversation: Conversation) -> [Message] {
        var messages = conversation.messages

        // Only keep recent messages (configurable, default 30)
        if messages.count > Self.maxRecentMessages {
            messages = Array(messages.suffix(Self.maxRecentMessages))
        }

        // Check total character size against contextMaxSize
        let maxSize = settings.contextMaxSize
        var totalChars = messages.reduce(0) { $0 + $1.content.count }

        // Stage 1: remove oldest messages (keep minimum 5)
        while totalChars > maxSize && messages.count > 5 {
            let removed = messages.removeFirst()
            totalChars -= removed.content.count
        }

        return messages
    }

    // MARK: - API Key Management (for Settings UI)

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
        let prefix = String(key.prefix(6))
        return "\(prefix)****"
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
            currentConversation = Conversation(
                userId: sessionContext.currentUserId
            )
        }
    }

    private func appendUserMessage(_ text: String) {
        let message = Message(role: .user, content: text)
        currentConversation?.messages.append(message)
        currentConversation?.updatedAt = Date()
    }

    private func appendAssistantMessage(_ text: String) {
        let message = Message(role: .assistant, content: text)
        currentConversation?.messages.append(message)
        currentConversation?.updatedAt = Date()
    }

    private func appendToolResultMessage(_ result: ToolResult) {
        let message = Message(
            role: .tool,
            content: result.content,
            toolCallId: result.toolCallId
        )
        currentConversation?.messages.append(message)
        currentConversation?.updatedAt = Date()
    }

    private func saveConversation() {
        guard let conversation = currentConversation else { return }

        // Auto-title from first user message if still default
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
            // User-initiated cancel — no error message needed
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
            // User-initiated cancel — skip logging
        } else {
            Log.app.error("LLM error: \(error.localizedDescription)")
        }

        // Preserve partial response
        if !streamingText.isEmpty {
            appendAssistantMessage(streamingText)
            streamingText = ""
        }

        saveConversation()
        processingSubState = nil
        currentToolName = nil
        transition(to: .idle)
    }
}
