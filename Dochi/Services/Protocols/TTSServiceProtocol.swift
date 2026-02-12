import Foundation

@MainActor
protocol TTSServiceProtocol {
    /// Current engine state
    var engineState: TTSEngineState { get }

    /// Whether TTS is currently speaking
    var isSpeaking: Bool { get }

    /// Load TTS model and prepare for synthesis
    func loadEngine() async throws

    /// Unload TTS model to free memory
    func unloadEngine()

    /// Enqueue a sentence for TTS synthesis and playback.
    /// Sentences are queued and played sequentially.
    func enqueueSentence(_ text: String)

    /// Stop all playback and clear the queue
    func stopAndClear()

    /// Called when all queued sentences have been spoken
    var onComplete: (@MainActor () -> Void)? { get set }
}

enum TTSEngineState: Sendable {
    case unloaded
    case loading
    case ready
    case error(String)
}
