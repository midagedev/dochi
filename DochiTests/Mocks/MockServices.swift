import Foundation
@testable import Dochi

// Mocks for the kept service protocols, used to drive DochiViewModel in tests.

@MainActor
final class MockSpeechService: SpeechServiceProtocol {
    var isAuthorized: Bool = true
    var isListening: Bool = false

    var startListeningCallCount = 0
    var lastSilenceTimeout: TimeInterval?
    private var onFinal: (@MainActor (String) -> Void)?
    private var onPartial: (@MainActor (String) -> Void)?
    private var onError: (@MainActor (Error) -> Void)?
    private var onContinuousPartial: (@MainActor (String) -> Void)?

    func requestAuthorization() async -> Bool { isAuthorized }

    func startListening(
        silenceTimeout: TimeInterval,
        onPartialResult: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        startListeningCallCount += 1
        lastSilenceTimeout = silenceTimeout
        isListening = true
        self.onPartial = onPartialResult
        self.onFinal = onFinalResult
        self.onError = onError
    }

    func stopListening() {
        isListening = false
    }

    func startContinuousRecognition(
        onPartialResult: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.onContinuousPartial = onPartialResult
    }

    func stopContinuousRecognition() {
        self.onContinuousPartial = nil
    }

    // Test hooks
    func emitFinal(_ text: String) { onFinal?(text) }
    func emitPartial(_ text: String) { onPartial?(text) }
    func emitContinuousPartial(_ text: String) { onContinuousPartial?(text) }
}

@MainActor
final class MockTTSService: TTSServiceProtocol {
    var engineState: TTSEngineState = .ready
    var isSpeaking: Bool = false
    var onComplete: (@MainActor () -> Void)?

    private(set) var enqueued: [String] = []
    private(set) var loadCount = 0
    private(set) var stopCount = 0

    func loadEngine() async throws { loadCount += 1; engineState = .ready }
    func unloadEngine() { engineState = .unloaded }
    func enqueueSentence(_ text: String) { enqueued.append(text); isSpeaking = true }
    func stopAndClear() { stopCount += 1; isSpeaking = false }

    /// Simulate the queue draining and TTS finishing.
    func finishSpeaking() {
        isSpeaking = false
        onComplete?()
    }
}

@MainActor
final class MockSoundService: SoundServiceProtocol {
    func playWakeWordDetected() {}
    func playInputComplete() {}
}

@MainActor
final class MockKeychainService: KeychainServiceProtocol {
    private var store: [String: String] = [:]
    func save(account: String, value: String) throws { store[account] = value }
    func load(account: String) -> String? { store[account] }
    func delete(account: String) throws { store[account] = nil }
}

@MainActor
final class MockHermesBridge: HermesBridgeProtocol {
    var connectionState: HermesConnectionState = .connected(persona: "테스트")
    var onProactiveMessage: (@MainActor (String) -> Void)?
    var onConnectionStateChanged: (@MainActor (HermesConnectionState) -> Void)?

    /// Scripted events to emit for the next `send`.
    var scriptedEvents: [HermesEvent] = []
    private(set) var sentMessages: [String] = []

    func connect() { connectionState = .connected(persona: "테스트"); onConnectionStateChanged?(connectionState) }
    func disconnect() { connectionState = .disconnected; onConnectionStateChanged?(connectionState) }
    func reconfigure(host: String, port: Int) { connect() }

    func send(text: String, conversationId: String, user: String?) -> AsyncThrowingStream<HermesEvent, Error> {
        sentMessages.append(text)
        let events = scriptedEvents
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func emitProactive(_ text: String) { onProactiveMessage?(text) }
}
