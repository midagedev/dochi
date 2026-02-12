import Foundation
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    // MARK: - P1 Settings

    @ObservationIgnored
    @AppStorage("llmProvider") var llmProvider: String = LLMProvider.openai.rawValue

    @ObservationIgnored
    @AppStorage("llmModel") var llmModel: String = "gpt-4o"

    @ObservationIgnored
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0

    @ObservationIgnored
    @AppStorage("interactionMode") var interactionMode: String = InteractionMode.voiceAndText.rawValue

    @ObservationIgnored
    @AppStorage("contextAutoCompress") var contextAutoCompress: Bool = true

    @ObservationIgnored
    @AppStorage("contextMaxSize") var contextMaxSize: Int = 80_000

    @ObservationIgnored
    @AppStorage("activeAgentName") var activeAgentName: String = "도치"

    @ObservationIgnored
    @AppStorage("uiDensity") var uiDensity: String = "normal"

    // MARK: - P2 Settings

    @ObservationIgnored
    @AppStorage("wakeWordEnabled") var wakeWordEnabled: Bool = true

    @ObservationIgnored
    @AppStorage("wakeWord") var wakeWord: String = "도치야"

    @ObservationIgnored
    @AppStorage("sttSilenceTimeout") var sttSilenceTimeout: Double = 2.0

    @ObservationIgnored
    @AppStorage("supertonicVoice") var supertonicVoice: String = SupertonicVoice.F1.rawValue

    @ObservationIgnored
    @AppStorage("ttsSpeed") var ttsSpeed: Double = 1.0

    @ObservationIgnored
    @AppStorage("ttsDiffusionSteps") var ttsDiffusionSteps: Int = 3

    // MARK: - P4 Settings

    @ObservationIgnored
    @AppStorage("telegramEnabled") var telegramEnabled: Bool = false

    @ObservationIgnored
    @AppStorage("telegramStreamReplies") var telegramStreamReplies: Bool = true

    @ObservationIgnored
    @AppStorage("currentWorkspaceId") var currentWorkspaceId: String = "00000000-0000-0000-0000-000000000000"

    @ObservationIgnored
    @AppStorage("hasSeenPermissionInfo") var hasSeenPermissionInfo: Bool = false

    @ObservationIgnored
    @AppStorage("supabaseURL") var supabaseURL: String = ""

    @ObservationIgnored
    @AppStorage("supabaseAnonKey") var supabaseAnonKey: String = ""

    @ObservationIgnored
    @AppStorage("mcpServersJSON") var mcpServersJSON: String = "[]"

    @ObservationIgnored
    @AppStorage("wakeWordAlwaysOn") var wakeWordAlwaysOn: Bool = false

    // MARK: - P5 Settings

    @ObservationIgnored
    @AppStorage("fallbackLLMProvider") var fallbackLLMProvider: String = ""

    @ObservationIgnored
    @AppStorage("fallbackLLMModel") var fallbackLLMModel: String = ""

    // MARK: - Heartbeat / Proactive Agent

    @ObservationIgnored
    @AppStorage("heartbeatEnabled") var heartbeatEnabled: Bool = false

    @ObservationIgnored
    @AppStorage("heartbeatIntervalMinutes") var heartbeatIntervalMinutes: Int = 30

    @ObservationIgnored
    @AppStorage("heartbeatCheckCalendar") var heartbeatCheckCalendar: Bool = true

    @ObservationIgnored
    @AppStorage("heartbeatCheckKanban") var heartbeatCheckKanban: Bool = true

    @ObservationIgnored
    @AppStorage("heartbeatCheckReminders") var heartbeatCheckReminders: Bool = true

    @ObservationIgnored
    @AppStorage("heartbeatQuietHoursStart") var heartbeatQuietHoursStart: Int = 23

    @ObservationIgnored
    @AppStorage("heartbeatQuietHoursEnd") var heartbeatQuietHoursEnd: Int = 8

    // MARK: - Computed

    var currentProvider: LLMProvider {
        LLMProvider(rawValue: llmProvider) ?? .openai
    }

    var currentInteractionMode: InteractionMode {
        InteractionMode(rawValue: interactionMode) ?? .voiceAndText
    }

    var currentVoice: SupertonicVoice {
        SupertonicVoice(rawValue: supertonicVoice) ?? .F1
    }
}
