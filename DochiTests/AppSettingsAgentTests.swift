import XCTest
@testable import Dochi

@MainActor
final class AppSettingsAgentTests: XCTestCase {
    func testNativeProvidersUseCurrentSupportedDefaultModels() {
        XCTAssertEqual(NativeModelProviderKind.anthropic.defaultModel, "claude-sonnet-5")
        XCTAssertEqual(NativeModelProviderKind.openAI.defaultModel, "gpt-5.6")
        XCTAssertEqual(NativeModelProviderKind.gemini.defaultModel, "gemini-3.5-flash")
        XCTAssertEqual(NativeModelProviderKind.openAICompatible.defaultModel, "")
    }

    func testNativeModelPreferenceIsKeptPerProvider() {
        let defaults = UserDefaults.standard
        let keys = [
            "nativeProviderKind",
            "nativeModel",
            "nativeModel.anthropic",
            "nativeModel.openAI",
        ]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = saved[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        for key in keys { defaults.removeObject(forKey: key) }
        defaults.set(NativeModelProviderKind.anthropic.rawValue, forKey: "nativeProviderKind")
        let settings = AppSettings()
        settings.nativeModel = "custom-claude"

        settings.nativeProviderKind = NativeModelProviderKind.openAI.rawValue
        XCTAssertEqual(settings.nativeModel, NativeModelProviderKind.openAI.defaultModel)
        settings.nativeModel = "custom-openai"

        settings.nativeProviderKind = NativeModelProviderKind.anthropic.rawValue
        XCTAssertEqual(settings.nativeModel, "custom-claude")
        settings.nativeProviderKind = NativeModelProviderKind.openAI.rawValue
        XCTAssertEqual(settings.nativeModel, "custom-openai")
    }
}
