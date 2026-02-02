import Foundation
import AVFoundation

@MainActor
final class RealtimeService: ObservableObject {
    enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case connected       // 연결됨, 대기 중
        case listening       // 사용자 음성 감지 중
        case responding      // AI 응답 중
    }

    @Published var state: State = .disconnected
    @Published var userTranscript: String = ""
    @Published var assistantTranscript: String = ""
    @Published var error: String?

    var onResponseComplete: ((String) -> Void)?

    // WebSocket
    private nonisolated(unsafe) var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?

    // Audio capture
    private nonisolated(unsafe) var audioEngine: AVAudioEngine?
    private nonisolated(unsafe) var inputConverter: AVAudioConverter?
    private let captureFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!

    // Audio playback
    private nonisolated(unsafe) var playerNode: AVAudioPlayerNode?
    private nonisolated(unsafe) var playbackMixer: AVAudioMixerNode?

    // Pending session config (sent after session.created)
    private var pendingSessionConfig: [String: Any]?

    // MARK: - Connect

    func connect(apiKey: String, instructions: String, voice: String = "nova") {
        guard state == .disconnected else { return }
        state = .connecting
        error = nil

        // Store config to send after session.created
        pendingSessionConfig = [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": instructions.isEmpty ? "You are a helpful assistant. Respond in Korean." : instructions,
                "voice": voice,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "whisper-1"],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 800,
                ] as [String: Any],
            ] as [String: Any],
        ]

        let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        startReceiving()
    }

    func disconnect() {
        tearDownAudio()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
        userTranscript = ""
        assistantTranscript = ""
    }

    // MARK: - Text Input

    func sendTextMessage(_ text: String) {
        guard state == .connected || state == .listening else { return }

        let event: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": text]
                ],
            ] as [String: Any],
        ]
        sendJSON(event)
        sendJSON(["type": "response.create"])
        state = .responding
        assistantTranscript = ""
    }

    // MARK: - Audio Setup

    private func setupAudio() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()

        engine.attach(player)
        engine.attach(mixer)

        // Playback: player → mixer → mainMixer → output
        let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
        engine.connect(player, to: mixer, format: playbackFormat)
        engine.connect(mixer, to: engine.mainMixerNode, format: playbackFormat)

        // Capture: inputNode → tap
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Converter: mic format → 24kHz PCM16 mono
        if let converter = AVAudioConverter(from: inputFormat, to: captureFormat) {
            self.inputConverter = converter

            inputNode.installTap(onBus: 0, bufferSize: 2400, format: inputFormat) { [weak self] buffer, _ in
                self?.processInputBuffer(buffer, converter: converter)
            }
        }

        self.audioEngine = engine
        self.playerNode = player
        self.playbackMixer = mixer

        engine.prepare()
        do {
            try engine.start()
        } catch {
            self.error = "오디오 시작 실패: \(error.localizedDescription)"
        }
    }

    private func tearDownAudio() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        playerNode = nil
        playbackMixer = nil
        audioEngine = nil
        inputConverter = nil
    }

    // MARK: - Audio Capture → WebSocket

    private nonisolated func processInputBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * 24000.0 / buffer.format.sampleRate
        )
        guard frameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: frameCount)
        else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        // PCM16 → base64
        guard let channelData = convertedBuffer.int16ChannelData else { return }
        let data = Data(bytes: channelData[0], count: Int(convertedBuffer.frameLength) * 2)
        let base64 = data.base64EncodedString()

        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64,
        ]
        sendJSON(event)
    }

    // MARK: - WebSocket → Audio Playback

    private func playAudioDelta(_ base64Audio: String) {
        guard let data = Data(base64Encoded: base64Audio),
              let player = playerNode,
              let engine = audioEngine, engine.isRunning
        else { return }

        let frameCount = UInt32(data.count / 2)  // PCM16 = 2 bytes per frame
        let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        // PCM16 (Int16) → Float32
        data.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            guard let floatChannel = pcmBuffer.floatChannelData?[0] else { return }
            for i in 0..<Int(frameCount) {
                floatChannel[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        if !player.isPlaying {
            player.play()
        }
        player.scheduleBuffer(pcmBuffer)
    }

    // MARK: - WebSocket Send/Receive

    private nonisolated func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8)
        else { return }
        webSocket?.send(.string(str)) { _ in }
    }

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleEvent(text)
                    default:
                        break
                    }
                    self.startReceiving()
                case .failure(let err):
                    if self.state != .disconnected {
                        self.error = err.localizedDescription
                        self.state = .disconnected
                    }
                }
            }
        }
    }

    private func handleEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "session.created":
            // 서버 연결 완료 → 세션 설정 전송 후 오디오 시작
            if let config = pendingSessionConfig {
                sendJSON(config)
                pendingSessionConfig = nil
            }
            setupAudio()
            state = .connected

        case "session.updated":
            // 세션 설정 적용 완료
            print("[Dochi] 세션 설정 적용됨")

        case "input_audio_buffer.speech_started":
            state = .listening
            userTranscript = ""
            assistantTranscript = ""
            // 사용자가 말하기 시작하면 AI 응답 재생 중단
            playerNode?.stop()

        case "input_audio_buffer.speech_stopped":
            state = .responding
            SoundService.playInputComplete()

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                userTranscript = transcript
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                assistantTranscript += delta
            }

        case "response.audio.delta":
            if let delta = json["delta"] as? String {
                playAudioDelta(delta)
            }

        case "response.done":
            let transcript = assistantTranscript
            state = .connected
            if !transcript.isEmpty {
                onResponseComplete?(transcript)
            }

        case "error":
            if let errData = json["error"] as? [String: Any],
               let msg = errData["message"] as? String {
                error = msg
            }

        default:
            break
        }
    }
}
