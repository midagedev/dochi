import Foundation

@MainActor
final class TTSRouter: TTSServiceProtocol {
    private let settings: AppSettings
    private let keychainService: KeychainServiceProtocol

    private let systemTTS = SystemTTSService()
    private let googleCloudTTS = GoogleCloudTTSService()
    private let supertonicTTS = SupertonicService()

    /// Tracks whether we're currently using a fallback provider.
    private(set) var isFallbackActive: Bool = false
    private(set) var fallbackProviderName: String?
    private var originalProvider: TTSProvider?

    /// Callback for fallback state changes (used by ViewModel).
    var onFallbackStateChanged: ((_ active: Bool, _ providerName: String?) -> Void)?

    var onComplete: (@MainActor () -> Void)? {
        didSet {
            systemTTS.onComplete = onComplete
            googleCloudTTS.onComplete = onComplete
            supertonicTTS.onComplete = onComplete
        }
    }

    var engineState: TTSEngineState {
        activeService.engineState
    }

    var isSpeaking: Bool {
        systemTTS.isSpeaking || googleCloudTTS.isSpeaking || supertonicTTS.isSpeaking
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
        case .onnxLocal:
            return supertonicTTS
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

        supertonicTTS.speed = speed
        supertonicTTS.diffusionSteps = settings.ttsDiffusionSteps
    }

    // MARK: - TTSServiceProtocol

    func loadEngine() async throws {
        syncSettings()
        do {
            try await activeService.loadEngine()
        } catch {
            // If loading the active service fails and it's a cloud provider,
            // attempt offline fallback
            if settings.ttsOfflineFallbackEnabled && !settings.currentTTSProvider.isLocal {
                Log.tts.warning("Active TTS engine load failed, attempting offline fallback: \(error.localizedDescription)")
                try await activateOfflineFallback()
                return
            }
            throw error
        }
    }

    func unloadEngine() {
        systemTTS.unloadEngine()
        googleCloudTTS.unloadEngine()
        supertonicTTS.unloadEngine()
    }

    func enqueueSentence(_ text: String) {
        syncSettings()
        activeService.enqueueSentence(text)
    }

    func stopAndClear() {
        systemTTS.stopAndClear()
        googleCloudTTS.stopAndClear()
        supertonicTTS.stopAndClear()
    }

    // MARK: - Offline Fallback

    /// Attempt to fall back to a local TTS provider.
    /// Priority: ONNX (if model installed) -> System TTS
    private func activateOfflineFallback() async throws {
        let currentProvider = settings.currentTTSProvider
        guard !currentProvider.isLocal else { return }

        originalProvider = currentProvider

        // Try ONNX first if a model is installed
        if !settings.onnxModelId.isEmpty {
            do {
                settings.ttsProvider = TTSProvider.onnxLocal.rawValue
                syncSettings()
                try await supertonicTTS.loadEngine()
                isFallbackActive = true
                fallbackProviderName = TTSProvider.onnxLocal.displayName
                onFallbackStateChanged?(true, fallbackProviderName)
                Log.tts.info("TTS offline fallback activated: ONNX")
                return
            } catch {
                Log.tts.warning("ONNX fallback failed: \(error.localizedDescription), trying system TTS")
            }
        }

        // Fall back to system TTS
        settings.ttsProvider = TTSProvider.system.rawValue
        syncSettings()
        try await systemTTS.loadEngine()
        isFallbackActive = true
        fallbackProviderName = TTSProvider.system.displayName
        onFallbackStateChanged?(true, fallbackProviderName)
        Log.tts.info("TTS offline fallback activated: System TTS")
    }

    /// Restore the original TTS provider after fallback.
    func restoreTTSProvider() {
        guard isFallbackActive, let original = originalProvider else { return }

        settings.ttsProvider = original.rawValue
        isFallbackActive = false
        fallbackProviderName = nil
        originalProvider = nil
        onFallbackStateChanged?(false, nil)
        Log.tts.info("TTS provider restored to: \(original.displayName)")

        // Reload the original engine
        Task {
            try? await loadEngine()
        }
    }
}
