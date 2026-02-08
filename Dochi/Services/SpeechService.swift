import Foundation
@preconcurrency import Speech
import AVFoundation
import os

@MainActor
final class SpeechService: ObservableObject {
    enum State: Sendable {
        case idle
        case listening
        case waitingForWakeWord
    }

    @Published var state: State = .idle
    @Published var transcript: String = ""
    /// 인식기 리셋 시 보존된 이전 텍스트
    private var preservedTranscript: String = ""
    @Published var wakeWordTranscript: String = ""  // 디버그용: 웨이크워드 모드에서 인식된 텍스트
    @Published var error: String?

    var onQueryCaptured: ((String) -> Void)?
    var onWakeWordDetected: ((String) -> Void)?  // transcript 전달
    var onSilenceTimeout: (() -> Void)?
    var onListeningCancelled: (() -> Void)?

    private nonisolated(unsafe) var audioEngine: AVAudioEngine?
    private nonisolated(unsafe) var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private nonisolated(unsafe) var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var wakeWordRestartTimer: Timer?
    private var silenceTimer: Timer?
    var silenceTimeout: TimeInterval = 1.0  // 무음 후 자동 완료까지 대기 시간
    private var continuousListeningTimeout: TimeInterval = 10.0
    private var isContinuousMode: Bool = false
    private let soundService: SoundServiceProtocol
    private var authorizationGranted = false

    init(soundService: SoundServiceProtocol = SoundService()) {
        self.soundService = soundService
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    }

    // MARK: - Authorization

    /// 마이크 + 음성인식 권한을 한 번에 요청. 앱 시작 시 호출.
    func requestAuthorization() async -> Bool {
        if authorizationGranted { return true }

        // 1) 음성인식 권한 — nonisolated static으로 분리 (콜백이 백그라운드 스레드에서 옴)
        let speechGranted = await Self.requestSpeechPermission()

        guard speechGranted else {
            error = "음성 인식 권한이 거부되었습니다."
            return false
        }

        // 2) 마이크 권한
        let micGranted = await Self.requestMicPermission()

        guard micGranted else {
            error = "마이크 권한이 거부되었습니다."
            return false
        }

        authorizationGranted = true
        return true
    }

    /// 백그라운드 스레드에서 콜백되므로 반드시 nonisolated
    private nonisolated static func requestSpeechPermission() async -> Bool {
        await withUnsafeContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func requestMicPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return true
    }

    // MARK: - Push-to-Talk

    func startListening() {
        guard state == .idle || state == .waitingForWakeWord else { return }
        if state == .waitingForWakeWord { stopWakeWordDetection() }

        transcript = ""
        preservedTranscript = ""
        error = nil
        isContinuousMode = false
        doStartRecognition(mode: .query)
    }

    /// 연속 대화 모드: 타임아웃 시 onSilenceTimeout 호출
    func startContinuousListening(timeout: TimeInterval = 10.0) {
        guard state == .idle || state == .waitingForWakeWord else { return }
        if state == .waitingForWakeWord { stopWakeWordDetection() }

        transcript = ""
        preservedTranscript = ""
        error = nil
        isContinuousMode = true
        continuousListeningTimeout = timeout
        doStartRecognition(mode: .query)
        startContinuousTimeout()
    }

    func stopListening() {
        guard state == .listening else { return }
        let captured = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        tearDownAudio()
        state = .idle
        isContinuousMode = false
        if !captured.isEmpty {
            soundService.playInputComplete()
            onQueryCaptured?(captured)
        } else {
            onListeningCancelled?()
        }
    }

    // MARK: - Wake Word

    func startWakeWordDetection(wakeWord: String) {
        guard state == .idle, !wakeWord.isEmpty else { return }
        wakeWordTranscript = ""
        doStartRecognition(mode: .wakeWord(wakeWord: wakeWord))
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
        case wakeWord(wakeWord: String)
    }

    /// 오디오 탭을 nonisolated 컨텍스트에서 설치 (Swift 6 concurrency 호환)
    private nonisolated static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private func doStartRecognition(mode: RecognitionMode) {
        guard authorizationGranted else {
            error = "마이크/음성인식 권한이 필요합니다. 시스템 설정에서 허용해주세요."
            Log.stt.error("권한 미부여")
            if case .query = mode { onListeningCancelled?() }
            return
        }

        let available = speechRecognizer?.isAvailable ?? false
        let onDevice = speechRecognizer?.supportsOnDeviceRecognition ?? false
        Log.stt.info("음성인식 시작 - available: \(available), onDevice: \(onDevice)")

        guard available else {
            error = "음성 인식을 사용할 수 없습니다."
            Log.stt.error("음성 인식 불가")
            if case .query = mode { onListeningCancelled?() }
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 온디바이스가 안 되면 서버 인식 사용
        if onDevice {
            request.requiresOnDeviceRecognition = true
            Log.stt.info("온디바이스 인식 사용")
        } else {
            Log.stt.info("서버 인식 사용 (온디바이스 미지원)")
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Log.stt.debug("오디오 포맷 - sampleRate: \(format.sampleRate), channels: \(format.channelCount)")

        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "오디오 입력 장치를 찾을 수 없습니다."
            Log.stt.error("오디오 포맷 무효")
            if case .query = mode { onListeningCancelled?() }
            return
        }

        // 오디오 스레드에서 실행되는 tap을 nonisolated 컨텍스트에서 설치
        Self.installAudioTap(on: inputNode, format: format, request: request)

        self.audioEngine = engine
        self.recognitionRequest = request

        switch mode {
        case .query:
            state = .listening
            beginQueryRecognition(request: request)
        case .wakeWord(let wakeWord):
            state = .waitingForWakeWord
            Log.stt.info("웨이크워드 대기: \(wakeWord)")
            beginWakeWordRecognition(request: request, wakeWord: wakeWord)
        }

        engine.prepare()
        do {
            try engine.start()
            Log.stt.info("오디오 엔진 시작 성공")
        } catch {
            self.error = "오디오 엔진 시작 실패: \(error.localizedDescription)"
            Log.stt.error("오디오 엔진 실패: \(error, privacy: .public)")
            tearDownAudio()
            state = .idle
            if case .query = mode { onListeningCancelled?() }
        }
    }

    private func beginQueryRecognition(request: SFSpeechAudioBufferRecognitionRequest) {
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    let newText = result.bestTranscription.formattedString
                    let previousTranscript = self.transcript

                    // 인식기가 앞문장을 날리는 현상 대응:
                    // 기존 텍스트(보존분 제외)의 절반 이상이 사라지면 리셋으로 간주
                    let currentPartial = self.preservedTranscript.isEmpty
                        ? self.transcript
                        : String(self.transcript.dropFirst(self.preservedTranscript.count)).trimmingCharacters(in: .whitespaces)

                    if !currentPartial.isEmpty && newText.count < currentPartial.count / 2 {
                        // 이전 텍스트 보존
                        self.preservedTranscript = self.transcript
                        Log.stt.debug("인식기 리셋 감지, 보존: \(self.preservedTranscript)")
                    }

                    if self.preservedTranscript.isEmpty {
                        self.transcript = newText
                    } else {
                        self.transcript = self.preservedTranscript + " " + newText
                    }

                    // 텍스트가 실제로 변경된 경우에만 무음 타이머 리셋
                    if self.transcript != previousTranscript {
                        self.resetSilenceTimer()
                    }
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

        // 연속 모드면 전체 타임아웃도 리셋
        if isContinuousMode {
            startContinuousTimeout()
        }
    }

    private var continuousTimer: Timer?

    private func startContinuousTimeout() {
        continuousTimer?.invalidate()
        continuousTimer = Timer.scheduledTimer(withTimeInterval: continuousListeningTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.state == .listening, self.isContinuousMode else { return }
                // 타임아웃 시 캡처된 게 없으면 onSilenceTimeout 호출
                let captured = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                self.tearDownAudio()
                self.state = .idle
                self.isContinuousMode = false
                if captured.isEmpty {
                    self.onSilenceTimeout?()
                } else {
                    self.soundService.playInputComplete()
                    self.onQueryCaptured?(captured)
                }
            }
        }
    }

    private func beginWakeWordRecognition(request: SFSpeechAudioBufferRecognitionRequest, wakeWord: String) {
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, err in
            DispatchQueue.main.async {
                guard let self, self.state == .waitingForWakeWord else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.wakeWordTranscript = text

                    // 자모 유사도 기반 매칭
                    if JamoMatcher.isMatch(transcript: text, wakeWord: wakeWord) {
                        Log.stt.info("웨이크워드 자모 매칭 성공: \"\(text)\" ≈ \"\(wakeWord)\"")
                        self.soundService.playWakeWordDetected()
                        let detectedTranscript = text
                        self.stopWakeWordDetection()
                        self.onWakeWordDetected?(detectedTranscript)
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
                            self.startWakeWordDetection(wakeWord: wakeWord)
                        }
                    }
                }
            }
        }
    }

    private func tearDownAudio() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        continuousTimer?.invalidate()
        continuousTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
