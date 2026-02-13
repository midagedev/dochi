import Foundation
import AVFoundation

@MainActor
final class SystemTTSService: NSObject, TTSServiceProtocol {
    private(set) var engineState: TTSEngineState = .unloaded
    private(set) var isSpeaking: Bool = false
    var onComplete: (@MainActor () -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var sentenceQueue: [String] = []
    private var isProcessing: Bool = false

    var speed: Float = 1.0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Engine Lifecycle

    func loadEngine() async throws {
        guard case .unloaded = engineState else { return }
        engineState = .ready
        Log.tts.info("System TTS engine ready")
    }

    func unloadEngine() {
        stopAndClear()
        engineState = .unloaded
        Log.tts.info("System TTS engine unloaded")
    }

    // MARK: - Sentence Queue

    func enqueueSentence(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        sentenceQueue.append(cleaned)
        Log.tts.debug("System TTS enqueued (\(self.sentenceQueue.count) in queue)")
        processNextIfNeeded()
    }

    func stopAndClear() {
        sentenceQueue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isProcessing = false
        Log.tts.info("System TTS stopped and queue cleared")
    }

    // MARK: - Queue Processing

    private func processNextIfNeeded() {
        guard !isProcessing, !sentenceQueue.isEmpty else { return }
        isProcessing = true
        isSpeaking = true

        let sentence = sentenceQueue.removeFirst()
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        // AVSpeechUtterance rate: 0.0~1.0, default ~0.5. Map our 0.5x~2.0x accordingly.
        utterance.rate = mapSpeedToRate(speed)
        utterance.pitchMultiplier = 1.0

        synthesizer.speak(utterance)
        Log.tts.debug("System TTS speaking: \(sentence.prefix(30))...")
    }

    /// Map user-facing speed (0.5x~2.0x) to AVSpeechUtterance rate (0.0~1.0).
    private func mapSpeedToRate(_ speed: Float) -> Float {
        // speed 1.0 → rate 0.5 (default), speed 0.5 → rate 0.3, speed 2.0 → rate 0.7
        let rate = 0.3 + (speed - 0.5) * (0.4 / 1.5)
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if sentenceQueue.isEmpty {
                isProcessing = false
                isSpeaking = false
                onComplete?()
            } else {
                isProcessing = false
                processNextIfNeeded()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isProcessing = false
            if sentenceQueue.isEmpty {
                isSpeaking = false
            }
        }
    }
}
