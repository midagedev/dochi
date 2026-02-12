import Foundation
import AVFoundation
import os

@MainActor
final class SupertonicService: TTSServiceProtocol {
    private(set) var engineState: TTSEngineState = .unloaded
    private(set) var isSpeaking: Bool = false
    var onComplete: (@MainActor () -> Void)?

    private var sentenceQueue: [String] = []
    private var isProcessing: Bool = false
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // TTS settings
    var speed: Float = 1.0
    var diffusionSteps: Int = 3
    var voice: SupertonicVoice = .F1

    // MARK: - Engine Lifecycle

    func loadEngine() async throws {
        guard isUnloadedState || isErrorState else { return }
        engineState = .loading
        Log.tts.info("Loading TTS engine...")

        // TODO: Load ONNX models when available
        // 1. Load duration model
        // 2. Load acoustic model
        // 3. Load vocoder model
        // 4. Warm up with a test inference

        setupAudioEngine()
        engineState = .ready
        Log.tts.info("TTS engine ready")
    }

    func unloadEngine() {
        stopAndClear()
        teardownAudioEngine()
        engineState = .unloaded
        Log.tts.info("TTS engine unloaded")
    }

    // MARK: - Sentence Queue

    func enqueueSentence(_ text: String) {
        let cleaned = preprocessText(text)
        guard !cleaned.isEmpty else { return }
        sentenceQueue.append(cleaned)
        Log.tts.debug("Enqueued sentence (\(self.sentenceQueue.count) in queue)")
        processQueueIfNeeded()
    }

    func stopAndClear() {
        sentenceQueue.removeAll()
        playerNode?.stop()
        isSpeaking = false
        isProcessing = false
        Log.tts.info("TTS stopped and queue cleared")
    }

    // MARK: - Queue Processing

    private func processQueueIfNeeded() {
        guard !isProcessing, !sentenceQueue.isEmpty else { return }
        isProcessing = true
        isSpeaking = true

        Task {
            while !sentenceQueue.isEmpty {
                let sentence = sentenceQueue.removeFirst()
                await synthesizeAndPlay(sentence)
            }
            isProcessing = false
            isSpeaking = false
            onComplete?()
        }
    }

    private func synthesizeAndPlay(_ text: String) async {
        Log.tts.debug("Synthesizing: \(text.prefix(30))...")

        // TODO: Actual ONNX inference pipeline when models available
        // 1. tokenize(text) -> ids, mask
        // 2. durationModel.run(ids, mask) -> durations
        // 3. acousticModel.run(ids, durations) -> latents
        // 4. vocoderModel.run(latents) -> waveform
        // 5. Play waveform through audio engine

        // Placeholder: simulate synthesis time
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Text Preprocessing

    func preprocessText(_ text: String) -> String {
        var result = text
        // Remove emojis
        result = result.unicodeScalars
            .filter { !$0.properties.isEmoji || $0.isASCII }
            .map(String.init)
            .joined()
        // Normalize quotes
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")  // left double quote
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")  // right double quote
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")   // left single quote
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")   // right single quote
        // Trim whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    // MARK: - Audio Engine

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        guard let engine = audioEngine, let player = playerNode else { return }
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            Log.tts.debug("Audio engine started")
        } catch {
            Log.tts.error("Audio engine start failed: \(error.localizedDescription)")
            engineState = .error(error.localizedDescription)
        }
    }

    private func teardownAudioEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        if let player = playerNode {
            audioEngine?.detach(player)
        }
        playerNode = nil
        audioEngine = nil
    }

    private var isUnloadedState: Bool {
        if case .unloaded = engineState { return true }
        return false
    }

    private var isErrorState: Bool {
        if case .error = engineState { return true }
        return false
    }
}
