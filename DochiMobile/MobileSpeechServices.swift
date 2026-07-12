@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

@MainActor
@Observable
final class MobileSpeechRecognitionService {
    private(set) var isListening = false
    private(set) var transcript = ""
    private(set) var permissionDescription = ""
    var errorMessage: String?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var hasInstalledTap = false
    @ObservationIgnored private var transcriptPrefix = ""
    @ObservationIgnored private var callbackGate = MobileSpeechCallbackGate()

    init(locale: Locale = Locale(identifier: "ko-KR")) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        refreshPermissionDescription()
    }

    func startListening(existingText: String = "") async {
        errorMessage = nil
        stopListening(cancelRecognition: true)
        let startID = callbackGate.begin()

        let hasSpeechPermission = await requestSpeechPermission()
        guard callbackGate.accepts(startID) else { return }
        guard hasSpeechPermission else {
            _ = callbackGate.finish(startID)
            errorMessage = "음성 인식 권한이 꺼져 있어요. 설정 앱의 개인정보 보호 및 보안에서 허용해 주세요."
            refreshPermissionDescription()
            return
        }
        let hasMicrophonePermission = await requestMicrophonePermission()
        guard callbackGate.accepts(startID) else { return }
        guard hasMicrophonePermission else {
            _ = callbackGate.finish(startID)
            errorMessage = "마이크 권한이 꺼져 있어요. 설정 앱에서 도치의 마이크 접근을 허용해 주세요."
            refreshPermissionDescription()
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            _ = callbackGate.finish(startID)
            errorMessage = "지금은 음성 인식을 사용할 수 없어요. 잠시 후 다시 시도해 주세요."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if speechRecognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            recognitionRequest = request
            transcriptPrefix = existingText.trimmingCharacters(in: .whitespacesAndNewlines)
            transcript = transcriptPrefix

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                let recognizedText = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                let errorText = error?.localizedDescription
                Task { @MainActor [weak self] in
                    self?.receiveRecognitionCallback(
                        generationID: startID,
                        recognizedText: recognizedText,
                        isFinal: isFinal,
                        errorText: errorText
                    )
                }
            }

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw MobileSpeechError.noAudioInput
            }
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasInstalledTap = true
            audioEngine.prepare()
            try audioEngine.start()
            guard callbackGate.accepts(startID) else {
                stopListening(cancelRecognition: true)
                return
            }
            isListening = true
            permissionDescription = "듣는 중"
        } catch {
            guard callbackGate.accepts(startID) else { return }
            stopListening(cancelRecognition: true)
            errorMessage = error.localizedDescription
        }
    }

    func stopListening(cancelRecognition: Bool = false) {
        recognitionRequest?.endAudio()
        if cancelRecognition {
            callbackGate.invalidate()
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
        }
        finishAudioCapture()
    }

    func clearError() { errorMessage = nil }

    private func receiveRecognitionCallback(
        generationID: UUID,
        recognizedText: String?,
        isFinal: Bool,
        errorText: String?
    ) {
        // Speech callbacks can arrive after cancellation, and even after a new
        // recognition task has started. Only the generation that installed the
        // callback may mutate the current transcript or audio state.
        guard callbackGate.accepts(generationID) else { return }
        if let recognizedText {
            transcript = join(prefix: transcriptPrefix, recognized: recognizedText)
        }
        if let errorText, !isFinal {
            errorMessage = "음성 인식을 마치지 못했어요: \(errorText)"
        }
        if isFinal || errorText != nil {
            guard callbackGate.finish(generationID) else { return }
            recognitionRequest = nil
            recognitionTask = nil
            finishAudioCapture()
        }
    }

    private func finishAudioCapture() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        isListening = false
        refreshPermissionDescription()
    }

    private func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            return status == .authorized
        @unknown default:
            return false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func refreshPermissionDescription() {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVAudioApplication.shared.recordPermission
        if speech == .denied || speech == .restricted || microphone == .denied {
            permissionDescription = "권한 필요"
        } else if speech == .authorized, microphone == .granted {
            permissionDescription = "사용 가능"
        } else {
            permissionDescription = "사용할 때 권한 요청"
        }
    }

    private func join(prefix: String, recognized: String) -> String {
        guard !prefix.isEmpty else { return recognized }
        guard !recognized.isEmpty else { return prefix }
        return "\(prefix) \(recognized)"
    }
}

/// A tiny deterministic seam around Speech's out-of-order callback behavior.
/// The service owns this on the main actor; tests exercise the generation
/// transition without requiring microphone or speech-recognition permissions.
struct MobileSpeechCallbackGate: Sendable {
    private(set) var activeGenerationID: UUID?

    @discardableResult
    mutating func begin(id: UUID = UUID()) -> UUID {
        activeGenerationID = id
        return id
    }

    func accepts(_ id: UUID) -> Bool {
        activeGenerationID == id
    }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard accepts(id) else { return false }
        activeGenerationID = nil
        return true
    }

    mutating func invalidate() {
        activeGenerationID = nil
    }
}

@MainActor
final class MobileSpeechOutputService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
            ?? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.04
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

private enum MobileSpeechError: LocalizedError {
    case noAudioInput

    var errorDescription: String? {
        switch self {
        case .noAudioInput: "사용 가능한 마이크 입력을 찾지 못했어요."
        }
    }
}
