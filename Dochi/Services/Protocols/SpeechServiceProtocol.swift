import Foundation

@MainActor
protocol SpeechServiceProtocol {
    /// Whether microphone permission is granted
    var isAuthorized: Bool { get }

    /// Whether currently listening
    var isListening: Bool { get }

    /// Request microphone permission
    func requestAuthorization() async -> Bool

    /// Start speech recognition. Returns transcribed text via callback.
    /// - Parameters:
    ///   - silenceTimeout: seconds of silence before auto-stopping
    ///   - onPartialResult: called with intermediate transcription results
    ///   - onFinalResult: called with the final transcribed text
    ///   - onError: called when an error occurs
    func startListening(
        silenceTimeout: TimeInterval,
        onPartialResult: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    )

    /// Stop speech recognition
    func stopListening()

    /// Start continuous recognition for wake word detection (no silence timeout).
    /// Automatically restarts every 60 seconds to handle Apple STT limits.
    func startContinuousRecognition(
        onPartialResult: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    )

    /// Stop continuous recognition
    func stopContinuousRecognition()
}
