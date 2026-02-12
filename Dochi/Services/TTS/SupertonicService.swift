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
    private let modelManager = ONNXModelManager()

    // TTS settings
    var speed: Float = 1.0
    var diffusionSteps: Int = 3
    var voice: SupertonicVoice = .F1

    // Audio format for output
    private let sampleRate: Double = 22050
    private let channels: AVAudioChannelCount = 1

    // MARK: - Engine Lifecycle

    func loadEngine() async throws {
        guard isUnloadedState || isErrorState else { return }
        engineState = .loading
        Log.tts.info("Loading TTS engine...")

        // Load ONNX models if available
        let mgr = modelManager
        if mgr.areModelsAvailable() {
            do {
                try await Task.detached {
                    try mgr.loadModels()
                }.value
                Log.tts.info("ONNX models loaded")
            } catch {
                Log.tts.warning("ONNX model load failed: \(error.localizedDescription) — running in placeholder mode")
            }
        } else {
            Log.tts.info("ONNX models not found at \(mgr.modelsDirectoryPath.path) — running in placeholder mode")
        }

        setupAudioEngine()
        engineState = .ready
        Log.tts.info("TTS engine ready (models loaded: \(mgr.isLoaded))")
    }

    func unloadEngine() {
        stopAndClear()
        teardownAudioEngine()
        modelManager.unloadModels()
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

        if modelManager.isLoaded {
            await synthesizeWithONNX(text)
        } else {
            // Placeholder: simulate synthesis time
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - ONNX Inference Pipeline

    private func synthesizeWithONNX(_ text: String) async {
        // Step 1: Grapheme-to-Phoneme conversion
        let phonemes = KoreanG2P.convert(text)
        guard !phonemes.isEmpty else {
            Log.tts.warning("G2P produced empty phonemes for: \(text.prefix(30))")
            return
        }

        Log.tts.debug("G2P: \(phonemes.count) phonemes")

        // Step 2-5: Run ONNX inference on background thread
        let waveform: [Float]? = await Task.detached { [modelManager, speed, diffusionSteps] in
            return Self.runInferencePipeline(
                phonemes: phonemes,
                modelManager: modelManager,
                speed: speed,
                diffusionSteps: diffusionSteps
            )
        }.value

        guard let waveform, !waveform.isEmpty else {
            Log.tts.warning("ONNX inference produced no waveform")
            return
        }

        // Step 6: Play audio
        playWaveform(waveform)
    }

    /// Run the full ONNX inference pipeline (duration → acoustic → vocoder).
    /// Called on a background thread via Task.detached.
    private nonisolated static func runInferencePipeline(
        phonemes: [String],
        modelManager: ONNXModelManager,
        speed: Float,
        diffusionSteps: Int
    ) -> [Float]? {
        #if canImport(OnnxRuntimeBindings)
        guard let durationSession = modelManager.durationSession,
              let acousticSession = modelManager.acousticSession,
              let vocoderSession = modelManager.vocoderSession else {
            return nil
        }

        // TODO: Implement actual ONNX inference when model format is finalized
        // 1. phonemes → token IDs (vocab mapping)
        // 2. durationSession.run(tokenIds, mask) → durations
        // 3. acousticSession.run(tokenIds, durations) → mel spectrogram
        // 4. vocoderSession.run(mel) → waveform [Float]
        // 5. Apply speed adjustment

        return nil
        #else
        return nil
        #endif
    }

    // MARK: - Audio Playback

    private func playWaveform(_ waveform: [Float]) {
        guard let engine = audioEngine, let player = playerNode else {
            Log.tts.error("Audio engine not available for playback")
            return
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(waveform.count)) else {
            Log.tts.error("Failed to create audio buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(waveform.count)
        if let channelData = buffer.floatChannelData {
            waveform.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: waveform.count)
            }
        }

        player.scheduleBuffer(buffer) {
            Log.tts.debug("Buffer playback completed")
        }

        if !player.isPlaying {
            player.play()
        }
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
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")
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
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
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
