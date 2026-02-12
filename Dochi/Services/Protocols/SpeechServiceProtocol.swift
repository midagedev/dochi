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
}
