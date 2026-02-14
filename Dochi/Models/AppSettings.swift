import Foundation
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    // MARK: - P1 Settings

    var llmProvider: String = UserDefaults.standard.string(forKey: "llmProvider") ?? LLMProvider.openai.rawValue {
        didSet { UserDefaults.standard.set(llmProvider, forKey: "llmProvider") }
    }

    var llmModel: String = UserDefaults.standard.string(forKey: "llmModel") ?? "gpt-4o" {
        didSet { UserDefaults.standard.set(llmModel, forKey: "llmModel") }
    }

    var chatFontSize: Double = UserDefaults.standard.object(forKey: "chatFontSize") as? Double ?? 14.0 {
        didSet { UserDefaults.standard.set(chatFontSize, forKey: "chatFontSize") }
    }

    var interactionMode: String = UserDefaults.standard.string(forKey: "interactionMode") ?? InteractionMode.voiceAndText.rawValue {
        didSet { UserDefaults.standard.set(interactionMode, forKey: "interactionMode") }
    }

    var contextAutoCompress: Bool = UserDefaults.standard.object(forKey: "contextAutoCompress") as? Bool ?? true {
        didSet { UserDefaults.standard.set(contextAutoCompress, forKey: "contextAutoCompress") }
    }

    var contextMaxSize: Int = UserDefaults.standard.object(forKey: "contextMaxSize") as? Int ?? 80_000 {
        didSet { UserDefaults.standard.set(contextMaxSize, forKey: "contextMaxSize") }
    }

    var activeAgentName: String = UserDefaults.standard.string(forKey: "activeAgentName") ?? "도치" {
        didSet { UserDefaults.standard.set(activeAgentName, forKey: "activeAgentName") }
    }

    var uiDensity: String = UserDefaults.standard.string(forKey: "uiDensity") ?? "normal" {
        didSet { UserDefaults.standard.set(uiDensity, forKey: "uiDensity") }
    }

    // MARK: - P2 Settings

    var wakeWordEnabled: Bool = UserDefaults.standard.object(forKey: "wakeWordEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wakeWordEnabled, forKey: "wakeWordEnabled") }
    }

    var wakeWord: String = UserDefaults.standard.string(forKey: "wakeWord") ?? "도치야" {
        didSet { UserDefaults.standard.set(wakeWord, forKey: "wakeWord") }
    }

    var sttSilenceTimeout: Double = UserDefaults.standard.object(forKey: "sttSilenceTimeout") as? Double ?? 2.0 {
        didSet { UserDefaults.standard.set(sttSilenceTimeout, forKey: "sttSilenceTimeout") }
    }

    var supertonicVoice: String = UserDefaults.standard.string(forKey: "supertonicVoice") ?? SupertonicVoice.F1.rawValue {
        didSet { UserDefaults.standard.set(supertonicVoice, forKey: "supertonicVoice") }
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

    var ttsProvider: String = UserDefaults.standard.string(forKey: "ttsProvider") ?? TTSProvider.system.rawValue {
        didSet { UserDefaults.standard.set(ttsProvider, forKey: "ttsProvider") }
    }

    var googleCloudVoiceName: String = UserDefaults.standard.string(forKey: "googleCloudVoiceName") ?? GoogleCloudVoice.defaultVoiceName {
        didSet { UserDefaults.standard.set(googleCloudVoiceName, forKey: "googleCloudVoiceName") }
    }

    // MARK: - P4 Settings

    var telegramEnabled: Bool = UserDefaults.standard.object(forKey: "telegramEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(telegramEnabled, forKey: "telegramEnabled") }
    }

    var telegramStreamReplies: Bool = UserDefaults.standard.object(forKey: "telegramStreamReplies") as? Bool ?? true {
        didSet { UserDefaults.standard.set(telegramStreamReplies, forKey: "telegramStreamReplies") }
    }

    var currentWorkspaceId: String = UserDefaults.standard.string(forKey: "currentWorkspaceId") ?? "00000000-0000-0000-0000-000000000000" {
        didSet { UserDefaults.standard.set(currentWorkspaceId, forKey: "currentWorkspaceId") }
    }

    var deviceId: String = UserDefaults.standard.string(forKey: "deviceId") ?? "" {
        didSet { UserDefaults.standard.set(deviceId, forKey: "deviceId") }
    }

    var ollamaBaseURL: String = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434" {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }

    var hasSeenPermissionInfo: Bool = UserDefaults.standard.object(forKey: "hasSeenPermissionInfo") as? Bool ?? false {
        didSet { UserDefaults.standard.set(hasSeenPermissionInfo, forKey: "hasSeenPermissionInfo") }
    }

    var supabaseURL: String = UserDefaults.standard.string(forKey: "supabaseURL") ?? "" {
        didSet { UserDefaults.standard.set(supabaseURL, forKey: "supabaseURL") }
    }

    var supabaseAnonKey: String = UserDefaults.standard.string(forKey: "supabaseAnonKey") ?? "" {
        didSet { UserDefaults.standard.set(supabaseAnonKey, forKey: "supabaseAnonKey") }
    }

    var mcpServersJSON: String = UserDefaults.standard.string(forKey: "mcpServersJSON") ?? "[]" {
        didSet { UserDefaults.standard.set(mcpServersJSON, forKey: "mcpServersJSON") }
    }

    var wakeWordAlwaysOn: Bool = UserDefaults.standard.object(forKey: "wakeWordAlwaysOn") as? Bool ?? false {
        didSet { UserDefaults.standard.set(wakeWordAlwaysOn, forKey: "wakeWordAlwaysOn") }
    }

    // MARK: - Family

    var defaultUserId: String = UserDefaults.standard.string(forKey: "defaultUserId") ?? "" {
        didSet { UserDefaults.standard.set(defaultUserId, forKey: "defaultUserId") }
    }

    // MARK: - P5 Settings

    var fallbackLLMProvider: String = UserDefaults.standard.string(forKey: "fallbackLLMProvider") ?? "" {
        didSet { UserDefaults.standard.set(fallbackLLMProvider, forKey: "fallbackLLMProvider") }
    }

    var fallbackLLMModel: String = UserDefaults.standard.string(forKey: "fallbackLLMModel") ?? "" {
        didSet { UserDefaults.standard.set(fallbackLLMModel, forKey: "fallbackLLMModel") }
    }

    // MARK: - Avatar

    var avatarEnabled: Bool = UserDefaults.standard.object(forKey: "avatarEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(avatarEnabled, forKey: "avatarEnabled") }
    }

    // MARK: - Heartbeat / Proactive Agent

    var heartbeatEnabled: Bool = UserDefaults.standard.object(forKey: "heartbeatEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(heartbeatEnabled, forKey: "heartbeatEnabled") }
    }

    var heartbeatIntervalMinutes: Int = UserDefaults.standard.object(forKey: "heartbeatIntervalMinutes") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(heartbeatIntervalMinutes, forKey: "heartbeatIntervalMinutes") }
    }

    var heartbeatCheckCalendar: Bool = UserDefaults.standard.object(forKey: "heartbeatCheckCalendar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(heartbeatCheckCalendar, forKey: "heartbeatCheckCalendar") }
    }

    var heartbeatCheckKanban: Bool = UserDefaults.standard.object(forKey: "heartbeatCheckKanban") as? Bool ?? true {
        didSet { UserDefaults.standard.set(heartbeatCheckKanban, forKey: "heartbeatCheckKanban") }
    }

    var heartbeatCheckReminders: Bool = UserDefaults.standard.object(forKey: "heartbeatCheckReminders") as? Bool ?? true {
        didSet { UserDefaults.standard.set(heartbeatCheckReminders, forKey: "heartbeatCheckReminders") }
    }

    var heartbeatQuietHoursStart: Int = UserDefaults.standard.object(forKey: "heartbeatQuietHoursStart") as? Int ?? 23 {
        didSet { UserDefaults.standard.set(heartbeatQuietHoursStart, forKey: "heartbeatQuietHoursStart") }
    }

    var heartbeatQuietHoursEnd: Int = UserDefaults.standard.object(forKey: "heartbeatQuietHoursEnd") as? Int ?? 8 {
        didSet { UserDefaults.standard.set(heartbeatQuietHoursEnd, forKey: "heartbeatQuietHoursEnd") }
    }

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

    var currentTTSProvider: TTSProvider {
        TTSProvider(rawValue: ttsProvider) ?? .system
    }
}
