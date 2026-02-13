import Foundation

struct GoogleCloudVoice: Identifiable, Sendable {
    let id: String          // e.g. "ko-KR-Chirp3-HD-Aoede"
    let name: String        // API voice name
    let displayName: String // UI display name
    let gender: Gender
    let tier: Tier

    enum Gender: String, Sendable {
        case female, male
    }

    enum Tier: String, Sendable {
        case chirp3HD = "Chirp3-HD"
        case wavenet = "WaveNet"
        case neural2 = "Neural2"
        case standard = "Standard"

        var displayName: String { rawValue }
    }
}

extension GoogleCloudVoice {
    /// Korean voice catalog — curated subset of Google Cloud TTS voices.
    static let koreanVoices: [GoogleCloudVoice] = [
        // Chirp3-HD (highest quality)
        .init(id: "ko-KR-Chirp3-HD-Aoede", name: "ko-KR-Chirp3-HD-Aoede", displayName: "Aoede (여성)", gender: .female, tier: .chirp3HD),
        .init(id: "ko-KR-Chirp3-HD-Charon", name: "ko-KR-Chirp3-HD-Charon", displayName: "Charon (남성)", gender: .male, tier: .chirp3HD),
        .init(id: "ko-KR-Chirp3-HD-Kore", name: "ko-KR-Chirp3-HD-Kore", displayName: "Kore (여성)", gender: .female, tier: .chirp3HD),
        .init(id: "ko-KR-Chirp3-HD-Puck", name: "ko-KR-Chirp3-HD-Puck", displayName: "Puck (남성)", gender: .male, tier: .chirp3HD),

        // WaveNet
        .init(id: "ko-KR-Wavenet-A", name: "ko-KR-Wavenet-A", displayName: "Wavenet A (여성)", gender: .female, tier: .wavenet),
        .init(id: "ko-KR-Wavenet-B", name: "ko-KR-Wavenet-B", displayName: "Wavenet B (여성)", gender: .female, tier: .wavenet),
        .init(id: "ko-KR-Wavenet-C", name: "ko-KR-Wavenet-C", displayName: "Wavenet C (남성)", gender: .male, tier: .wavenet),
        .init(id: "ko-KR-Wavenet-D", name: "ko-KR-Wavenet-D", displayName: "Wavenet D (남성)", gender: .male, tier: .wavenet),

        // Neural2
        .init(id: "ko-KR-Neural2-A", name: "ko-KR-Neural2-A", displayName: "Neural2 A (여성)", gender: .female, tier: .neural2),
        .init(id: "ko-KR-Neural2-B", name: "ko-KR-Neural2-B", displayName: "Neural2 B (여성)", gender: .female, tier: .neural2),
        .init(id: "ko-KR-Neural2-C", name: "ko-KR-Neural2-C", displayName: "Neural2 C (남성)", gender: .male, tier: .neural2),

        // Standard
        .init(id: "ko-KR-Standard-A", name: "ko-KR-Standard-A", displayName: "Standard A (여성)", gender: .female, tier: .standard),
        .init(id: "ko-KR-Standard-B", name: "ko-KR-Standard-B", displayName: "Standard B (여성)", gender: .female, tier: .standard),
        .init(id: "ko-KR-Standard-C", name: "ko-KR-Standard-C", displayName: "Standard C (남성)", gender: .male, tier: .standard),
        .init(id: "ko-KR-Standard-D", name: "ko-KR-Standard-D", displayName: "Standard D (남성)", gender: .male, tier: .standard),
    ]

    static let defaultVoiceName = "ko-KR-Chirp3-HD-Aoede"

    /// Group voices by tier for display.
    static var voicesByTier: [(tier: Tier, voices: [GoogleCloudVoice])] {
        let tiers: [Tier] = [.chirp3HD, .wavenet, .neural2, .standard]
        return tiers.compactMap { tier in
            let voices = koreanVoices.filter { $0.tier == tier }
            return voices.isEmpty ? nil : (tier, voices)
        }
    }
}
