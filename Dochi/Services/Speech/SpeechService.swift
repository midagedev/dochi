import AVFoundation
import Foundation
import os
import Speech

@MainActor
final class SpeechService: SpeechServiceProtocol {

    // MARK: - Protocol properties

    private(set) var isAuthorized: Bool = false
    private(set) var isListening: Bool = false

    // MARK: - Private state

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?

    /// Tracks the last raw partial transcription to detect new speech activity.
    private var lastTranscription: String = ""

    /// Stores the best transcription obtained so far during a session.
    private var bestTranscription: String = ""

    /// Callbacks kept for the duration of a listening session.
    private var onPartialResult: (@MainActor (String) -> Void)?
    private var onFinalResult: (@MainActor (String) -> Void)?
    private var onError: (@MainActor (Error) -> Void)?

    // MARK: - Init

    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
        Log.stt.info("SpeechService initialised with locale ko-KR")
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let status = await Self.requestSpeechAuthorizationStatus()

        switch status {
        case .authorized:
            isAuthorized = true
            Log.stt.info("Speech recognition authorised")
        case .denied:
            isAuthorized = false
            Log.stt.warning("Speech recognition denied by user")
        case .restricted:
            isAuthorized = false
            Log.stt.warning("Speech recognition restricted on this device")
        case .notDetermined:
            isAuthorized = false
            Log.stt.warning("Speech recognition authorisation not determined")
        @unknown default:
            isAuthorized = false
            Log.stt.warning("Speech recognition authorisation unknown status")
        }

        return isAuthorized
    }

    /// Requests speech authorization outside MainActor isolation because the
    /// framework callback may arrive on a background queue.
    nonisolated private static func requestSpeechAuthorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Builds a tap handler outside MainActor isolation because the audio tap is
    /// invoked on a realtime audio queue.
    nonisolated private static func makeInputTapHandler(
        for request: SFSpeechAudioBufferRecognitionRequest
    ) -> AVAudioNodeTapBlock {
        { [weak request] buffer, _ in
            request?.append(buffer)
        }
    }

    // MARK: - Start listening

    func startListening(
        silenceTimeout: TimeInterval,
        onPartialResult: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        guard !isListening else {
            Log.stt.warning("startListening called while already listening — ignoring")
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            Log.stt.error("SFSpeechRecognizer unavailable")
            onError(SpeechServiceError.recognizerUnavailable)
            return
        }

        // Store callbacks
        self.onPartialResult = onPartialResult
        self.onFinalResult = onFinalResult
        self.onError = onError
        self.lastTranscription = ""
        self.bestTranscription = ""

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device recognition for privacy; fall back to server if unsupported.
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            Log.stt.info("Using on-device recognition")
        } else {
            request.requiresOnDeviceRecognition = false
            Log.stt.info("On-device recognition not available — using server")
        }

        self.recognitionRequest = request

        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        let tapHandler = Self.makeInputTapHandler(for: request)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat, block: tapHandler)

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            Log.stt.error("Failed to start audio engine: \(error.localizedDescription)")
            cleanup()
            onError(SpeechServiceError.audioEngineFailure(error))
            return
        }

        isListening = true
        Log.stt.info("Started listening (silence timeout: \(silenceTimeout)s)")

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognitionResult(result, error: error, silenceTimeout: silenceTimeout)
            }
        }

        // Start the silence timer
        resetSilenceTimer(timeout: silenceTimeout)
    }

    // MARK: - Stop listening

    func stopListening() {
        guard isListening else { return }
        Log.stt.info("stopListening called — delivering final result")
        deliverFinalResult()
    }

    // MARK: - Recognition result handling

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?,
        silenceTimeout: TimeInterval
    ) {
        if let error {
            // Cancelled tasks produce error code 216 / 1110 — not a real error
            let nsError = error as NSError
            if nsError.code == 216 || nsError.code == 1110 {
                Log.stt.debug("Recognition task ended (code \(nsError.code))")
                return
            }

            Log.stt.error("Recognition error: \(error.localizedDescription)")
            let callback = onError
            cleanup()
            callback?(SpeechServiceError.recognitionFailed(error))
            return
        }

        guard let result else { return }

        let rawText = result.bestTranscription.formattedString
        let mergedText = mergeTranscription(previous: bestTranscription, current: rawText)
        bestTranscription = mergedText
        onPartialResult?(mergedText)

        if rawText != lastTranscription {
            lastTranscription = rawText
            resetSilenceTimer(timeout: silenceTimeout)
        }

        if result.isFinal {
            Log.stt.info("Recognition returned final result")
            deliverFinalResult()
        }
    }

    // MARK: - Silence timer

    private func resetSilenceTimer(timeout: TimeInterval) {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
            } catch {
                // Task was cancelled — normal when timer is reset or listening stops
                return
            }

            guard let self, self.isListening else { return }
            Log.stt.info("Silence timeout reached (\(timeout)s)")
            // Keep session open while waiting for first utterance.
            // Otherwise voice mode can loop stop/start with empty results.
            if self.bestTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.resetSilenceTimer(timeout: timeout)
                return
            }
            self.deliverFinalResult()
        }
    }

    // MARK: - Deliver final result and cleanup

    private func deliverFinalResult() {
        let text = bestTranscription
        let callback = onFinalResult

        cleanup()

        if !text.isEmpty {
            Log.stt.info("Final transcription (\(text.count) chars)")
            callback?(text)
        } else {
            Log.stt.info("No speech detected — delivering empty result")
            callback?("")
        }
    }

    /// Keeps previously spoken text when recognizer partials shrink/regress.
    /// This reduces "earlier sentence disappeared" behavior after a short pause.
    private func mergeTranscription(previous: String, current: String) -> String {
        let prev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let curr = current.trimmingCharacters(in: .whitespacesAndNewlines)

        if prev.isEmpty { return curr }
        if curr.isEmpty { return prev }
        if curr == prev { return prev }

        // Normalize spacing for containment checks to avoid false mismatches.
        let normalizedPrev = prev.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let normalizedCurr = curr.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if normalizedCurr.contains(normalizedPrev) { return curr }
        if normalizedPrev.contains(normalizedCurr) { return prev }

        // If both hypotheses start similarly, prefer the longer one
        // instead of concatenating (prevents duplicated prefixes).
        let commonPrefixCount = zip(prev, curr).prefix(while: { $0 == $1 }).count
        let shortestLength = min(prev.count, curr.count)
        if shortestLength > 0 && Double(commonPrefixCount) / Double(shortestLength) >= 0.5 {
            return curr.count >= prev.count ? curr : prev
        }

        // Append only when we have a meaningful suffix/prefix overlap.
        let prevChars = Array(prev)
        let currChars = Array(curr)
        let maxOverlap = min(prevChars.count, currChars.count)

        if maxOverlap > 0 {
            for overlap in stride(from: maxOverlap, through: 1, by: -1) {
                let prevSuffix = prevChars.suffix(overlap)
                let currPrefix = currChars.prefix(overlap)
                if prevSuffix.elementsEqual(currPrefix) && overlap >= 4 {
                    return prev + String(currChars.dropFirst(overlap))
                }
            }
        }

        // Fallback: keep the longer candidate; do not force concatenation.
        return curr.count >= prev.count ? curr : prev
    }

    // MARK: - Continuous Recognition (Wake Word Detection)

    private var continuousTask: Task<Void, Never>?
    private var continuousOnPartial: (@MainActor (String) -> Void)?
    private var continuousOnError: (@MainActor (Error) -> Void)?
    private var isContinuousMode = false

    func startContinuousRecognition(
        onPartialResult: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        guard !isContinuousMode else {
            Log.stt.warning("Continuous recognition already active")
            return
        }

        isContinuousMode = true
        continuousOnPartial = onPartialResult
        continuousOnError = onError

        Log.stt.info("Starting continuous recognition for wake word detection")
        startContinuousSession()
    }

    func stopContinuousRecognition() {
        guard isContinuousMode else { return }
        isContinuousMode = false
        continuousTask?.cancel()
        continuousTask = nil
        continuousOnPartial = nil
        continuousOnError = nil

        if isListening {
            cleanup()
        }
        Log.stt.info("Continuous recognition stopped")
    }

    private func startContinuousSession() {
        guard isContinuousMode else { return }

        // Use a very long silence timeout (effectively no timeout)
        startListening(
            silenceTimeout: 55, // Restart before Apple's ~60s limit
            onPartialResult: { [weak self] text in
                self?.continuousOnPartial?(text)
            },
            onFinalResult: { [weak self] _ in
                // Session ended (silence timeout or Apple limit) — restart
                guard let self, self.isContinuousMode else { return }
                Log.stt.debug("Continuous recognition session ended, restarting...")
                self.continuousTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self?.startContinuousSession()
                }
            },
            onError: { [weak self] error in
                guard let self, self.isContinuousMode else { return }
                self.continuousOnError?(error)
                // Retry after delay
                self.continuousTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self?.startContinuousSession()
                }
            }
        )
    }

    // MARK: - Cleanup

    private func cleanup() {
        silenceTimer?.cancel()
        silenceTimer = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        isListening = false
        onPartialResult = nil
        onFinalResult = nil
        onError = nil

        Log.stt.debug("Cleanup completed")
    }
}

// MARK: - Errors

enum SpeechServiceError: LocalizedError {
    case recognizerUnavailable
    case audioEngineFailure(Error)
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "음성 인식기를 사용할 수 없습니다."
        case .audioEngineFailure(let underlying):
            return "오디오 엔진 시작 실패: \(underlying.localizedDescription)"
        case .recognitionFailed(let underlying):
            return "음성 인식 실패: \(underlying.localizedDescription)"
        }
    }
}
