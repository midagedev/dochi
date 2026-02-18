import Foundation
import AVFoundation

@MainActor
final class TypecastTTSService: NSObject, TTSServiceProtocol {
    static let defaultModel = "ssfm-v30"

    private(set) var engineState: TTSEngineState = .unloaded
    private(set) var isSpeaking: Bool = false
    var onComplete: (@MainActor () -> Void)?

    private var sentenceQueue: [String] = []
    private var isProcessing: Bool = false
    private var audioPlayer: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Never>?

    // Settings
    var apiKey: String = ""
    var voiceId: String = ""
    var model: String = TypecastTTSService.defaultModel
    var language: String = "kor"
    var emotionType: String = "preset"
    var emotionPreset: String = "normal"
    var emotionIntensity: Float = 1.0
    var volume: Int = 100
    var audioPitch: Int = 0
    var audioFormat: String = "wav"
    var speed: Float = 1.0

    private static let apiURL = URL(string: "https://api.typecast.ai/v1/text-to-speech")!
    private let maxTextLength = 5_000

    // MARK: - Engine Lifecycle

    func loadEngine() async throws {
        guard isUnloadedOrError else { return }
        engineState = .loading
        Log.tts.info("Loading Typecast TTS engine...")
        engineState = .ready
        Log.tts.info("Typecast TTS engine ready")
    }

    func unloadEngine() {
        stopAndClear()
        engineState = .unloaded
        Log.tts.info("Typecast TTS engine unloaded")
    }

    // MARK: - Sentence Queue

    func enqueueSentence(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let chunks = splitText(cleaned, maxLength: maxTextLength)
        sentenceQueue.append(contentsOf: chunks)
        Log.tts.debug("Typecast TTS enqueued (\(self.sentenceQueue.count) in queue)")
        processQueueIfNeeded()
    }

    func stopAndClear() {
        sentenceQueue.removeAll()
        audioPlayer?.stop()
        audioPlayer = nil
        playbackContinuation?.resume()
        playbackContinuation = nil
        isSpeaking = false
        isProcessing = false
        Log.tts.info("Typecast TTS stopped and queue cleared")
    }

    // MARK: - Queue Processing

    private func processQueueIfNeeded() {
        guard !isProcessing, !sentenceQueue.isEmpty else { return }
        isProcessing = true
        isSpeaking = true

        Task {
            while !sentenceQueue.isEmpty {
                let sentence = sentenceQueue.removeFirst()
                guard let audioData = await synthesize(sentence) else { continue }
                await playAudioData(audioData)
            }

            isProcessing = false
            isSpeaking = false
            onComplete?()
        }
    }

    private func synthesize(_ text: String) async -> Data? {
        Log.tts.debug("Typecast TTS synthesizing: \(text.prefix(30))...")

        guard !apiKey.isEmpty else {
            Log.tts.error("Typecast TTS API key not set")
            return nil
        }

        guard !voiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.tts.error("Typecast voice_id not set")
            return nil
        }

        do {
            return try await callAPI(text: text)
        } catch {
            Log.tts.error("Typecast TTS synthesis failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Typecast API

    private func callAPI(text: String) async throws -> Data {
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")

        var prompt: [String: Any] = [
            "emotion_type": emotionType == "smart" ? "smart" : "preset",
        ]
        if emotionType != "smart" {
            prompt["emotion_preset"] = emotionPreset
            prompt["emotion_intensity"] = Double(clampEmotionIntensity(emotionIntensity))
        }

        let output: [String: Any] = [
            "volume": clampVolume(volume),
            "audio_pitch": clampAudioPitch(audioPitch),
            "audio_tempo": Double(clampTempo(speed)),
            "audio_format": (audioFormat == "mp3") ? "mp3" : "wav",
        ]

        let requestBody: [String: Any] = [
            "voice_id": voiceId,
            "text": text,
            "model": model,
            "language": language,
            "prompt": prompt,
            "output": output,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TypecastTTSError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            Log.tts.error("Typecast API error \(httpResponse.statusCode): \(errorBody)")
            throw TypecastTTSError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        return data
    }

    // MARK: - Audio Playback

    private func playAudioData(_ data: Data) async {
        await withCheckedContinuation { continuation in
            playbackContinuation = continuation

            do {
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.prepareToPlay()
                audioPlayer = player

                if !player.play() {
                    throw TypecastTTSError.playbackFailed
                }
            } catch {
                Log.tts.error("Typecast audio playback failed: \(error.localizedDescription)")
                playbackContinuation?.resume()
                playbackContinuation = nil
                audioPlayer = nil
            }
        }
    }

    // MARK: - Helpers

    private var isUnloadedOrError: Bool {
        switch engineState {
        case .unloaded, .error: true
        default: false
        }
    }

    private func splitText(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }

        var chunks: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxLength, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }

        return chunks
    }

    private func clampTempo(_ value: Float) -> Float {
        min(max(value, 0.5), 2.0)
    }

    private func clampEmotionIntensity(_ value: Float) -> Float {
        min(max(value, 0.0), 2.0)
    }

    private func clampVolume(_ value: Int) -> Int {
        min(max(value, 0), 200)
    }

    private func clampAudioPitch(_ value: Int) -> Int {
        min(max(value, -12), 12)
    }
}

// MARK: - AVAudioPlayerDelegate

extension TypecastTTSService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            playbackContinuation?.resume()
            playbackContinuation = nil
            audioPlayer = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            if let error {
                Log.tts.error("Typecast audio decode failed: \(error.localizedDescription)")
            }
            playbackContinuation?.resume()
            playbackContinuation = nil
            audioPlayer = nil
        }
    }
}

// MARK: - Errors

enum TypecastTTSError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "서버 응답이 올바르지 않습니다"
        case .apiError(let statusCode, let message):
            "API 오류 (\(statusCode)): \(message)"
        case .playbackFailed:
            "오디오 재생을 시작할 수 없습니다"
        }
    }
}
