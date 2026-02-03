import Foundation
import AVFoundation
import OnnxRuntimeBindings

@MainActor
final class SupertonicService: ObservableObject {
    enum State: Equatable {
        case unloaded
        case loading
        case ready
        case synthesizing
        case playing
    }

    @Published var state: State = .unloaded
    @Published var error: String?

    var onSpeakingComplete: (() -> Void)?

    private var tts: SupertonicTTS?
    private var ortEnv: ORTEnv?
    private var currentStyle: SupertonicStyle?
    private var currentVoice: SupertonicVoice?

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var queueTask: Task<Void, Never>?

    // 문장 큐
    private var sentenceQueue: [String] = []
    private var isProcessingQueue = false

    private static let modelDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dochi/supertonic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let requiredFiles = [
        "tts.json",
        "unicode_indexer.json",
        "duration_predictor.onnx",
        "text_encoder.onnx",
        "vector_estimator.onnx",
        "vocoder.onnx",
    ]

    private static let voiceFiles: [SupertonicVoice: String] = {
        var map = [SupertonicVoice: String]()
        for v in SupertonicVoice.allCases {
            map[v] = "\(v.rawValue).json"
        }
        return map
    }()

    private static let hfBaseURL = "https://huggingface.co/Supertone/supertonic-2/resolve/main/onnx/"
    private static let hfVoiceBaseURL = "https://huggingface.co/Supertone/supertonic-2/resolve/main/voice_styles/"

    // MARK: - Loading

    func loadIfNeeded(voice: SupertonicVoice) {
        guard state == .unloaded || (state == .ready && voice != currentVoice) else { return }

        let needDownload = state == .unloaded
        state = .loading
        error = nil

        Task { [weak self] in
            do {
                if needDownload {
                    try await self?.ensureModelsDownloaded()
                }
                try await self?.ensureVoiceDownloaded(voice)
                try await self?.loadModels(voice: voice)
                self?.state = .ready
            } catch {
                self?.error = "모델 로드 실패: \(error.localizedDescription)"
                self?.state = .unloaded
            }
        }
    }

    func tearDown() {
        stopPlayback()
        queueTask?.cancel()
        queueTask = nil
        sentenceQueue.removeAll()
        isProcessingQueue = false
        tts = nil
        ortEnv = nil
        currentStyle = nil
        currentVoice = nil
        state = .unloaded
    }

    // MARK: - Queue-based Speak

    /// 문장 하나를 큐에 추가. LLM 스트리밍 중 호출됨.
    var speed: Float = 1.15
    var diffusionSteps: Int = 10

    func enqueueSentence(_ text: String, lang: String = "ko", voice: SupertonicVoice) {
        sentenceQueue.append(text)
        processQueue(lang: lang, voice: voice)
    }

    /// 전체 텍스트를 한번에 재생 (기존 호환)
    func speak(_ text: String, lang: String = "ko", voice: SupertonicVoice) {
        stopPlayback()
        sentenceQueue.removeAll()
        sentenceQueue.append(text)
        processQueue(lang: lang, voice: voice)
    }

    func stopPlayback() {
        queueTask?.cancel()
        queueTask = nil
        sentenceQueue.removeAll()
        isProcessingQueue = false
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        if state == .playing || state == .synthesizing {
            state = .ready
        }
    }

    private func processQueue(lang: String, voice: SupertonicVoice) {
        guard !isProcessingQueue else { return }
        guard let tts, let style = currentStyle else { return }

        isProcessingQueue = true

        let capturedTTS = tts
        let capturedStyle = style
        let sampleRate = tts.sampleRate
        let capturedSpeed = speed
        let capturedSteps = diffusionSteps

        queueTask = Task { [weak self] in
            // 오디오 엔진을 한 번만 세팅
            await self?.setupAudioEngine(sampleRate: sampleRate)

            while let self = self {
                // 큐에서 다음 문장 꺼내기
                guard !self.sentenceQueue.isEmpty else {
                    // 큐 비었으면 대기 후 재확인 (LLM이 아직 스트리밍 중일 수 있음)
                    try? await Task.sleep(for: .milliseconds(100))

                    // 다시 확인 — 여전히 비었고 LLM 스트리밍도 끝났으면 종료
                    if self.sentenceQueue.isEmpty {
                        break
                    }
                    continue
                }

                let sentence = self.sentenceQueue.removeFirst()
                self.state = .synthesizing

                do {
                    let result: (wav: [Float], duration: Float) = try await Task.detached {
                        try capturedTTS.call(sentence, lang, capturedStyle, capturedSteps, speed: capturedSpeed)
                    }.value

                    try Task.checkCancellation()

                    self.state = .playing
                    await self.playBufferAndWait(samples: result.wav, sampleRate: sampleRate)
                } catch is CancellationError {
                    break
                } catch {
                    self.error = "음성 합성 실패: \(error.localizedDescription)"
                    break
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isProcessingQueue = false
                if self.state != .unloaded {
                    self.state = .ready
                }
                self.onSpeakingComplete?()
            }
        }
    }

    // MARK: - Audio Engine (재사용)

    private func setupAudioEngine(sampleRate: Int) {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        engine.prepare()
        do {
            try engine.start()
            player.play()
        } catch {
            self.error = "오디오 시작 실패: \(error.localizedDescription)"
            return
        }

        self.audioEngine = engine
        self.playerNode = player
    }

    private func playBufferAndWait(samples: [Float], sampleRate: Int) async {
        guard !samples.isEmpty, let player = playerNode, let engine = audioEngine, engine.isRunning else { return }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: samples.count)
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer) {
                continuation.resume()
            }
        }
    }

    // MARK: - Model Download

    private func ensureModelsDownloaded() async throws {
        let fm = FileManager.default
        for file in Self.requiredFiles {
            let localURL = Self.modelDir.appendingPathComponent(file)
            if fm.fileExists(atPath: localURL.path) { continue }

            let remoteURL = URL(string: Self.hfBaseURL + file)!
            print("[Supertonic] Downloading \(file)...")
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            try fm.moveItem(at: tempURL, to: localURL)
            print("[Supertonic] Downloaded \(file)")
        }
    }

    private func ensureVoiceDownloaded(_ voice: SupertonicVoice) async throws {
        guard let fileName = Self.voiceFiles[voice] else { return }
        let localURL = Self.modelDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: localURL.path) { return }

        let remoteURL = URL(string: Self.hfVoiceBaseURL + fileName)!
        print("[Supertonic] Downloading voice \(fileName)...")
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        print("[Supertonic] Downloaded voice \(fileName)")
    }

    // MARK: - Model Loading

    private func loadModels(voice: SupertonicVoice) async throws {
        let modelPath = Self.modelDir.path

        let (env, loadedTTS) = try await Task.detached {
            let env = try ORTEnv(loggingLevel: .warning)
            let tts = try supertonicLoadTTS(modelPath, env)
            return (env, tts)
        }.value

        self.ortEnv = env
        self.tts = loadedTTS

        guard let voiceFile = Self.voiceFiles[voice] else { return }
        let voicePath = Self.modelDir.appendingPathComponent(voiceFile).path

        let style = try await Task.detached {
            try supertonicLoadVoiceStyle([voicePath])
        }.value

        self.currentStyle = style
        self.currentVoice = voice
        print("[Supertonic] Models and voice \(voice.rawValue) loaded")
    }
}
