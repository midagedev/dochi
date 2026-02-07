import Foundation
import SwiftUI
import Combine

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
    private let contextService: ContextServiceProtocol
    private let conversationService: ConversationServiceProtocol

    // Tool loop 관련
    @Published var currentToolExecution: String?
    private var toolLoopMessages: [Message] = []
    private let maxToolIterations = 10

    private var cancellables = Set<AnyCancellable>()
    @Published var wakeWordVariations: [String] = []
    private var lastGeneratedWakeWord: String = ""

    // 연속 대화 모드
    @Published var isSessionActive: Bool = false
    private var isAskingToEndSession: Bool = false
    private let sessionTimeoutSeconds: TimeInterval = 10.0

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
        loadConversations()
    }

    private func setupCallbacks() {
        // 웨이크워드 감지 → 세션 시작
        speechService.onWakeWordDetected = { [weak self] in
            guard let self else { return }
            self.isSessionActive = true
            self.state = .listening
            print("[Dochi] 세션 시작")
        }

        // STT 완료 → 응답 처리
        speechService.onQueryCaptured = { [weak self] query in
            guard let self else { return }

            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.handleEndSessionResponse(query)
                return
            }

            if self.isSessionActive && self.isEndSessionRequest(query) {
                self.confirmAndEndSession()
                return
            }

            self.handleQuery(query)
        }

        // STT 무음 타임아웃
        speechService.onSilenceTimeout = { [weak self] in
            guard let self, self.isSessionActive else { return }

            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.endSession()
                return
            }

            self.askToEndSession()
        }

        // LLM 문장 단위 → TTS 큐에 즉시 추가
        llmService.onSentenceReady = { [weak self] sentence in
            guard let self else { return }
            if self.supertonicService.state == .ready || self.supertonicService.state == .synthesizing || self.supertonicService.state == .playing {
                self.state = .speaking
                self.supertonicService.speed = self.settings.ttsSpeed
                self.supertonicService.diffusionSteps = self.settings.ttsDiffusionSteps
                self.supertonicService.enqueueSentence(sentence, voice: self.settings.supertonicVoice)
            }
        }

        // LLM 응답 완료 → 메시지 히스토리에 추가
        llmService.onResponseComplete = { [weak self] response in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: response))
        }

        // LLM이 tool 호출 요청 → tool 실행 후 재호출
        llmService.onToolCallsReceived = { [weak self] toolCalls in
            guard let self else { return }
            Task {
                await self.executeToolLoop(toolCalls: toolCalls)
            }
        }

        // TTS 재생 완료 → 연속 대화 또는 웨이크워드 대기
        supertonicService.onSpeakingComplete = { [weak self] in
            guard let self else { return }
            self.state = .idle

            if self.isSessionActive {
                self.startContinuousListening()
            } else {
                self.startWakeWordIfNeeded()
            }
        }

        // Supertonic 로드 완료 → 웨이크워드 시작
        supertonicService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ttsState in
                guard let self, ttsState == .ready, self.state == .idle else { return }
                self.startWakeWordIfNeeded()
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

    // MARK: - Connection

    func connectOnLaunch() {
        if supertonicService.state == .unloaded {
            connect()
        }
    }

    func toggleConnection() {
        if supertonicService.state == .ready {
            stopWakeWord()
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

    private func handleQuery(_ query: String) {
        messages.append(Message(role: .user, content: query))
        state = .processing

        // Tool loop 초기화
        toolLoopMessages = messages

        sendLLMRequest(messages: messages, toolResults: nil)
    }

    private func sendLLMRequest(messages: [Message], toolResults: [ToolResult]?) {
        let provider = settings.llmProvider
        let model = settings.llmModel
        let apiKey = settings.apiKey(for: provider)
        let systemPrompt = settings.buildInstructions()

        // 내장 도구 서비스 설정 업데이트
        builtInToolService.configure(tavilyApiKey: settings.tavilyApiKey)

        // MCP + 내장 도구 목록
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

    // MARK: - Tool Loop

    private func executeToolLoop(toolCalls: [ToolCall]) async {
        var iteration = 0
        var currentToolCalls = toolCalls

        while !currentToolCalls.isEmpty && iteration < maxToolIterations {
            iteration += 1
            print("[Dochi] Tool loop iteration \(iteration), \(currentToolCalls.count) tools to execute")

            // 현재 partial response를 assistant 메시지로 저장 (tool_calls 포함)
            let assistantMessage = Message(
                role: .assistant,
                content: llmService.partialResponse,
                toolCalls: currentToolCalls
            )
            toolLoopMessages.append(assistantMessage)

            // 각 tool 실행
            var results: [ToolResult] = []
            for toolCall in currentToolCalls {
                currentToolExecution = toolCall.name
                state = .executingTool(toolCall.name)
                print("[Dochi] Executing tool: \(toolCall.name)")

                do {
                    // 내장 도구인지 확인
                    let isBuiltIn = builtInToolService.availableTools.contains { $0.name == toolCall.name }
                    let toolResult: MCPToolResult

                    if isBuiltIn {
                        toolResult = try await builtInToolService.callTool(
                            name: toolCall.name,
                            arguments: toolCall.arguments
                        )
                    } else {
                        toolResult = try await mcpService.callTool(
                            name: toolCall.name,
                            arguments: toolCall.arguments
                        )
                    }
                    results.append(ToolResult(
                        toolCallId: toolCall.id,
                        content: toolResult.content,
                        isError: toolResult.isError
                    ))
                    print("[Dochi] Tool \(toolCall.name) completed")
                } catch {
                    results.append(ToolResult(
                        toolCallId: toolCall.id,
                        content: "Error: \(error.localizedDescription)",
                        isError: true
                    ))
                    print("[Dochi] Tool \(toolCall.name) failed: \(error)")
                }
            }

            currentToolExecution = nil
            state = .processing

            // tool 결과와 함께 LLM 재호출
            // continuation을 사용해서 다음 응답 대기
            currentToolCalls = await withCheckedContinuation { continuation in
                var receivedToolCalls: [ToolCall]?
                var completed = false

                llmService.onToolCallsReceived = { [weak self] toolCalls in
                    guard let self, !completed else { return }
                    completed = true
                    receivedToolCalls = toolCalls
                    continuation.resume(returning: toolCalls)
                }

                llmService.onResponseComplete = { [weak self] response in
                    guard let self, !completed else { return }
                    completed = true
                    // 최종 응답 - 메시지에 추가
                    self.messages = self.toolLoopMessages
                    self.messages.append(Message(role: .assistant, content: response))
                    continuation.resume(returning: [])
                }

                sendLLMRequest(messages: toolLoopMessages, toolResults: results)
            }
        }

        if iteration >= maxToolIterations {
            print("[Dochi] Tool loop reached max iterations (\(maxToolIterations))")
            errorMessage = "도구 실행 횟수가 최대치(\(maxToolIterations))에 도달했습니다."
        }

        // Tool loop 완료 후 콜백 복원
        setupLLMCallbacks()
    }

    private func setupLLMCallbacks() {
        llmService.onResponseComplete = { [weak self] response in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: response))
        }

        llmService.onToolCallsReceived = { [weak self] toolCalls in
            guard let self else { return }
            Task {
                await self.executeToolLoop(toolCalls: toolCalls)
            }
        }
    }

    // MARK: - Wake Word

    func startWakeWordIfNeeded() {
        guard settings.wakeWordEnabled,
              state == .idle,
              speechService.state == .idle,
              !settings.wakeWord.isEmpty
        else { return }

        let wakeWord = settings.wakeWord

        if wakeWord == lastGeneratedWakeWord, !wakeWordVariations.isEmpty {
            speechService.startWakeWordDetection(phrases: wakeWordVariations)
            return
        }

        Task {
            let variations = await generateWakeWordVariations(wakeWord)
            self.wakeWordVariations = variations
            self.lastGeneratedWakeWord = wakeWord
            print("[Dochi] 웨이크워드 변형 (\(variations.count)개): \(variations)")

            guard self.settings.wakeWordEnabled,
                  self.state == .idle,
                  self.speechService.state == .idle
            else { return }
            self.speechService.startWakeWordDetection(phrases: variations)
        }
    }

    func stopWakeWord() {
        speechService.stopWakeWordDetection()
    }

    private func generateWakeWordVariations(_ wakeWord: String) async -> [String] {
        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !settings.apiKey(for: $0).isEmpty }) else {
            return [wakeWord]
        }

        let apiKey = settings.apiKey(for: provider)
        let prompt = """
        다음 단어와 발음이 비슷하여 한국어 음성인식(STT)에서 이 단어 대신 인식될 수 있는 표현들을 나열해줘.
        원래 단어 포함해서 총 15개. 각 줄에 하나씩만, 번호나 설명 없이 단어만: \(wakeWord)
        """

        do {
            let response = try await callLLMSimple(provider: provider, apiKey: apiKey, prompt: prompt)
            var variations = response
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"^[\d]+[.\)]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "- ", with: "")
                }
                .filter { !$0.isEmpty && $0.count <= 10 }

            if !variations.contains(wakeWord) {
                variations.insert(wakeWord, at: 0)
            }
            return variations.isEmpty ? [wakeWord] : variations
        } catch {
            print("[Dochi] 웨이크워드 변형 생성 실패: \(error.localizedDescription)")
            return [wakeWord]
        }
    }

    private func callLLMSimple(provider: LLMProvider, apiKey: String, prompt: String) async throws -> String {
        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        switch provider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": "gpt-4o-mini",
                "messages": [["role": "user", "content": prompt]],
                "max_tokens": 300,
            ]
        case .zai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": "glm-4.7",
                "messages": [["role": "user", "content": prompt]],
                "max_tokens": 300,
                "enable_thinking": false,
            ] as [String: Any]
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": "claude-haiku-4-20250414",
                "messages": [["role": "user", "content": prompt]],
                "max_tokens": 300,
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }

        switch provider {
        case .openai, .zai:
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        case .anthropic:
            if let content = json["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                return text
            }
        }
        return ""
    }

    // MARK: - Continuous Conversation

    private func startContinuousListening() {
        state = .listening
        speechService.startContinuousListening(timeout: sessionTimeoutSeconds)
        print("[Dochi] 연속 대화 STT 시작 (타임아웃: \(sessionTimeoutSeconds)초)")
    }

    private func askToEndSession() {
        isAskingToEndSession = true
        state = .speaking
        supertonicService.speed = settings.ttsSpeed
        supertonicService.diffusionSteps = settings.ttsDiffusionSteps
        supertonicService.speak("대화를 종료할까요?", voice: settings.supertonicVoice)
        print("[Dochi] 세션 종료 여부 질문")
    }

    private func handleEndSessionResponse(_ response: String) {
        let normalized = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let positiveKeywords = ["응", "어", "예", "네", "그래", "종료", "끝", "됐어", "괜찮아", "ㅇㅇ", "웅", "yes", "yeah", "ok", "okay"]

        if positiveKeywords.contains(where: { normalized.contains($0) }) {
            endSession()
        } else {
            print("[Dochi] 세션 계속")
            handleQuery(response)
        }
    }

    private func isEndSessionRequest(_ query: String) -> Bool {
        let normalized = query.lowercased().replacingOccurrences(of: " ", with: "")
        let endKeywords = [
            "대화종료", "대화끝", "세션종료", "세션끝",
            "그만할게", "그만하자", "이만할게", "이만하자",
            "끝내자", "끝낼게", "종료해", "종료할게",
            "잘가", "잘있어", "바이바이", "bye", "goodbye"
        ]
        return endKeywords.contains(where: { normalized.contains($0) })
    }

    private func confirmAndEndSession() {
        state = .speaking
        supertonicService.speed = settings.ttsSpeed
        supertonicService.diffusionSteps = settings.ttsDiffusionSteps
        supertonicService.speak("네, 대화를 종료할게요. 다음에 또 불러주세요!", voice: settings.supertonicVoice)

        Task {
            while supertonicService.state == .playing || supertonicService.state == .synthesizing {
                try? await Task.sleep(for: .milliseconds(100))
            }
            endSession()
        }
    }

    private func endSession() {
        print("[Dochi] 세션 종료")
        isSessionActive = false
        isAskingToEndSession = false

        if !messages.isEmpty {
            let sessionMessages = messages
            Task {
                await saveAndAnalyzeConversation(sessionMessages)
            }
        }
        messages.removeAll()
        currentConversationId = nil

        state = .idle
        startWakeWordIfNeeded()
    }

    // MARK: - Push-to-Talk

    func startListening() {
        guard state == .idle else { return }
        stopWakeWord()
        isSessionActive = true
        state = .listening
        speechService.startListening()
    }

    func stopListening() {
        guard state == .listening else { return }
        speechService.stopListening()
    }

    func clearConversation() {
        if !messages.isEmpty {
            let sessionMessages = messages
            Task {
                await saveAndAnalyzeConversation(sessionMessages)
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
        // 현재 대화가 있으면 먼저 저장
        if !messages.isEmpty {
            let sessionMessages = messages
            Task {
                await saveAndAnalyzeConversation(sessionMessages)
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

    private func saveCurrentConversation(title: String) {
        let id = currentConversationId ?? UUID()
        let now = Date()

        let conversation = Conversation(
            id: id,
            title: title,
            messages: messages,
            createdAt: conversations.first(where: { $0.id == id })?.createdAt ?? now,
            updatedAt: now
        )

        conversationService.save(conversation)
        loadConversations()
    }

    // MARK: - Session Context Analysis

    private func saveAndAnalyzeConversation(_ sessionMessages: [Message]) async {
        guard sessionMessages.count >= 2 else { return }

        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !settings.apiKey(for: $0).isEmpty }) else {
            // API 키 없으면 기본 제목으로 저장
            let defaultTitle = generateDefaultTitle(from: sessionMessages)
            await MainActor.run {
                saveConversationWithTitle(defaultTitle, messages: sessionMessages)
            }
            return
        }

        let apiKey = settings.apiKey(for: provider)
        let currentContext = contextService.loadMemory()

        let conversationText = sessionMessages.map { msg in
            let role = msg.role == .user ? "사용자" : "어시스턴트"
            return "[\(role)] \(msg.content)"
        }.joined(separator: "\n")

        let prompt = """
        다음은 방금 끝난 대화입니다:

        \(conversationText)

        ---

        현재 저장된 사용자 컨텍스트:
        \(currentContext.isEmpty ? "(없음)" : currentContext)

        ---

        두 가지를 JSON 형식으로 출력해주세요:
        1. "title": 이 대화를 3~10자로 요약한 제목 (한글)
        2. "memory": 장기적으로 기억할 사용자 정보 (이름, 선호도, 관심사 등). 기존과 중복되거나 없으면 null

        반드시 아래 형식만 출력 (다른 텍스트 없이):
        {"title": "...", "memory": "..." 또는 null}
        """

        do {
            let response = try await callLLMSimple(provider: provider, apiKey: apiKey, prompt: prompt)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            // JSON 파싱
            if let jsonData = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                let title = json["title"] as? String ?? generateDefaultTitle(from: sessionMessages)

                // 대화 저장
                await MainActor.run {
                    saveConversationWithTitle(title, messages: sessionMessages)
                }

                // 메모리 업데이트
                if let memory = json["memory"] as? String, !memory.isEmpty {
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    let entry = "\n\n<!-- \(timestamp) -->\n\(memory)"
                    contextService.appendMemory(entry)
                    print("[Dochi] 컨텍스트 추가됨: \(memory.prefix(50))...")

                    await compressContextIfNeeded()
                }
            } else {
                // JSON 파싱 실패 시 기본 제목으로 저장
                let defaultTitle = generateDefaultTitle(from: sessionMessages)
                await MainActor.run {
                    saveConversationWithTitle(defaultTitle, messages: sessionMessages)
                }
            }
        } catch {
            print("[Dochi] 컨텍스트 분석 실패: \(error.localizedDescription)")
            let defaultTitle = generateDefaultTitle(from: sessionMessages)
            await MainActor.run {
                saveConversationWithTitle(defaultTitle, messages: sessionMessages)
            }
        }
    }

    private func saveConversationWithTitle(_ title: String, messages: [Message]) {
        let id = currentConversationId ?? UUID()
        let now = Date()

        let conversation = Conversation(
            id: id,
            title: title,
            messages: messages,
            createdAt: conversations.first(where: { $0.id == id })?.createdAt ?? now,
            updatedAt: now
        )

        conversationService.save(conversation)
        loadConversations()
        print("[Dochi] 대화 저장됨: \(title)")
    }

    private func generateDefaultTitle(from messages: [Message]) -> String {
        // 첫 사용자 메시지에서 제목 생성
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.count <= 10 {
                return content
            } else {
                return String(content.prefix(10)) + "..."
            }
        }
        return "대화"
    }

    // MARK: - Context Compression

    private func compressContextIfNeeded() async {
        guard settings.contextAutoCompress else { return }

        let currentSize = contextService.memorySize
        let maxSize = settings.contextMaxSize
        guard currentSize > maxSize else { return }

        print("[Dochi] 컨텍스트 압축 시작 (현재: \(currentSize) bytes, 제한: \(maxSize) bytes)")

        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !settings.apiKey(for: $0).isEmpty }) else {
            print("[Dochi] 컨텍스트 압축 불가: API 키 없음")
            return
        }

        let apiKey = settings.apiKey(for: provider)
        let currentContext = contextService.loadMemory()

        let prompt = """
        다음은 사용자에 대해 기억하고 있는 정보입니다:

        \(currentContext)

        ---

        위 정보를 다음 기준으로 정리해주세요:
        - 중요도 순으로 정렬
        - 중복되거나 비슷한 내용은 하나로 통합
        - 오래되거나 불필요해 보이는 정보는 제거
        - 타임스탬프 주석(<!-- ... -->)은 제거
        - 결과물은 현재 크기의 절반 이하로
        - 마크다운 형식 유지
        - 절대 인사말이나 설명 없이 정리된 내용만 출력
        """

        do {
            let response = try await callLLMSimple(provider: provider, apiKey: apiKey, prompt: prompt)
            let compressed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if !compressed.isEmpty && compressed.count < currentContext.count {
                contextService.saveMemory(compressed)
                let newSize = contextService.memorySize
                print("[Dochi] 컨텍스트 압축 완료 (\(currentSize) → \(newSize) bytes)")
            }
        } catch {
            print("[Dochi] 컨텍스트 압축 실패: \(error.localizedDescription)")
        }
    }
}
