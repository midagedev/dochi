import Foundation
import AVFoundation

@MainActor
final class GoogleCloudTTSService: TTSServiceProtocol {
    private(set) var engineState: TTSEngineState = .unloaded
    private(set) var isSpeaking: Bool = false
    var onComplete: (@MainActor () -> Void)?

    private var sentenceQueue: [String] = []
    private var isProcessing: Bool = false
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // Settings
    var apiKey: String = ""
    var voiceName: String = GoogleCloudVoice.defaultVoiceName
    var speed: Float = 1.0
    var pitch: Float = 0.0

    // Audio format: LINEAR16, 24kHz, mono
    private let sampleRate: Double = 24000
    private let channels: AVAudioChannelCount = 1

    private static let apiURL = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize")!

    // MARK: - Engine Lifecycle

    func loadEngine() async throws {
        guard isUnloadedOrError else { return }
        engineState = .loading
        Log.tts.info("Loading Google Cloud TTS engine...")

        setupAudioEngine()
        engineState = .ready
        Log.tts.info("Google Cloud TTS engine ready")
    }

    func unloadEngine() {
        stopAndClear()
        teardownAudioEngine()
        engineState = .unloaded
        Log.tts.info("Google Cloud TTS engine unloaded")
    }

    // MARK: - Sentence Queue

    func enqueueSentence(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        sentenceQueue.append(cleaned)
        Log.tts.debug("GCP TTS enqueued (\(self.sentenceQueue.count) in queue)")
        processQueueIfNeeded()
    }

    func stopAndClear() {
        sentenceQueue.removeAll()
        playerNode?.stop()
        isSpeaking = false
        isProcessing = false
        Log.tts.info("GCP TTS stopped and queue cleared")
    }

    // MARK: - Queue Processing

    private func processQueueIfNeeded() {
        guard !isProcessing, !sentenceQueue.isEmpty else { return }
        isProcessing = true
        isSpeaking = true

        Task {
            // Prefetch: synthesize next sentence while current one plays
            var nextAudioTask: Task<Data?, Never>?

            while !sentenceQueue.isEmpty {
                let sentence = sentenceQueue.removeFirst()

                // Wait for prefetched audio or synthesize now
                let audioData: Data?
                if let prefetch = nextAudioTask {
                    audioData = await prefetch.value
                    nextAudioTask = nil
                } else {
                    audioData = await synthesize(sentence)
                }

                // Start prefetching next sentence while this one plays
                if let next = sentenceQueue.first {
                    let key = apiKey
                    let voice = voiceName
                    let spd = speed
                    nextAudioTask = Task {
                        await self.synthesize(next)
                    }
                }

                if let data = audioData {
                    playPCMData(data)
                    await waitForPlaybackCompletion()
                }

                // Remove prefetched sentence from queue if it was consumed
                if nextAudioTask != nil, !sentenceQueue.isEmpty {
                    // The prefetch corresponds to sentenceQueue.first, which will be
                    // removeFirst()'d in the next loop iteration — that's correct.
                }
            }

            nextAudioTask?.cancel()
            isProcessing = false
            isSpeaking = false
            onComplete?()
        }
    }

    private func synthesize(_ text: String) async -> Data? {
        Log.tts.debug("GCP TTS synthesizing: \(text.prefix(30))...")

        guard !apiKey.isEmpty else {
            Log.tts.error("Google Cloud TTS API key not set")
            return nil
        }

        do {
            return try await callAPI(text: text)
        } catch {
            Log.tts.error("GCP TTS synthesis failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Google Cloud TTS API

    private func callAPI(text: String) async throws -> Data {
        var url = Self.apiURL
        url.append(queryItems: [URLQueryItem(name: "key", value: apiKey)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let isChirp = voiceName.contains("Chirp")
        var audioConfig: [String: Any] = [
            "audioEncoding": "LINEAR16",
            "sampleRateHertz": Int(sampleRate),
        ]
        if !isChirp {
            audioConfig["speakingRate"] = Double(speed)
            audioConfig["pitch"] = Double(pitch)
        }

        let body: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": "ko-KR",
                "name": voiceName,
            ],
            "audioConfig": audioConfig,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleCloudTTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            Log.tts.error("GCP TTS API error \(httpResponse.statusCode): \(errorBody)")
            throw GoogleCloudTTSError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response — audioContent is base64-encoded
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let audioContentBase64 = json["audioContent"] as? String,
              let audioData = Data(base64Encoded: audioContentBase64) else {
            throw GoogleCloudTTSError.invalidAudioData
        }

        // LINEAR16 response includes a WAV header (44 bytes). Strip it for raw PCM.
        let pcmData = audioData.count > 44 ? audioData.dropFirst(44) : audioData
        return Data(pcmData)
    }

    // MARK: - Audio Playback

    private var playbackContinuation: CheckedContinuation<Void, Never>?

    private func playPCMData(_ data: Data) {
        guard let engine = audioEngine, let player = playerNode else {
            Log.tts.error("Audio engine not available for GCP TTS playback")
            return
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: true)!
        let frameCount = AVAudioFrameCount(data.count / 2) // 16-bit = 2 bytes per sample

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            Log.tts.error("Failed to create PCM buffer for GCP TTS")
            return
        }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            if let src = rawBuffer.baseAddress {
                buffer.int16ChannelData?[0].update(from: src.assumingMemoryBound(to: Int16.self), count: Int(frameCount))
            }
        }

        // Convert Int16 buffer to Float32 for the audio engine
        let floatFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        guard let converter = AVAudioConverter(from: format, to: floatFormat),
              let floatBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCount) else {
            Log.tts.error("Failed to create audio converter for GCP TTS")
            return
        }

        var conversionError: NSError?
        converter.convert(to: floatBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            Log.tts.error("Audio conversion error: \(conversionError.localizedDescription)")
            return
        }

        player.scheduleBuffer(floatBuffer) { [weak self] in
            Task { @MainActor in
                Log.tts.debug("GCP TTS buffer playback completed")
                self?.playbackContinuation?.resume()
                self?.playbackContinuation = nil
            }
        }

        if !player.isPlaying {
            player.play()
        }
    }

    private func waitForPlaybackCompletion() async {
        await withCheckedContinuation { continuation in
            playbackContinuation = continuation
        }
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
            Log.tts.debug("GCP TTS audio engine started")
        } catch {
            Log.tts.error("GCP TTS audio engine start failed: \(error.localizedDescription)")
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

    private var isUnloadedOrError: Bool {
        switch engineState {
        case .unloaded, .error: true
        default: false
        }
    }
}

// MARK: - Errors

enum GoogleCloudTTSError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "서버 응답이 올바르지 않습니다"
        case .apiError(let statusCode, let message):
            "API 오류 (\(statusCode)): \(message)"
        case .invalidAudioData:
            "오디오 데이터를 디코딩할 수 없습니다"
        }
    }
}
