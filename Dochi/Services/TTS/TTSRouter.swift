import Foundation

@MainActor
final class TTSRouter: TTSServiceProtocol {
    private let settings: AppSettings
    private let keychainService: KeychainServiceProtocol

    private let systemTTS = SystemTTSService()
    private let googleCloudTTS = GoogleCloudTTSService()

    var onComplete: (@MainActor () -> Void)? {
        didSet {
            systemTTS.onComplete = onComplete
            googleCloudTTS.onComplete = onComplete
        }
    }

    var engineState: TTSEngineState {
        activeService.engineState
    }

    var isSpeaking: Bool {
        systemTTS.isSpeaking || googleCloudTTS.isSpeaking
    }

    init(settings: AppSettings, keychainService: KeychainServiceProtocol) {
        self.settings = settings
        self.keychainService = keychainService
    }

    // MARK: - Active Service

    private var activeService: TTSServiceProtocol {
        switch settings.currentTTSProvider {
        case .googleCloud:
            return googleCloudTTS
        case .system:
            return systemTTS
        }
    }

    // MARK: - Settings Sync

    private func syncSettings() {
        let speed = Float(settings.ttsSpeed)

        systemTTS.speed = speed

        googleCloudTTS.speed = speed
        googleCloudTTS.pitch = Float(settings.ttsPitch)
        googleCloudTTS.voiceName = settings.googleCloudVoiceName
        googleCloudTTS.apiKey = keychainService.load(account: TTSProvider.googleCloud.keychainAccount) ?? ""
    }

    // MARK: - TTSServiceProtocol

    func loadEngine() async throws {
        syncSettings()
        try await activeService.loadEngine()
    }

    func unloadEngine() {
        systemTTS.unloadEngine()
        googleCloudTTS.unloadEngine()
    }

    func enqueueSentence(_ text: String) {
        syncSettings()
        activeService.enqueueSentence(text)
    }

    func stopAndClear() {
        systemTTS.stopAndClear()
        googleCloudTTS.stopAndClear()
    }
}
