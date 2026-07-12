import Foundation

/// User-facing settings for the voice + character front-end.
///
/// Anything about *thinking* (model choice, memory, tools) now lives in the
/// Hermes backend, so this holds only what Dochi itself owns: how it listens
/// (STT, wake word), how it speaks (TTS), how the avatar looks, and where the
/// Hermes bridge is.
@MainActor
@Observable
final class AppSettings {
    static let avatarCameraZoomDefault: Double = 0.9
    static let avatarCameraZoomRange: ClosedRange<Double> = 0.5...1.25

    static func normalizedAvatarCameraZoom(_ value: Double?) -> Double {
        let raw = value ?? avatarCameraZoomDefault
        return min(max(raw, avatarCameraZoomRange.lowerBound), avatarCameraZoomRange.upperBound)
    }

    init() {
        // Normalize the persisted avatar model id once at launch.
        let defaults = UserDefaults.standard
        let normalizedModel = AvatarModelCatalog.normalizedModelID(defaults.string(forKey: "avatarModelName"))
        defaults.set(normalizedModel, forKey: "avatarModelName")
    }

    // MARK: - Interaction Mode

    var interactionMode: String = UserDefaults.standard.string(forKey: "interactionMode") ?? InteractionMode.voiceAndText.rawValue {
        didSet { UserDefaults.standard.set(interactionMode, forKey: "interactionMode") }
    }
    var currentInteractionMode: InteractionMode {
        InteractionMode(rawValue: interactionMode) ?? .voiceAndText
    }

    var chatFontSize: Double = UserDefaults.standard.object(forKey: "chatFontSize") as? Double ?? 14.0 {
        didSet { UserDefaults.standard.set(chatFontSize, forKey: "chatFontSize") }
    }

    /// Optional user identity passed to Hermes (for its per-user memory).
    var defaultUserId: String = UserDefaults.standard.string(forKey: "defaultUserId") ?? "" {
        didSet { UserDefaults.standard.set(defaultUserId, forKey: "defaultUserId") }
    }

    // MARK: - Speech-to-Text / Wake Word

    var sttSilenceTimeout: Double = UserDefaults.standard.object(forKey: "sttSilenceTimeout") as? Double ?? 2.0 {
        didSet { UserDefaults.standard.set(sttSilenceTimeout, forKey: "sttSilenceTimeout") }
    }
    var wakeWordEnabled: Bool = UserDefaults.standard.object(forKey: "wakeWordEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wakeWordEnabled, forKey: "wakeWordEnabled") }
    }
    var wakeWord: String = UserDefaults.standard.string(forKey: "wakeWord") ?? "도치야" {
        didSet { UserDefaults.standard.set(wakeWord, forKey: "wakeWord") }
    }
    var wakeWordAlwaysOn: Bool = UserDefaults.standard.object(forKey: "wakeWordAlwaysOn") as? Bool ?? false {
        didSet { UserDefaults.standard.set(wakeWordAlwaysOn, forKey: "wakeWordAlwaysOn") }
    }

    // MARK: - Text-to-Speech

    var ttsProvider: String = UserDefaults.standard.string(forKey: "ttsProvider") ?? TTSProvider.system.rawValue {
        didSet { UserDefaults.standard.set(ttsProvider, forKey: "ttsProvider") }
    }
    var currentTTSProvider: TTSProvider {
        TTSProvider(rawValue: ttsProvider) ?? .system
    }

    var ttsSpeed: Double = UserDefaults.standard.object(forKey: "ttsSpeed") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(ttsSpeed, forKey: "ttsSpeed") }
    }
    var ttsPitch: Double = UserDefaults.standard.object(forKey: "ttsPitch") as? Double ?? 0.0 {
        didSet { UserDefaults.standard.set(ttsPitch, forKey: "ttsPitch") }
    }
    var ttsDiffusionSteps: Int = UserDefaults.standard.object(forKey: "ttsDiffusionSteps") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(ttsDiffusionSteps, forKey: "ttsDiffusionSteps") }
    }
    var ttsOfflineFallbackEnabled: Bool = UserDefaults.standard.object(forKey: "ttsOfflineFallbackEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(ttsOfflineFallbackEnabled, forKey: "ttsOfflineFallbackEnabled") }
    }

    // ONNX / Supertonic local TTS
    var onnxModelId: String = UserDefaults.standard.string(forKey: "onnxModelId") ?? "" {
        didSet { UserDefaults.standard.set(onnxModelId, forKey: "onnxModelId") }
    }
    var supertonicVoice: String = UserDefaults.standard.string(forKey: "supertonicVoice") ?? SupertonicVoice.F1.rawValue {
        didSet { UserDefaults.standard.set(supertonicVoice, forKey: "supertonicVoice") }
    }
    var currentVoice: SupertonicVoice {
        SupertonicVoice(rawValue: supertonicVoice) ?? .F1
    }

    // Google Cloud TTS
    var googleCloudVoiceName: String = UserDefaults.standard.string(forKey: "googleCloudVoiceName") ?? GoogleCloudVoice.defaultVoiceName {
        didSet { UserDefaults.standard.set(googleCloudVoiceName, forKey: "googleCloudVoiceName") }
    }

    // Typecast TTS
    var typecastVoiceId: String = UserDefaults.standard.string(forKey: "typecastVoiceId") ?? "" {
        didSet { UserDefaults.standard.set(typecastVoiceId, forKey: "typecastVoiceId") }
    }
    var typecastModel: String = UserDefaults.standard.string(forKey: "typecastModel") ?? "ssfm-v30" {
        didSet { UserDefaults.standard.set(typecastModel, forKey: "typecastModel") }
    }
    var typecastLanguage: String = UserDefaults.standard.string(forKey: "typecastLanguage") ?? "kor" {
        didSet { UserDefaults.standard.set(typecastLanguage, forKey: "typecastLanguage") }
    }
    var typecastEmotionType: String = UserDefaults.standard.string(forKey: "typecastEmotionType") ?? "preset" {
        didSet { UserDefaults.standard.set(typecastEmotionType, forKey: "typecastEmotionType") }
    }
    var typecastEmotionPreset: String = UserDefaults.standard.string(forKey: "typecastEmotionPreset") ?? "normal" {
        didSet { UserDefaults.standard.set(typecastEmotionPreset, forKey: "typecastEmotionPreset") }
    }
    var typecastEmotionIntensity: Double = UserDefaults.standard.object(forKey: "typecastEmotionIntensity") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(typecastEmotionIntensity, forKey: "typecastEmotionIntensity") }
    }
    var typecastVolume: Int = UserDefaults.standard.object(forKey: "typecastVolume") as? Int ?? 100 {
        didSet { UserDefaults.standard.set(typecastVolume, forKey: "typecastVolume") }
    }
    var typecastAudioPitch: Int = UserDefaults.standard.object(forKey: "typecastAudioPitch") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(typecastAudioPitch, forKey: "typecastAudioPitch") }
    }
    var typecastAudioFormat: String = UserDefaults.standard.string(forKey: "typecastAudioFormat") ?? "wav" {
        didSet { UserDefaults.standard.set(typecastAudioFormat, forKey: "typecastAudioFormat") }
    }

    // MARK: - Avatar

    var avatarEnabled: Bool = UserDefaults.standard.object(forKey: "avatarEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(avatarEnabled, forKey: "avatarEnabled") }
    }
    var avatarModelName: String = AvatarModelCatalog.normalizedModelID(UserDefaults.standard.string(forKey: "avatarModelName")) {
        didSet {
            let normalized = AvatarModelCatalog.normalizedModelID(avatarModelName)
            if normalized != avatarModelName {
                avatarModelName = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: "avatarModelName")
        }
    }
    var avatarCameraZoom: Double = AppSettings.normalizedAvatarCameraZoom(
        UserDefaults.standard.object(forKey: "avatarCameraZoom") as? Double
    ) {
        didSet {
            let normalized = AppSettings.normalizedAvatarCameraZoom(avatarCameraZoom)
            if normalized != avatarCameraZoom {
                avatarCameraZoom = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: "avatarCameraZoom")
        }
    }

    // MARK: - Hermes Agent Backend

    /// Host of the local dochi-hermes-bridge WebSocket server.
    var hermesBridgeHost: String = UserDefaults.standard.string(forKey: "hermesBridgeHost") ?? "127.0.0.1" {
        didSet { UserDefaults.standard.set(hermesBridgeHost, forKey: "hermesBridgeHost") }
    }
    /// Port of the local dochi-hermes-bridge WebSocket server.
    var hermesBridgePort: Int = UserDefaults.standard.object(forKey: "hermesBridgePort") as? Int ?? 8765 {
        didSet { UserDefaults.standard.set(hermesBridgePort, forKey: "hermesBridgePort") }
    }
}
