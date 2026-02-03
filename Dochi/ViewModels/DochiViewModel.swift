import Foundation
import SwiftUI
import Combine

@MainActor
final class DochiViewModel: ObservableObject {
    // MARK: - Text Mode State

    enum TextModeState: Equatable {
        case idle
        case listening      // SpeechService(STT) 활성
        case processing     // LLM 응답 생성 중
        case speaking       // Supertonic TTS 재생 중
    }

    @Published var messages: [Message] = []
    @Published var errorMessage: String?
    @Published var textModeState: TextModeState = .idle

    var settings: AppSettings
    let realtime: RealtimeService
    let speechService: SpeechService
    let llmService: LLMService
    let supertonicService: SupertonicService

    private var cancellables = Set<AnyCancellable>()
    @Published var wakeWordVariations: [String] = []
    private var lastGeneratedWakeWord: String = ""

    // 연속 대화 모드
    @Published var isSessionActive: Bool = false
    private var sessionTimeoutTimer: Timer?
    private var isAskingToEndSession: Bool = false
    private let sessionTimeoutSeconds: TimeInterval = 10.0

    // MARK: - Computed

    var isTextMode: Bool { settings.appMode == .text }
    var isRealtimeMode: Bool { settings.appMode == .realtime }

    var isConnected: Bool {
        if isRealtimeMode {
            return realtime.state != .disconnected && realtime.state != .connecting
        } else {
            // 텍스트 모드에서는 Supertonic이 ready면 "연결됨"
            return supertonicService.state == .ready || textModeState != .idle
        }
    }

    // MARK: - Init

    init(settings: AppSettings) {
        self.settings = settings
        self.realtime = RealtimeService()
        self.speechService = SpeechService()
        self.llmService = LLMService()
        self.supertonicService = SupertonicService()

        setupRealtimeCallbacks()
        setupTextModeCallbacks()
        setupChangeForwarding()
    }

    private func setupRealtimeCallbacks() {
        realtime.onResponseComplete = { [weak self] transcript in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: transcript))
        }
    }

    private func setupTextModeCallbacks() {
        // 웨이크워드 감지 → 세션 시작
        speechService.onWakeWordDetected = { [weak self] in
            guard let self, self.isTextMode else { return }
            self.isSessionActive = true
            self.textModeState = .listening
            print("[Dochi] 세션 시작")
        }

        // STT 완료 → 응답 처리
        speechService.onQueryCaptured = { [weak self] query in
            guard let self, self.isTextMode else { return }
            self.cancelSessionTimeout()

            // 세션 종료 질문에 대한 응답 처리
            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.handleEndSessionResponse(query)
                return
            }

            // 사용자가 직접 세션 종료 요청
            if self.isSessionActive && self.isEndSessionRequest(query) {
                self.confirmAndEndSession()
                return
            }

            self.handleTextModeQuery(query)
        }

        // STT 무음 타임아웃 (사용자가 아무 말 안함)
        speechService.onSilenceTimeout = { [weak self] in
            guard let self, self.isTextMode, self.isSessionActive else { return }
            self.cancelSessionTimeout()

            // 세션 종료 질문 중이었으면 → 종료로 처리
            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.endSession()
                return
            }

            // 세션 종료 여부 질문
            self.askToEndSession()
        }

        // LLM 문장 단위 → TTS 큐에 즉시 추가
        llmService.onSentenceReady = { [weak self] sentence in
            guard let self, self.isTextMode else { return }
            if self.supertonicService.state == .ready || self.supertonicService.state == .synthesizing || self.supertonicService.state == .playing {
                self.textModeState = .speaking
                self.supertonicService.speed = self.settings.ttsSpeed
                self.supertonicService.diffusionSteps = self.settings.ttsDiffusionSteps
                self.supertonicService.enqueueSentence(sentence, voice: self.settings.supertonicVoice)
            }
        }

        // LLM 응답 완료 → 메시지 히스토리에 추가
        llmService.onResponseComplete = { [weak self] response in
            guard let self, self.isTextMode else { return }
            self.messages.append(Message(role: .assistant, content: response))
        }

        // TTS 큐 재생 완료 → 연속 대화 또는 웨이크워드 대기
        supertonicService.onSpeakingComplete = { [weak self] in
            guard let self else { return }
            self.textModeState = .idle

            if self.isSessionActive {
                // 연속 대화: 바로 STT 시작하고 타임아웃 설정
                self.startContinuousListening()
            } else {
                // 세션 비활성: 웨이크워드 대기
                self.startWakeWordIfNeeded()
            }
        }

        // Supertonic 로드 완료 → 웨이크워드 시작
        supertonicService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, self.isTextMode, state == .ready, self.textModeState == .idle else { return }
                self.startWakeWordIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func setupChangeForwarding() {
        // 자식 ObservableObject 변경 전파
        realtime.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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

    func toggleConnection() {
        if isRealtimeMode {
            if isConnected {
                realtime.disconnect()
            } else {
                connectRealtime()
            }
        } else {
            if supertonicService.state == .ready {
                stopWakeWord()
                supertonicService.tearDown()
                textModeState = .idle
            } else if supertonicService.state == .unloaded {
                connectTextMode()
            }
        }
    }

    private func connectRealtime() {
        let apiKey = settings.apiKey
        guard !apiKey.isEmpty else {
            errorMessage = "OpenAI API 키를 설정해주세요."
            return
        }
        errorMessage = nil
        realtime.connect(
            apiKey: apiKey,
            instructions: settings.buildInstructions(),
            voice: settings.voice
        )
    }

    private func connectTextMode() {
        let provider = settings.llmProvider
        let apiKey = settings.apiKey(for: provider)
        guard !apiKey.isEmpty else {
            errorMessage = "\(provider.displayName) API 키를 설정해주세요."
            return
        }
        errorMessage = nil
        supertonicService.loadIfNeeded(voice: settings.supertonicVoice)
    }

    // MARK: - Mode Switch

    func switchMode(to mode: AppMode) {
        guard mode != settings.appMode else { return }

        // 기존 모드 정리
        if isRealtimeMode {
            realtime.disconnect()
        } else {
            supertonicService.tearDown()
            llmService.cancel()
            speechService.stopListening()
            speechService.stopWakeWordDetection()
            textModeState = .idle
        }

        settings.appMode = mode
    }

    // MARK: - Text Input

    func sendMessage(_ text: String) {
        if isRealtimeMode {
            guard isConnected else {
                errorMessage = "먼저 연결해주세요."
                return
            }
            messages.append(Message(role: .user, content: text))
            realtime.sendTextMessage(text)
        } else {
            handleTextModeQuery(text)
        }
    }

    // MARK: - Text Mode Pipeline

    private func handleTextModeQuery(_ query: String) {
        messages.append(Message(role: .user, content: query))
        textModeState = .processing

        let provider = settings.llmProvider
        let model = settings.llmModel
        let apiKey = settings.apiKey(for: provider)
        let systemPrompt = settings.buildInstructions()

        llmService.sendMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            provider: provider,
            model: model,
            apiKey: apiKey
        )
    }

    // MARK: - Wake Word

    func startWakeWordIfNeeded() {
        guard isTextMode,
              settings.wakeWordEnabled,
              textModeState == .idle,
              speechService.state == .idle,
              !settings.wakeWord.isEmpty
        else { return }

        let wakeWord = settings.wakeWord

        // 캐시된 변형이 있으면 바로 시작
        if wakeWord == lastGeneratedWakeWord, !wakeWordVariations.isEmpty {
            speechService.startWakeWordDetection(phrases: wakeWordVariations)
            return
        }

        // LLM으로 발음 유사 변형 생성
        Task {
            let variations = await generateWakeWordVariations(wakeWord)
            self.wakeWordVariations = variations
            self.lastGeneratedWakeWord = wakeWord
            print("[Dochi] 웨이크워드 변형 (\(variations.count)개): \(variations)")

            // 생성 중 상태가 바뀌지 않았으면 시작
            guard self.isTextMode,
                  self.settings.wakeWordEnabled,
                  self.textModeState == .idle,
                  self.speechService.state == .idle
            else { return }
            self.speechService.startWakeWordDetection(phrases: variations)
        }
    }

    func stopWakeWord() {
        speechService.stopWakeWordDetection()
    }

    private func generateWakeWordVariations(_ wakeWord: String) async -> [String] {
        // 사용 가능한 API 키가 있는 제공자 찾기
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
        textModeState = .listening
        speechService.startContinuousListening(timeout: sessionTimeoutSeconds)
        print("[Dochi] 연속 대화 STT 시작 (타임아웃: \(sessionTimeoutSeconds)초)")
    }

    private func cancelSessionTimeout() {
        sessionTimeoutTimer?.invalidate()
        sessionTimeoutTimer = nil
    }

    private func askToEndSession() {
        isAskingToEndSession = true
        textModeState = .speaking
        supertonicService.speed = settings.ttsSpeed
        supertonicService.diffusionSteps = settings.ttsDiffusionSteps
        supertonicService.speak("대화를 종료할까요?", voice: settings.supertonicVoice)
        print("[Dochi] 세션 종료 여부 질문")
    }

    private func handleEndSessionResponse(_ response: String) {
        let normalized = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let positiveKeywords = ["응", "어", "예", "네", "그래", "종료", "끝", "됐어", "괜찮아", "ㅇㅇ", "웅", "yes", "yeah", "ok", "okay"]

        if positiveKeywords.contains(where: { normalized.contains($0) }) {
            // 긍정 → 세션 종료
            endSession()
        } else {
            // 부정 또는 다른 대화 → 계속
            print("[Dochi] 세션 계속")
            handleTextModeQuery(response)
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
        textModeState = .speaking
        supertonicService.speed = settings.ttsSpeed
        supertonicService.diffusionSteps = settings.ttsDiffusionSteps
        supertonicService.speak("네, 대화를 종료할게요. 다음에 또 불러주세요!", voice: settings.supertonicVoice)

        // TTS 완료 후 세션 종료 (onSpeakingComplete에서 처리되지 않도록 플래그 설정)
        Task {
            // TTS 재생 완료 대기
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
        cancelSessionTimeout()

        // 컨텍스트 분석 후 대화 초기화
        if !messages.isEmpty {
            analyzeSessionForContext()
        }
        messages.removeAll()

        // 웨이크워드 대기로 전환
        textModeState = .idle
        startWakeWordIfNeeded()
    }

    // MARK: - Push-to-Talk (Text Mode)

    func startTextModeListening() {
        guard isTextMode, textModeState == .idle else { return }
        stopWakeWord()
        isSessionActive = true  // 수동 시작도 세션 활성화
        textModeState = .listening
        speechService.startListening()
    }

    func stopTextModeListening() {
        guard isTextMode, textModeState == .listening else { return }
        speechService.stopListening()
        // onQueryCaptured 콜백이 호출되면 handleTextModeQuery로 이동
    }

    // MARK: - User Speech (Realtime)

    func addUserTranscriptToHistory() {
        let text = realtime.userTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            messages.append(Message(role: .user, content: text))
        }
    }

    func clearConversation() {
        // 세션 종료 전 컨텍스트 분석
        if !messages.isEmpty {
            analyzeSessionForContext()
        }

        messages.removeAll()
        if isRealtimeMode && isConnected {
            realtime.disconnect()
            connectRealtime()
        }
    }

    // MARK: - Session Context Analysis

    private func analyzeSessionForContext() {
        let sessionMessages = messages
        guard sessionMessages.count >= 2 else { return }  // 최소 1턴 이상

        Task {
            await extractAndSaveContext(from: sessionMessages)
        }
    }

    private func extractAndSaveContext(from sessionMessages: [Message]) async {
        // 사용 가능한 API 키가 있는 제공자 찾기
        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !settings.apiKey(for: $0).isEmpty }) else {
            return
        }

        let apiKey = settings.apiKey(for: provider)
        let currentContext = ContextService.loadMemory()

        // 대화 내용을 텍스트로 변환
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

        위 대화에서 장기적으로 기억해야 할 사용자 정보가 있다면 추출해주세요.
        - 사용자의 이름, 선호도, 관심사, 중요한 사실 등
        - 이미 저장된 정보와 중복되면 제외
        - 새로 추가하거나 수정할 내용만 마크다운 형식으로 출력
        - 기억할 내용이 없으면 "없음"만 출력
        - 절대 인사말이나 설명 없이 내용만 출력
        """

        do {
            let response = try await callLLMSimple(provider: provider, apiKey: apiKey, prompt: prompt)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            // "없음"이 아니고 의미있는 내용이면 저장
            if !trimmed.isEmpty && trimmed != "없음" && trimmed.count > 3 {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let entry = "\n\n<!-- \(timestamp) -->\n\(trimmed)"
                ContextService.appendMemory(entry)
                print("[Dochi] 컨텍스트 추가됨: \(trimmed.prefix(50))...")

                // 자동 압축 체크
                await compressContextIfNeeded()
            }
        } catch {
            print("[Dochi] 컨텍스트 분석 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Context Compression

    private func compressContextIfNeeded() async {
        guard settings.contextAutoCompress else { return }

        let currentSize = ContextService.memorySize
        let maxSize = settings.contextMaxSize
        guard currentSize > maxSize else { return }

        print("[Dochi] 컨텍스트 압축 시작 (현재: \(currentSize) bytes, 제한: \(maxSize) bytes)")

        // 사용 가능한 API 키가 있는 제공자 찾기
        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !settings.apiKey(for: $0).isEmpty }) else {
            print("[Dochi] 컨텍스트 압축 불가: API 키 없음")
            return
        }

        let apiKey = settings.apiKey(for: provider)
        let currentContext = ContextService.loadMemory()

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
                ContextService.saveMemory(compressed)
                let newSize = ContextService.memorySize
                print("[Dochi] 컨텍스트 압축 완료 (\(currentSize) → \(newSize) bytes)")
            }
        } catch {
            print("[Dochi] 컨텍스트 압축 실패: \(error.localizedDescription)")
        }
    }
}
