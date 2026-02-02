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
        // STT 완료 → LLM으로 전송
        speechService.onQueryCaptured = { [weak self] query in
            guard let self, self.isTextMode else { return }
            self.handleTextModeQuery(query)
        }

        // LLM 문장 단위 → TTS 큐에 즉시 추가
        llmService.onSentenceReady = { [weak self] sentence in
            guard let self, self.isTextMode else { return }
            if self.supertonicService.state == .ready || self.supertonicService.state == .synthesizing || self.supertonicService.state == .playing {
                self.textModeState = .speaking
                self.supertonicService.enqueueSentence(sentence, voice: self.settings.supertonicVoice)
            }
        }

        // LLM 응답 완료 → 메시지 히스토리에 추가
        llmService.onResponseComplete = { [weak self] response in
            guard let self, self.isTextMode else { return }
            self.messages.append(Message(role: .assistant, content: response))
        }

        // TTS 큐 재생 완료
        supertonicService.onSpeakingComplete = { [weak self] in
            guard let self else { return }
            self.textModeState = .idle
        }
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

    // MARK: - Push-to-Talk (Text Mode)

    func startTextModeListening() {
        guard isTextMode, textModeState == .idle else { return }
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
        messages.removeAll()
        if isRealtimeMode && isConnected {
            realtime.disconnect()
            connectRealtime()
        }
    }
}
