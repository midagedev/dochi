import Foundation
@preconcurrency import Speech
import AVFoundation

@MainActor
final class SpeechService: ObservableObject {
    enum State: Sendable {
        case idle
        case listening
        case waitingForWakeWord
    }

    @Published var state: State = .idle
    @Published var transcript: String = ""
    @Published var wakeWordTranscript: String = ""  // 디버그용: 웨이크워드 모드에서 인식된 텍스트
    @Published var error: String?

    var onQueryCaptured: ((String) -> Void)?

    private nonisolated(unsafe) var audioEngine: AVAudioEngine?
    private nonisolated(unsafe) var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private nonisolated(unsafe) var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var wakeWordRestartTimer: Timer?
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.0  // 1초 무음이면 자동 완료

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Push-to-Talk

    func startListening() {
        guard state == .idle || state == .waitingForWakeWord else { return }
        if state == .waitingForWakeWord { stopWakeWordDetection() }

        transcript = ""
        error = nil
        doStartRecognition(mode: .query)
    }

    func stopListening() {
        guard state == .listening else { return }
        let captured = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        tearDownAudio()
        state = .idle
        if !captured.isEmpty {
            SoundService.playInputComplete()
            onQueryCaptured?(captured)
        }
    }

    // MARK: - Wake Word

    func startWakeWordDetection(wakeWord: String) {
        guard state == .idle else { return }
        wakeWordTranscript = ""
        doStartRecognition(mode: .wakeWord(phrase: wakeWord))
    }

    func stopWakeWordDetection() {
        wakeWordRestartTimer?.invalidate()
        wakeWordRestartTimer = nil
        tearDownAudio()
        state = .idle
    }

    // MARK: - Internal

    private enum RecognitionMode {
        case query
        case wakeWord(phrase: String)
    }

    private func doStartRecognition(mode: RecognitionMode) {
        let available = speechRecognizer?.isAvailable ?? false
        let onDevice = speechRecognizer?.supportsOnDeviceRecognition ?? false
        print("[Dochi] 음성인식 시작 - available: \(available), onDevice: \(onDevice)")

        guard available else {
            error = "음성 인식을 사용할 수 없습니다."
            print("[Dochi] ERROR: 음성 인식 불가")
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 온디바이스가 안 되면 서버 인식 사용
        if onDevice {
            request.requiresOnDeviceRecognition = true
            print("[Dochi] 온디바이스 인식 사용")
        } else {
            print("[Dochi] 서버 인식 사용 (온디바이스 미지원)")
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        print("[Dochi] 오디오 포맷 - sampleRate: \(format.sampleRate), channels: \(format.channelCount)")

        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "오디오 입력 장치를 찾을 수 없습니다."
            print("[Dochi] ERROR: 오디오 포맷 무효")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        self.audioEngine = engine
        self.recognitionRequest = request

        switch mode {
        case .query:
            state = .listening
            beginQueryRecognition(request: request)
        case .wakeWord(let phrase):
            state = .waitingForWakeWord
            print("[Dochi] 웨이크워드 대기: '\(phrase)'")
            beginWakeWordRecognition(request: request, phrase: phrase)
        }

        engine.prepare()
        do {
            try engine.start()
            print("[Dochi] 오디오 엔진 시작 성공")
        } catch {
            self.error = "오디오 엔진 시작 실패: \(error.localizedDescription)"
            print("[Dochi] ERROR: 오디오 엔진 실패 - \(error)")
            tearDownAudio()
            state = .idle
        }
    }

    private func beginQueryRecognition(request: SFSpeechAudioBufferRecognitionRequest) {
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    // 말할 때마다 타이머 리셋 — 무음 2초 후 자동 완료
                    self.resetSilenceTimer()
                }
                if err != nil, self.state == .listening {
                    self.stopListening()
                }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.state == .listening else { return }
                self.stopListening()
            }
        }
    }

    private func beginWakeWordRecognition(request: SFSpeechAudioBufferRecognitionRequest, phrase: String) {
        // 공백 제거한 웨이크워드로 매칭 (인식 결과에 공백이 다르게 들어올 수 있음)
        let targetNormalized = phrase.replacingOccurrences(of: " ", with: "")

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, err in
            DispatchQueue.main.async {
                guard let self, self.state == .waitingForWakeWord else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.wakeWordTranscript = text

                    // 공백 무시하고 비교
                    let normalized = text.replacingOccurrences(of: " ", with: "")
                    if normalized.contains(targetNormalized) {
                        SoundService.playWakeWordDetected()
                        self.stopWakeWordDetection()
                        self.startListening()
                        return
                    }
                }

                if err != nil {
                    let errMsg = (err as NSError?)?.localizedDescription ?? ""
                    // 타임아웃/에러 시 재시작
                    self.tearDownAudio()
                    self.wakeWordTranscript = "재시작 중... (\(errMsg))"
                    self.wakeWordRestartTimer = Timer.scheduledTimer(
                        withTimeInterval: 0.5, repeats: false
                    ) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.state = .idle
                            self.startWakeWordDetection(wakeWord: phrase)
                        }
                    }
                }
            }
        }
    }

    private func tearDownAudio() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
