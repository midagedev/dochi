import Foundation
import SwiftUI

/// Orchestrates the Dochi voice + 3D-character front-end.
///
/// Dochi owns what the user *sees and hears* — Korean STT, TTS, and the VRM
/// avatar's state. All reasoning, memory, and tools live in the Hermes Agent
/// backend, reached through ``HermesAgentBridge``. The voice loop is:
///
///   STT (final transcript) ─▶ Hermes ─▶ streamed deltas ─▶ sentence chunker
///   ─▶ TTS (sentence-by-sentence) ─▶ avatar lip-sync ─▶ back to listening.
@MainActor
@Observable
final class DochiViewModel {
    // MARK: - Interaction State

    private(set) var interactionState: InteractionState = .idle
    private(set) var sessionState: SessionState = .inactive
    private(set) var processingSubState: ProcessingSubState?

    // MARK: - Conversation Data

    var currentConversation: Conversation?
    var conversations: [Conversation] = []
    var streamingText: String = ""
    var inputText: String = ""
    var errorMessage: String?
    var currentToolName: String?
    var partialTranscript: String = ""

    /// Tool runs surfaced by Hermes, shown inline in the transcript (UX-7).
    var toolExecutions: [ToolExecution] = []

    // MARK: - Backend Connection (mirrored for UI)

    private(set) var hermesConnection: HermesConnectionState = .disconnected

    // MARK: - TTS Fallback State (driven by TTSRouter)

    var isTTSFallbackActive: Bool = false
    var ttsFallbackProviderName: String?

    // MARK: - Services

    let settings: AppSettings
    private let speechService: SpeechServiceProtocol
    private var ttsService: TTSServiceProtocol
    private let soundService: SoundServiceProtocol
    private let conversationService: ConversationServiceProtocol
    let hermesBridge: HermesBridgeProtocol

    // MARK: - Internal

    private var processingTask: Task<Void, Never>?
    private var sessionTimeoutTask: Task<Void, Never>?
    private var sentenceChunker = SentenceChunker()
    /// True while assistant text is still streaming, so a TTS queue that drains
    /// mid-stream does not prematurely end the turn.
    private var expectingMoreSpeech = false
    private var isBackgroundListening = false
    private var toolExecutionsByName: [String: ToolExecution] = [:]
    private static let sessionEndingTimeout: TimeInterval = 10

    // MARK: - Computed

    var isVoiceMode: Bool { settings.currentInteractionMode == .voiceAndText }
    var isMicAuthorized: Bool { speechService.isAuthorized }
    var fontSize: Double { settings.chatFontSize }
    var messages: [Message] { currentConversation?.messages ?? [] }

    // MARK: - Init

    init(
        settings: AppSettings,
        speechService: SpeechServiceProtocol,
        ttsService: TTSServiceProtocol,
        soundService: SoundServiceProtocol,
        conversationService: ConversationServiceProtocol,
        hermesBridge: HermesBridgeProtocol
    ) {
        self.settings = settings
        self.speechService = speechService
        self.ttsService = ttsService
        self.soundService = soundService
        self.conversationService = conversationService
        self.hermesBridge = hermesBridge

        self.ttsService.onComplete = { [weak self] in
            self?.handleTTSComplete()
        }
        if let router = ttsService as? TTSRouter {
            router.onFallbackStateChanged = { [weak self] active, providerName in
                self?.isTTSFallbackActive = active
                self?.ttsFallbackProviderName = providerName
            }
        }

        self.hermesConnection = hermesBridge.connectionState
        self.hermesBridge.onConnectionStateChanged = { [weak self] state in
            self?.hermesConnection = state
        }
        self.hermesBridge.onProactiveMessage = { [weak self] message in
            self?.injectProactiveMessage(message)
        }
    }

    func connectBackend() {
        hermesBridge.connect()
    }

    /// Re-point the bridge at the host/port currently in settings and reconnect.
    func reconnectBackend() {
        hermesBridge.reconfigure(host: settings.hermesBridgeHost, port: settings.hermesBridgePort)
    }

    // MARK: - State Machine

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
        if to == .listening && from == .speaking { return false }
        if to == .processing && sessionState == .ending { return false }
        switch (from, to) {
        case (.idle, .processing), (.idle, .listening),
             (.listening, .processing), (.listening, .idle),
             (.processing, .speaking), (.processing, .idle),
             (.speaking, .idle), (.speaking, .listening):
            return true
        default:
            return false
        }
    }

    private func setSessionState(_ newState: SessionState) {
        let old = sessionState
        sessionState = newState
        Log.app.info("Session: \(String(describing: old)) → \(String(describing: newState))")
    }

    // MARK: - Text Send

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Barge-in: typing while Dochi is talking interrupts speech.
        if interactionState == .speaking {
            ttsService.stopAndClear()
            transition(to: .idle)
        }
        guard interactionState == .idle else {
            Log.app.warning("Cannot send: not idle (\(String(describing: self.interactionState)))")
            return
        }

        inputText = ""
        ensureConversation()
        appendUserMessage(text)
        transition(to: .processing)
        processingSubState = .streaming
        processingTask = Task { [weak self] in
            await self?.processHermesPath(input: text)
        }
    }

    func cancelRequest() {
        processingTask?.cancel()
        processingTask = nil
        ttsService.stopAndClear()
        sentenceChunker = SentenceChunker()
        expectingMoreSpeech = false
        if !streamingText.isEmpty {
            appendAssistantMessage(streamingText)
            streamingText = ""
            saveConversation()
        }
        processingSubState = nil
        currentToolName = nil
        if interactionState != .idle { transition(to: .idle) }
        Log.app.info("Request cancelled by user")
    }

    // MARK: - Hermes Streaming Path

    private func processHermesPath(input: String) async {
        guard !Task.isCancelled else { return }
        guard case .connected = hermesBridge.connectionState else {
            errorMessage = "Hermes 에이전트에 연결되어 있지 않습니다. 브리지(dochi-hermes-bridge)가 실행 중인지 확인해주세요."
            failTurn()
            return
        }

        let conversationId = currentConversation?.id.uuidString ?? UUID().uuidString
        let user = settings.defaultUserId.isEmpty ? nil : settings.defaultUserId

        streamingText = ""
        sentenceChunker = SentenceChunker()
        expectingMoreSpeech = isVoiceMode
        toolExecutionsByName.removeAll()
        var fullText = ""
        var startedSpeaking = false

        do {
            for try await event in hermesBridge.send(text: input, conversationId: conversationId, user: user) {
                guard !Task.isCancelled else { break }
                switch event {
                case .delta(let chunk):
                    fullText += chunk
                    streamingText += chunk
                    if isVoiceMode {
                        for sentence in sentenceChunker.append(chunk) {
                            if enqueueSpeechSentence(sentence) {
                                startSpeakingIfNeeded(&startedSpeaking)
                            }
                        }
                    }
                case .toolStarted(let name, let summary):
                    processingSubState = .toolCalling
                    currentToolName = name
                    beginToolExecution(name: name, summary: summary)
                case .toolFinished(let name, let isError, let summary):
                    endToolExecution(name: name, isError: isError, summary: summary)
                    currentToolName = nil
                    processingSubState = isError ? .toolError : .streaming
                case .done(let text, _):
                    if !text.isEmpty { fullText = text }
                }
            }
        } catch is CancellationError {
            // handled by cancelRequest()
            return
        } catch {
            errorMessage = error.localizedDescription
            Log.app.error("Hermes path error: \(error.localizedDescription)")
        }

        expectingMoreSpeech = false

        if isVoiceMode, let tail = sentenceChunker.flush() {
            if enqueueSpeechSentence(tail) {
                startSpeakingIfNeeded(&startedSpeaking)
            }
        }

        appendAssistantMessage(fullText)
        streamingText = ""
        saveConversation()

        if startedSpeaking {
            // Speech queued. If audio is still playing, handleTTSComplete()
            // advances the turn; otherwise advance now.
            if !ttsService.isSpeaking { advanceAfterSpeaking() }
        } else {
            // Text mode, or an empty/silent reply: no speech to wait on.
            processingSubState = nil
            currentToolName = nil
            if interactionState != .idle { transition(to: .idle) }
            if isVoiceMode && (sessionState == .active || sessionState == .ending) {
                startListening()
            }
        }
    }

    private func startSpeakingIfNeeded(_ started: inout Bool) {
        guard !started else { return }
        started = true
        if interactionState == .processing { transition(to: .speaking) }
    }

    private func failTurn() {
        processingSubState = nil
        currentToolName = nil
        if interactionState != .idle { transition(to: .idle) }
    }

    // MARK: - Tool Execution Tracking

    private func beginToolExecution(name: String, summary: String?) {
        let execution = ToolExecution(
            toolName: name,
            toolCallId: UUID().uuidString,
            displayName: name,
            inputSummary: summary ?? "",
            loopIndex: 0
        )
        toolExecutionsByName[name] = execution
        toolExecutions.append(execution)
    }

    private func endToolExecution(name: String, isError: Bool, summary: String?) {
        guard let execution = toolExecutionsByName[name] else { return }
        if isError {
            execution.fail(errorSummary: summary ?? "오류", errorFull: summary ?? "오류")
        } else {
            execution.complete(resultSummary: summary ?? "완료", resultFull: summary ?? "완료")
        }
    }

    // MARK: - Voice Actions

    /// Start listening via STT (triggered by wake word or UI button).
    func startListening() {
        guard interactionState == .idle else {
            Log.app.warning("Cannot start listening: not idle")
            return
        }
        guard speechService.isAuthorized else {
            Task { [weak self] in
                guard let self else { return }
                if await self.speechService.requestAuthorization() {
                    self.startListening()
                } else {
                    self.errorMessage = "마이크 및 음성 인식 권한이 필요합니다. 시스템 설정에서 허용해주세요."
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
            onPartialResult: { [weak self] text in self?.partialTranscript = text },
            onFinalResult: { [weak self] text in self?.handleSpeechFinalResult(text) },
            onError: { [weak self] error in self?.handleSpeechError(error) }
        )
    }

    func stopListening() {
        speechService.stopListening()
        partialTranscript = ""
        if interactionState == .listening { transition(to: .idle) }
    }

    /// Barge-in: user interrupts while Dochi is speaking.
    func handleBargeIn() {
        guard interactionState == .speaking else { return }
        ttsService.stopAndClear()
        transition(to: .idle)
        Log.app.info("Barge-in: TTS stopped")
        if isVoiceMode { startListening() }
    }

    /// End the voice session manually.
    func endVoiceSession() {
        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = nil
        speechService.stopListening()
        ttsService.stopAndClear()
        partialTranscript = ""
        if interactionState != .idle {
            interactionState = .idle
            processingSubState = nil
            currentToolName = nil
        }
        setSessionState(.inactive)
        saveConversation()
        newConversation()
        Log.app.info("Voice session ended")
    }

    /// Preload the TTS engine when entering voice mode.
    func prepareTTSEngine() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ttsService.loadEngine()
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
            if sessionState == .active { startListening() }
            return
        }

        soundService.playInputComplete()

        if isSessionEndCommand(trimmed) {
            beginSessionEnding()
            return
        }

        let cleanedText = stripWakeWord(from: trimmed)
        guard !cleanedText.isEmpty else {
            if sessionState == .active { startListening() } else { transition(to: .idle) }
            return
        }

        ensureConversation()
        appendUserMessage(cleanedText)
        transition(to: .processing)
        processingSubState = .streaming
        processingTask = Task { [weak self] in
            await self?.processHermesPath(input: cleanedText)
        }
    }

    private func handleSpeechError(_ error: Error) {
        partialTranscript = ""
        Log.stt.error("Speech error: \(error.localizedDescription)")
        errorMessage = "음성 입력 실패: \(error.localizedDescription)"
        if interactionState == .listening { transition(to: .idle) }

        let shouldRetry: Bool
        if let speechError = error as? SpeechServiceError {
            switch speechError {
            case .audioEngineFailure, .recognizerUnavailable, .noInputDevice, .noSpeechDetected:
                shouldRetry = false
            case .recognitionFailed:
                shouldRetry = true
            }
        } else {
            shouldRetry = true
        }
        if sessionState == .active && shouldRetry { startListening() }
    }

    // MARK: - TTS Integration

    private func handleTTSComplete() {
        guard interactionState == .speaking else { return }
        guard !expectingMoreSpeech else { return }  // more sentences still streaming
        advanceAfterSpeaking()
    }

    private func advanceAfterSpeaking() {
        transition(to: .idle)
        if sessionState == .active || sessionState == .ending {
            startListening()
        }
    }

    private func enqueueTTS(_ text: String) {
        guard isVoiceMode else { return }
        let speechText = Self.speechText(from: text)
        guard !speechText.isEmpty else { return }
        if interactionState == .idle { transition(to: .processing) }
        if interactionState == .processing { transition(to: .speaking) }
        ttsService.enqueueSentence(speechText)
    }

    @discardableResult
    private func enqueueSpeechSentence(_ text: String) -> Bool {
        let speechText = Self.speechText(from: text)
        guard !speechText.isEmpty else { return false }
        ttsService.enqueueSentence(speechText)
        return true
    }

    // MARK: - Session End

    private func isSessionEndCommand(_ text: String) -> Bool {
        let endPhrases = ["대화 종료", "그만할게", "그만 할게", "끝낼게", "종료"]
        return endPhrases.contains(where: { text.contains($0) })
    }

    private func beginSessionEnding() {
        setSessionState(.ending)
        expectingMoreSpeech = false
        enqueueTTS("대화를 종료할까요?")
        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.sessionEndingTimeout))
            guard !Task.isCancelled else { return }
            self?.endVoiceSession()
        }
    }

    // MARK: - Wake Word

    private func stripWakeWord(from text: String) -> String {
        let wakeWord = settings.wakeWord
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.hasPrefix(wakeWord) else { return stripped }
        let remaining = String(stripped.dropFirst(wakeWord.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if remaining.hasPrefix(",") || remaining.hasPrefix("，") {
            return String(remaining.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return remaining
    }

    func startBackgroundWakeWordListener() {
        guard settings.wakeWordEnabled, settings.wakeWordAlwaysOn else { return }
        guard !isBackgroundListening, interactionState == .idle else { return }
        guard speechService.isAuthorized else {
            Task { [weak self] in
                guard let self else { return }
                if await self.speechService.requestAuthorization() {
                    self.startBackgroundWakeWordListener()
                } else {
                    self.errorMessage = "웨이크워드를 사용하려면 마이크 및 음성 인식 권한이 필요합니다."
                }
            }
            return
        }

        isBackgroundListening = true
        Log.app.info("Starting background wake word listener")
        speechService.startContinuousRecognition(
            onPartialResult: { [weak self] text in
                guard let self else { return }
                if self.settings.wakeWordEnabled,
                   JamoMatcher.isMatch(transcript: text, wakeWord: self.settings.wakeWord) {
                    self.stopBackgroundWakeWordListener()
                    self.startListening()
                }
            },
            onError: { _ in }
        )
    }

    func stopBackgroundWakeWordListener() {
        guard isBackgroundListening else { return }
        isBackgroundListening = false
        speechService.stopContinuousRecognition()
        Log.app.info("Stopped background wake word listener")
    }

    // MARK: - Proactive

    /// Inject a server-initiated (Hermes proactive) message into the conversation.
    func injectProactiveMessage(_ message: String) {
        ensureConversation()
        guard var conversation = currentConversation else { return }
        let visualContent = Self.extractVisualContent(from: message)
        conversation.messages.append(Message(
            role: .assistant,
            content: visualContent.text,
            imageURLs: visualContent.imageURLs.nilIfEmpty
        ))
        conversation.updatedAt = Date()
        currentConversation = conversation
        conversationService.save(conversation: conversation)
        Log.app.info("Injected proactive message")
        if isVoiceMode && interactionState == .idle {
            expectingMoreSpeech = false
            enqueueTTS(message)
        }
    }

    // MARK: - Conversation CRUD

    func newConversation() {
        currentConversation = Conversation(userId: settings.defaultUserId.isEmpty ? nil : settings.defaultUserId)
        streamingText = ""
        toolExecutions = []
    }

    func loadConversations() {
        conversations = conversationService.list()
    }

    func selectConversation(id: UUID) {
        guard let conversation = conversationService.load(id: id) else { return }
        currentConversation = conversation
        toolExecutions = []
    }

    func deleteConversation(id: UUID) {
        conversationService.delete(id: id)
        if currentConversation?.id == id { newConversation() }
        loadConversations()
    }

    private func ensureConversation() {
        if currentConversation == nil {
            currentConversation = Conversation(userId: settings.defaultUserId.isEmpty ? nil : settings.defaultUserId)
        }
    }

    private func appendUserMessage(_ text: String, imageData: [ImageContent]? = nil) {
        currentConversation?.messages.append(Message(role: .user, content: text, imageData: imageData))
        currentConversation?.updatedAt = Date()
    }

    private func appendAssistantMessage(_ text: String) {
        let visualContent = Self.extractVisualContent(from: text)
        guard !visualContent.text.isEmpty || !visualContent.imageURLs.isEmpty else { return }
        currentConversation?.messages.append(Message(
            role: .assistant,
            content: visualContent.text,
            imageURLs: visualContent.imageURLs.nilIfEmpty
        ))
        currentConversation?.updatedAt = Date()
    }

    private static func extractVisualContent(from text: String) -> (text: String, imageURLs: [URL]) {
        var imageURLs: [URL] = []
        var seen = Set<String>()

        func appendImage(_ rawValue: String) {
            let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: " \n\r\t\"'<>"))
            guard !trimmed.isEmpty, let url = imageURL(from: trimmed) else { return }
            let key = url.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            imageURLs.append(url)
        }

        var cleaned = text

        // Markdown image syntax is the preferred Hermes output shape:
        // ![description](https://.../image.png) or ![description](/path/image.png)
        let markdownPattern = ##"!\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)"##
        if let regex = try? NSRegularExpression(pattern: markdownPattern) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                appendImage(nsText.substring(with: match.range(at: 1)))
            }
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(location: 0, length: (cleaned as NSString).length),
                withTemplate: ""
            )
        }

        // Tool JSON can leak into the final answer; preserve the image even if
        // Hermes forgets to wrap it in Markdown.
        let jsonImagePattern = ##""image"\s*:\s*"([^"]+)""##
        if let regex = try? NSRegularExpression(pattern: jsonImagePattern) {
            let nsText = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                guard match.numberOfRanges > 1 else { continue }
                appendImage(nsText.substring(with: match.range(at: 1)))
            }
        }

        let bareURLPattern = ##"https?://[^\s\]\)"']+"##
        if let regex = try? NSRegularExpression(pattern: bareURLPattern) {
            let nsText = cleaned as NSString
            var rangesToRemove: [NSRange] = []
            for match in regex.matches(in: cleaned, range: NSRange(location: 0, length: nsText.length)) {
                let candidate = nsText.substring(with: match.range)
                if isLikelyGeneratedImage(candidate) {
                    appendImage(candidate)
                    rangesToRemove.append(match.range)
                }
            }
            if !rangesToRemove.isEmpty {
                let mutable = NSMutableString(string: cleaned)
                for range in rangesToRemove.reversed() {
                    mutable.replaceCharacters(in: range, with: "")
                }
                cleaned = String(mutable)
            }
        }

        let filePathPattern = ##"/(?:Users|private|tmp|var)/[^\s\]\)"']+\.(?:png|jpg|jpeg|webp|gif)"##
        if let regex = try? NSRegularExpression(pattern: filePathPattern, options: [.caseInsensitive]) {
            let nsText = cleaned as NSString
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                appendImage(nsText.substring(with: match.range))
            }
            if !matches.isEmpty {
                let mutable = NSMutableString(string: cleaned)
                for match in matches.reversed() {
                    mutable.replaceCharacters(in: match.range, with: "")
                }
                cleaned = String(mutable)
            }
        }

        // Some tools return file URLs instead of absolute POSIX paths.
        let fileURLPattern = ##"file://[^\s\]\)"']+\.(?:png|jpg|jpeg|webp|gif)"##
        if let regex = try? NSRegularExpression(pattern: fileURLPattern, options: [.caseInsensitive]) {
            let nsText = cleaned as NSString
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                appendImage(nsText.substring(with: match.range))
            }
            if !matches.isEmpty {
                let mutable = NSMutableString(string: cleaned)
                for match in matches.reversed() {
                    mutable.replaceCharacters(in: match.range, with: "")
                }
                cleaned = String(mutable)
            }
        }

        // Collapse leftover empty JSON shells from tool output when the image
        // field was the only meaningful content.
        let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !imageURLs.isEmpty,
           trimmedCleaned.hasPrefix("{"),
           trimmedCleaned.hasSuffix("}") {
            cleaned = ""
        }

        cleaned = cleaned
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned, imageURLs)
    }

    private static func imageURL(from rawValue: String) -> URL? {
        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue)
        }
        if rawValue.hasPrefix("~/") {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(rawValue.dropFirst(2)))
                .path
            return URL(fileURLWithPath: path)
        }
        guard let url = URL(string: rawValue) else { return nil }
        if url.scheme == "http" || url.scheme == "https" || url.isFileURL {
            return url
        }
        return nil
    }

    private static func isLikelyGeneratedImage(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue) else { return false }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "webp", "gif"].contains(ext) { return true }
        let host = url.host?.lowercased() ?? ""
        if host.contains("fal.media") || host.contains("fal.ai") { return true }
        return url.path.lowercased().contains("image")
    }

    private static func speechText(from text: String) -> String {
        var cleaned = extractVisualContent(from: text).text

        let patterns = [
            ##"!\[[^\]]*(?:\]\([^)]*)?"##,
            ##"https?://[^\s\]\)"']+"##,
            ##"file://[^\s\]\)"']+"##,
            ##"/(?:Users|private|tmp|var)/[^\s\]\)"']+\.(?:png|jpg|jpeg|webp|gif)"##,
            ##"\b[\w.-]+\.(?:png|jpg|jpeg|webp|gif)\b"##,
            ##""image"\s*:\s*"[^"]+""##,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(location: 0, length: (cleaned as NSString).length),
                    withTemplate: ""
                )
            }
        }

        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            cleaned = ""
        }

        return cleaned
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
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
}

private extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}
