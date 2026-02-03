import Foundation
import SwiftUI
import Combine

@MainActor
final class DochiViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case listening      // STT 활성
        case processing     // LLM 응답 생성 중
        case speaking       // TTS 재생 중
    }

    @Published var messages: [Message] = []
    @Published var errorMessage: String?
    @Published var state: State = .idle

    var settings: AppSettings
    let speechService: SpeechService
    let llmService: LLMService
    let supertonicService: SupertonicService

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

    init(settings: AppSettings) {
        self.settings = settings
        self.speechService = SpeechService()
        self.llmService = LLMService()
        self.supertonicService = SupertonicService()

        setupCallbacks()
        setupChangeForwarding()
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
            analyzeSessionForContext()
        }
        messages.removeAll()

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
            analyzeSessionForContext()
        }
        messages.removeAll()
    }

    // MARK: - Session Context Analysis

    private func analyzeSessionForContext() {
        let sessionMessages = messages
        guard sessionMessages.count >= 2 else { return }

        Task {
            await extractAndSaveContext(from: sessionMessages)
        }
    }

    private func extractAndSaveContext(from sessionMessages: [Message]) async {
        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !settings.apiKey(for: $0).isEmpty }) else {
            return
        }

        let apiKey = settings.apiKey(for: provider)
        let currentContext = ContextService.loadMemory()

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

            if !trimmed.isEmpty && trimmed != "없음" && trimmed.count > 3 {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let entry = "\n\n<!-- \(timestamp) -->\n\(trimmed)"
                ContextService.appendMemory(entry)
                print("[Dochi] 컨텍스트 추가됨: \(trimmed.prefix(50))...")

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
