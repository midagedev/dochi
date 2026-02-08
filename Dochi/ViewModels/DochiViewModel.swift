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
    private let contextService: ContextServiceProtocol
    private let conversationService: ConversationServiceProtocol

    // Tool loop 관련
    @Published var currentToolExecution: String?
    private var toolLoopMessages: [Message] = []
    private let maxToolIterations = 10

    private var cancellables = Set<AnyCancellable>()
    // 연속 대화 모드
    @Published var isSessionActive: Bool = false
    @Published var autoEndSession: Bool = true
    private var isAskingToEndSession: Bool = false
    private let sessionTimeoutSeconds: TimeInterval = 10.0

    // 다중 사용자
    @Published var currentUserId: UUID?
    @Published var currentUserName: String?


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

    private func setupCallbacks() {
        // 웨이크워드 감지 → 세션 시작 + 사용자 식별
        speechService.onWakeWordDetected = { [weak self] transcript in
            guard let self else { return }
            self.isSessionActive = true
            self.state = .listening
            self.identifyUserFromTranscript(transcript)
            Log.app.info("세션 시작 (사용자: \(self.currentUserName ?? "미확인"))")
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

        // STT 리스닝 실패/빈 결과로 종료
        speechService.onListeningCancelled = { [weak self] in
            guard let self, self.state == .listening else { return }
            Log.app.info("리스닝 취소 — 상태 리셋")
            self.state = .idle
            self.startWakeWordIfNeeded()
        }

        // STT 무음 타임아웃
        speechService.onSilenceTimeout = { [weak self] in
            guard let self, self.isSessionActive else { return }

            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.endSession()
                return
            }

            if self.autoEndSession {
                self.askToEndSession()
            } else {
                // 자동종료 꺼져있으면 계속 듣기
                self.startContinuousListening()
            }
        }

        // LLM 문장 단위 → TTS 큐에 즉시 추가
        llmService.onSentenceReady = { [weak self] sentence in
            guard let self else { return }
            if self.supertonicService.state == .ready || self.supertonicService.state == .synthesizing || self.supertonicService.state == .playing {
                if self.state != .speaking {
                    // speaking 진입 시 STT 완전 해제 (에코 방지)
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

        // LLM 응답 완료 → 메시지 히스토리에 추가 + TTS 미재생 시 상태 복구
        llmService.onResponseComplete = { [weak self] response in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: response))
            self.recoverIfTTSDidNotPlay()
        }

        // LLM이 tool 호출 요청 → tool 실행 후 재호출
        llmService.onToolCallsReceived = { [weak self] toolCalls in
            guard let self else { return }
            Task {
                await self.executeToolLoop(toolCalls: toolCalls)
            }
        }

        // TTS 재생 완료 → 에코 방지 딜레이 후 연속 대화 또는 웨이크워드 대기
        supertonicService.onSpeakingComplete = { [weak self] in
            guard let self else { return }
            self.state = .idle

            Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard self.state == .idle else { return }

                if self.isSessionActive {
                    self.startContinuousListening()
                } else {
                    self.startWakeWordIfNeeded()
                }
            }
        }

        // 알람 발동 → TTS로 알림
        builtInToolService.onAlarmFired = { [weak self] message in
            guard let self else { return }
            Log.app.info("알람 발동: \(message), 현재 상태: \(String(describing: self.state)), TTS 상태: \(String(describing: self.supertonicService.state))")
            // speaking/listening 중이면 중단
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

    private func setupProfileCallback() {
        builtInToolService.profileTool.onUserIdentified = { [weak self] profile in
            guard let self else { return }
            self.currentUserId = profile.id
            self.currentUserName = profile.name
            Log.app.info("사용자 설정됨 (tool): \(profile.name)")
        }
    }

    /// 웨이크워드 transcript에서 프로필 이름 매칭
    private func identifyUserFromTranscript(_ transcript: String) {
        let profiles = contextService.loadProfiles()
        guard !profiles.isEmpty else {
            // 프로필 없으면 레거시 모드
            currentUserId = nil
            currentUserName = nil
            return
        }

        let normalized = transcript.replacingOccurrences(of: " ", with: "").lowercased()

        // 프로필 이름/별칭 매칭
        if let matched = profiles.first(where: { profile in
            profile.allNames.contains { normalized.contains($0.lowercased()) }
        }) {
            currentUserId = matched.id
            currentUserName = matched.name
            Log.app.info("웨이크워드에서 사용자 식별: \(matched.name)")
            return
        }

        // 매칭 실패 → 기본 사용자
        if let defaultId = settings.defaultUserId,
           let defaultProfile = profiles.first(where: { $0.id == defaultId }) {
            currentUserId = defaultProfile.id
            currentUserName = defaultProfile.name
            Log.app.info("기본 사용자 할당: \(defaultProfile.name)")
            return
        }

        // 둘 다 실패 → nil (시스템 프롬프트에서 "미확인" 처리)
        currentUserId = nil
        currentUserName = nil
    }

    /// 사용자별 최근 대화 요약 (최근 N개)
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

    // MARK: - Connection

    func connectOnLaunch() {
        // 앱 시작 시 마이크/음성인식 권한을 한 번만 요청
        Task {
            let granted = await speechService.requestAuthorization()
            if granted {
                // 권한 획득 즉시 웨이크워드 시작 (TTS 로드 완료 안 기다림)
                self.startWakeWordIfNeeded()
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
        // 텍스트 처리 중 웨이크워드 충돌 방지
        speechService.stopWakeWordDetection()

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

        // 사용자 컨텍스트 설정 (프로필 존재 시에만 기억/프로필 툴 활성)
        let hasProfiles = !contextService.loadProfiles().isEmpty
        builtInToolService.configureUserContext(
            contextService: hasProfiles ? contextService : nil,
            currentUserId: currentUserId
        )

        // 최근 대화 요약
        let recentSummaries = buildRecentSummaries(for: currentUserId, limit: 5)

        let systemPrompt = settings.buildInstructions(
            currentUserName: currentUserName,
            currentUserId: currentUserId,
            recentSummaries: recentSummaries
        )

        // 내장 도구 서비스 설정 업데이트
        builtInToolService.configure(tavilyApiKey: settings.tavilyApiKey, falaiApiKey: settings.falaiApiKey)

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
        var collectedImageURLs: [URL] = []

        while !currentToolCalls.isEmpty && iteration < maxToolIterations {
            iteration += 1
            Log.tool.info("Tool loop iteration \(iteration), \(currentToolCalls.count) tools to execute")

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
                Log.tool.info("Executing tool: \(toolCall.name)")

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

                    // 이미지 URL 수집 (![image](url) 패턴)
                    collectedImageURLs.append(contentsOf: extractImageURLs(from: toolResult.content))

                    results.append(ToolResult(
                        toolCallId: toolCall.id,
                        content: toolResult.content,
                        isError: toolResult.isError
                    ))
                    Log.tool.info("Tool \(toolCall.name) completed")
                } catch {
                    results.append(ToolResult(
                        toolCallId: toolCall.id,
                        content: "Error: \(error.localizedDescription)",
                        isError: true
                    ))
                    Log.tool.error("Tool \(toolCall.name, privacy: .public) failed: \(error, privacy: .public)")
                }
            }

            currentToolExecution = nil
            state = .processing

            // tool 결과를 메시지로 저장 (대화 히스토리 유지)
            for result in results {
                toolLoopMessages.append(Message(
                    role: .tool,
                    content: result.content,
                    toolCallId: result.toolCallId
                ))
            }

            // tool 결과와 함께 LLM 재호출
            // continuation을 사용해서 다음 응답 대기
            let imageURLs = collectedImageURLs
            currentToolCalls = await withCheckedContinuation { continuation in
                var completed = false

                llmService.onToolCallsReceived = { [weak self] toolCalls in
                    guard self != nil, !completed else { return }
                    completed = true
                    continuation.resume(returning: toolCalls)
                }

                llmService.onResponseComplete = { [weak self] response in
                    guard let self, !completed else { return }
                    completed = true
                    // 최종 응답 - 메시지에 추가 (이미지 URL 포함)
                    self.messages = self.toolLoopMessages
                    self.messages.append(Message(
                        role: .assistant,
                        content: response,
                        imageURLs: imageURLs.isEmpty ? nil : imageURLs
                    ))
                    continuation.resume(returning: [])
                }

                sendLLMRequest(messages: toolLoopMessages, toolResults: nil)
            }
        }

        if iteration >= maxToolIterations {
            Log.tool.error("Tool loop reached max iterations (\(self.maxToolIterations))")
            errorMessage = "도구 실행 횟수가 최대치(\(maxToolIterations))에 도달했습니다."
        }

        // Tool loop 완료 후 콜백 복원
        setupLLMCallbacks()
    }

    /// 마크다운 서식 기호를 제거하여 TTS에 적합한 텍스트로 변환
    static func sanitizeForTTS(_ text: String) -> String {
        var s = text

        // 코드블록 마커 줄은 스킵
        if s.hasPrefix("```") { return "" }

        // 마크다운 이미지 → 제거
        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        // 마크다운 링크 → 텍스트만
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // 인라인 코드 `text` → text
        s = s.replacingOccurrences(of: #"`([^`]*)`"#, with: "$1", options: .regularExpression)

        // 볼드/이탤릭: ***text*** → text, **text** → text, *text* → text
        s = s.replacingOccurrences(of: #"\*{1,3}([^*]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"_{1,3}([^_]+)_{1,3}"#, with: "$1", options: .regularExpression)

        // 헤더 마커 "## 제목" → "제목"
        s = s.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        // 리스트 마커 "- item", "* item"
        s = s.replacingOccurrences(of: #"^[-*+]\s+"#, with: "", options: .regularExpression)
        // 블록인용 "> text"
        s = s.replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression)
        // 수평선
        s = s.replacingOccurrences(of: #"^[-*_]{3,}$"#, with: "", options: .regularExpression)

        // 남은 * 기호 제거 (볼드/이탤릭 잔여)
        s = s.replacingOccurrences(of: "*", with: "")
        // 콜론 → 쉼표 (자연스러운 읽기)
        s = s.replacingOccurrences(of: ":", with: ",")

        // 연속 공백 정리
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractImageURLs(from content: String) -> [URL] {
        let pattern = #"!\[.*?\]\((.*?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)
        return matches.compactMap { match in
            guard let urlRange = Range(match.range(at: 1), in: content) else { return nil }
            return URL(string: String(content[urlRange]))
        }
    }

    private func setupLLMCallbacks() {
        llmService.onResponseComplete = { [weak self] response in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: response))
            self.recoverIfTTSDidNotPlay()
        }

        llmService.onToolCallsReceived = { [weak self] toolCalls in
            guard let self else { return }
            Task {
                await self.executeToolLoop(toolCalls: toolCalls)
            }
        }
    }

    /// TTS가 재생되지 않았을 때 상태 복구 (텍스트 전용 응답 등)
    private func recoverIfTTSDidNotPlay() {
        // TTS가 재생 중이면 onSpeakingComplete에서 처리하므로 여기선 무시
        guard state == .processing else { return }

        state = .idle
        Log.app.info("TTS 미재생 — 상태 복구")

        if isSessionActive {
            startContinuousListening()
        } else {
            startWakeWordIfNeeded()
        }
    }

    // MARK: - Wake Word

    func startWakeWordIfNeeded() {
        guard settings.wakeWordEnabled,
              state == .idle,
              speechService.state == .idle,
              !settings.wakeWord.isEmpty
        else { return }

        Log.stt.info("웨이크워드 자모 매칭 시작: \(self.settings.wakeWord)")
        speechService.startWakeWordDetection(wakeWord: settings.wakeWord)
    }

    func stopWakeWord() {
        speechService.stopWakeWordDetection()
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
                "model": "gpt-4.1-nano",
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
                "model": "claude-haiku-4-5-20251001",
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
        speechService.silenceTimeout = settings.sttSilenceTimeout
        speechService.startContinuousListening(timeout: sessionTimeoutSeconds)
        Log.app.info("연속 대화 STT 시작 (타임아웃: \(self.sessionTimeoutSeconds)초)")
    }

    private func askToEndSession() {
        isAskingToEndSession = true
        speechService.stopListening()
        speechService.stopWakeWordDetection()
        state = .speaking
        supertonicService.speed = settings.ttsSpeed
        supertonicService.diffusionSteps = settings.ttsDiffusionSteps
        supertonicService.speak("대화를 종료할까요?", voice: settings.supertonicVoice)
        Log.app.info("세션 종료 여부 질문")
    }

    private func handleEndSessionResponse(_ response: String) {
        let normalized = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let positiveKeywords = ["응", "어", "예", "네", "그래", "종료", "끝", "됐어", "괜찮아", "ㅇㅇ", "웅", "yes", "yeah", "ok", "okay"]

        if positiveKeywords.contains(where: { normalized.contains($0) }) {
            endSession()
        } else {
            Log.app.info("세션 계속")
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
        speechService.stopListening()
        speechService.stopWakeWordDetection()
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
        Log.app.info("세션 종료")
        isSessionActive = false
        isAskingToEndSession = false

        if !messages.isEmpty {
            let sessionMessages = messages
            let sessionUserId = currentUserId
            Task {
                await saveAndAnalyzeConversation(sessionMessages, userId: sessionUserId)
            }
        }
        messages.removeAll()
        currentConversationId = nil

        // 사용자 상태 리셋
        currentUserId = nil
        currentUserName = nil

        state = .idle
        startWakeWordIfNeeded()
    }

    // MARK: - Push-to-Talk

    func startListening() {
        // 응답 중이면 중단 후 바로 listening 전환 (barge-in)
        switch state {
        case .speaking:
            supertonicService.stopPlayback()
            llmService.cancel()
        case .processing, .executingTool:
            llmService.cancel()
            supertonicService.stopPlayback()
            currentToolExecution = nil
        case .listening:
            return // 이미 듣는 중
        case .idle:
            break
        }
        stopWakeWord()
        isSessionActive = true

        // Push-to-talk: 기본 사용자 할당 (프로필 있을 때)
        if currentUserId == nil {
            let profiles = contextService.loadProfiles()
            if !profiles.isEmpty, let defaultId = settings.defaultUserId,
               let defaultProfile = profiles.first(where: { $0.id == defaultId }) {
                currentUserId = defaultProfile.id
                currentUserName = defaultProfile.name
                Log.app.info("PTT 기본 사용자 할당: \(defaultProfile.name)")
            }
        }

        state = .listening
        speechService.silenceTimeout = settings.sttSilenceTimeout
        speechService.startListening()
    }

    func stopListening() {
        guard state == .listening else { return }
        speechService.stopListening()
    }

    /// 현재 진행 중인 응답(LLM/TTS/도구실행)을 취소하고 마지막 사용자 메시지도 제거
    func cancelResponse() {
        llmService.cancel()
        supertonicService.stopPlayback()
        speechService.stopListening()
        currentToolExecution = nil

        // 마지막 사용자 메시지 제거 (잘못 인식된 입력 되돌리기)
        if let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) {
            // 사용자 메시지 이후에 추가된 assistant 메시지도 같이 제거
            messages.removeSubrange(lastUserIndex...)
        }

        state = .idle
        startWakeWordIfNeeded()
    }

    func clearConversation() {
        if !messages.isEmpty {
            let sessionMessages = messages
            let sessionUserId = currentUserId
            Task {
                await saveAndAnalyzeConversation(sessionMessages, userId: sessionUserId)
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
            let sessionUserId = currentUserId
            Task {
                await saveAndAnalyzeConversation(sessionMessages, userId: sessionUserId)
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
        saveConversationWithTitle(title, summary: nil, userId: currentUserId, messages: messages)
    }

    // MARK: - Session Context Analysis

    private func saveAndAnalyzeConversation(_ sessionMessages: [Message], userId: UUID? = nil) async {
        guard sessionMessages.count >= 2 else { return }

        let hasProfiles = !contextService.loadProfiles().isEmpty
        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !settings.apiKey(for: $0).isEmpty }) else {
            let defaultTitle = generateDefaultTitle(from: sessionMessages)
            await MainActor.run {
                saveConversationWithTitle(defaultTitle, summary: nil, userId: userId, messages: sessionMessages)
            }
            return
        }

        let apiKey = settings.apiKey(for: provider)

        let conversationText = sessionMessages.compactMap { msg -> String? in
            guard msg.role == .user || msg.role == .assistant else { return nil }
            let role = msg.role == .user ? "사용자" : "어시스턴트"
            return "[\(role)] \(msg.content)"
        }.joined(separator: "\n")

        let prompt: String
        if hasProfiles {
            // 다중 사용자 모드: 경량 보완 분석
            let familyMemory = contextService.loadFamilyMemory()
            let personalMemory = userId.map { contextService.loadUserMemory(userId: $0) } ?? ""

            prompt = """
            다음은 방금 끝난 대화입니다:

            \(conversationText)

            ---

            현재 가족 공유 기억:
            \(familyMemory.isEmpty ? "(없음)" : familyMemory)

            현재 개인 기억:
            \(personalMemory.isEmpty ? "(없음)" : personalMemory)

            ---

            JSON으로 출력해주세요:
            1. "title": 대화를 3~10자로 요약한 제목 (한글)
            2. "summary": 대화 내용 1~2문장 요약
            3. "memory": 대화 중 save_memory 도구로 저장되지 않았을 수 있는 보완 기억
               - "family": 가족 전체에 해당하는 새 정보 (없으면 null)
               - "personal": 개인에 해당하는 새 정보 (없으면 null)
               - 이미 기억에 있는 내용이나 대화 중 save_memory로 저장된 내용은 제외

            반드시 아래 형식만 출력:
            {"title": "...", "summary": "...", "memory": {"family": "- 항목" 또는 null, "personal": "- 항목" 또는 null}}
            """
        } else {
            // 레거시 단일 사용자 모드
            let currentContext = contextService.loadMemory()

            prompt = """
            다음은 방금 끝난 대화입니다:

            \(conversationText)

            ---

            현재 저장된 사용자 컨텍스트:
            \(currentContext.isEmpty ? "(없음)" : currentContext)

            ---

            JSON으로 출력해주세요:
            1. "title": 이 대화를 3~10자로 요약한 제목 (한글)
            2. "summary": 대화 내용 1~2문장 요약
            3. "memory": 이 대화에서 새로 알게 된 사실 추출
               - 기존 컨텍스트에 이미 있는 내용은 제외
               - 새로 알게 된 사실이 전혀 없으면 null

            반드시 아래 형식만 출력:
            {"title": "...", "summary": "...", "memory": "- 항목1\\n- 항목2" 또는 null}
            """
        }

        do {
            let response = try await callLLMSimple(provider: provider, apiKey: apiKey, prompt: prompt)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if let jsonData = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                let title = json["title"] as? String ?? generateDefaultTitle(from: sessionMessages)
                let summary = json["summary"] as? String

                await MainActor.run {
                    saveConversationWithTitle(title, summary: summary, userId: userId, messages: sessionMessages)
                }

                if hasProfiles {
                    // 다중 사용자 모드: 보완 기억
                    if let memoryObj = json["memory"] as? [String: Any] {
                        if let familyMemory = memoryObj["family"] as? String, !familyMemory.isEmpty {
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            contextService.appendFamilyMemory("\n<!-- \(timestamp) -->\n\(familyMemory)")
                            Log.app.info("가족 기억 보완: \(familyMemory.prefix(50))...")
                        }
                        if let personalMemory = memoryObj["personal"] as? String, !personalMemory.isEmpty, let uid = userId {
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            contextService.appendUserMemory(userId: uid, content: "\n<!-- \(timestamp) -->\n\(personalMemory)")
                            Log.app.info("개인 기억 보완: \(personalMemory.prefix(50))...")
                        }
                    }
                } else {
                    // 레거시 모드
                    if let memory = json["memory"] as? String, !memory.isEmpty {
                        let timestamp = ISO8601DateFormatter().string(from: Date())
                        let entry = "\n\n<!-- \(timestamp) -->\n\(memory)"
                        contextService.appendMemory(entry)
                        Log.app.info("컨텍스트 추가됨: \(memory.prefix(50))...")

                        await compressContextIfNeeded()
                    }
                }
            } else {
                let defaultTitle = generateDefaultTitle(from: sessionMessages)
                await MainActor.run {
                    saveConversationWithTitle(defaultTitle, summary: nil, userId: userId, messages: sessionMessages)
                }
            }
        } catch {
            Log.app.error("컨텍스트 분석 실패: \(error.localizedDescription, privacy: .public)")
            let defaultTitle = generateDefaultTitle(from: sessionMessages)
            await MainActor.run {
                saveConversationWithTitle(defaultTitle, summary: nil, userId: userId, messages: sessionMessages)
            }
        }
    }

    private func saveConversationWithTitle(_ title: String, summary: String?, userId: UUID?, messages: [Message]) {
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

        Log.app.info("컨텍스트 압축 시작 (현재: \(currentSize) bytes, 제한: \(maxSize) bytes)")

        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !settings.apiKey(for: $0).isEmpty }) else {
            Log.app.warning("컨텍스트 압축 불가: API 키 없음")
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
                Log.app.info("컨텍스트 압축 완료 (\(currentSize) → \(newSize) bytes)")
            }
        } catch {
            Log.app.error("컨텍스트 압축 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}
