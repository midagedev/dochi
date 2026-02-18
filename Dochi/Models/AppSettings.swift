import Foundation
import SwiftUI

enum OperatingProfile: String, CaseIterable, Codable, Sendable {
    case familyHomeAssistant
    case personalProductivityAssistant

    var displayName: String {
        switch self {
        case .familyHomeAssistant:
            return "가족 홈 어시스턴트"
        case .personalProductivityAssistant:
            return "개인 생산성 어시스턴트"
        }
    }

    var summary: String {
        switch self {
        case .familyHomeAssistant:
            return "가족 일정/할 일/생활 운영을 중심으로 돕습니다."
        case .personalProductivityAssistant:
            return "개인 목표/집중/업무 실행을 중심으로 돕습니다."
        }
    }
}

struct SetupHealthIssue: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let sectionRawValue: String
    let weight: Int
}

struct SetupHealthReport: Equatable, Sendable {
    let score: Int
    let issues: [SetupHealthIssue]

    var primaryIssue: SetupHealthIssue? {
        issues.max { lhs, rhs in lhs.weight < rhs.weight }
    }
}

@MainActor
@Observable
final class AppSettings {
    private static let deprecatedKeys = [
        "uiDensity",
        "hasSeenPermissionInfo",
        "ragEmbeddingProvider",
    ]

    init() {
        let defaults = UserDefaults.standard

        // Remove stale keys for settings that are no longer exposed or used.
        for key in Self.deprecatedKeys {
            defaults.removeObject(forKey: key)
        }

        // Legacy migration: proactive suggestion app notification toggle -> channel policy.
        // If channel key does not exist, preserve old boolean behavior.
        if defaults.string(forKey: "suggestionNotificationChannel") == nil {
            let legacyEnabled = defaults.object(forKey: "notificationProactiveSuggestionEnabled") as? Bool ?? false
            let migrated: NotificationChannel = legacyEnabled ? .appOnly : .off
            defaults.set(migrated.rawValue, forKey: "suggestionNotificationChannel")
        }

        // Repair invalid operating profile values to safe default.
        if let storedProfile = defaults.string(forKey: "operatingProfile"),
           OperatingProfile(rawValue: storedProfile) == nil {
            defaults.set(OperatingProfile.familyHomeAssistant.rawValue, forKey: "operatingProfile")
        }

        if OperatingProfile(rawValue: operatingProfile) == nil {
            operatingProfile = OperatingProfile.familyHomeAssistant.rawValue
        }
    }

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

    var telegramConnectionMode: String = UserDefaults.standard.string(forKey: "telegramConnectionMode") ?? TelegramConnectionMode.polling.rawValue {
        didSet { UserDefaults.standard.set(telegramConnectionMode, forKey: "telegramConnectionMode") }
    }

    var telegramWebhookURL: String = UserDefaults.standard.string(forKey: "telegramWebhookURL") ?? "" {
        didSet { UserDefaults.standard.set(telegramWebhookURL, forKey: "telegramWebhookURL") }
    }

    var telegramWebhookPort: Int = UserDefaults.standard.object(forKey: "telegramWebhookPort") as? Int ?? 8443 {
        didSet { UserDefaults.standard.set(telegramWebhookPort, forKey: "telegramWebhookPort") }
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

    /// JSON mapping of Telegram chat IDs to workspace IDs: {"chatId": "workspaceId", ...}
    var telegramChatMappingJSON: String = UserDefaults.standard.string(forKey: "telegramChatMappingJSON") ?? "{}" {
        didSet { UserDefaults.standard.set(telegramChatMappingJSON, forKey: "telegramChatMappingJSON") }
    }

    /// Whether this device acts as the Telegram host for its workspace.
    var isTelegramHost: Bool = UserDefaults.standard.object(forKey: "isTelegramHost") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isTelegramHost, forKey: "isTelegramHost") }
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

    /// App execution posture chosen during onboarding.
    /// Defaults to family mode when not selected.
    var operatingProfile: String =
        UserDefaults.standard.string(forKey: "operatingProfile")
        ?? OperatingProfile.familyHomeAssistant.rawValue {
        didSet { UserDefaults.standard.set(operatingProfile, forKey: "operatingProfile") }
    }

    // MARK: - P5 Settings

    var fallbackLLMProvider: String = UserDefaults.standard.string(forKey: "fallbackLLMProvider") ?? "" {
        didSet { UserDefaults.standard.set(fallbackLLMProvider, forKey: "fallbackLLMProvider") }
    }

    var fallbackLLMModel: String = UserDefaults.standard.string(forKey: "fallbackLLMModel") ?? "" {
        didSet { UserDefaults.standard.set(fallbackLLMModel, forKey: "fallbackLLMModel") }
    }

    // MARK: - Task Complexity Routing

    var taskRoutingEnabled: Bool = UserDefaults.standard.object(forKey: "taskRoutingEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(taskRoutingEnabled, forKey: "taskRoutingEnabled") }
    }

    var lightModelProvider: String = UserDefaults.standard.string(forKey: "lightModelProvider") ?? "" {
        didSet { UserDefaults.standard.set(lightModelProvider, forKey: "lightModelProvider") }
    }

    var lightModelName: String = UserDefaults.standard.string(forKey: "lightModelName") ?? "" {
        didSet { UserDefaults.standard.set(lightModelName, forKey: "lightModelName") }
    }

    var heavyModelProvider: String = UserDefaults.standard.string(forKey: "heavyModelProvider") ?? "" {
        didSet { UserDefaults.standard.set(heavyModelProvider, forKey: "heavyModelProvider") }
    }

    var heavyModelName: String = UserDefaults.standard.string(forKey: "heavyModelName") ?? "" {
        didSet { UserDefaults.standard.set(heavyModelName, forKey: "heavyModelName") }
    }

    // MARK: - LM Studio

    var lmStudioBaseURL: String = UserDefaults.standard.string(forKey: "lmStudioBaseURL") ?? "http://localhost:1234" {
        didSet { UserDefaults.standard.set(lmStudioBaseURL, forKey: "lmStudioBaseURL") }
    }

    // MARK: - Offline Fallback

    var offlineFallbackEnabled: Bool = UserDefaults.standard.object(forKey: "offlineFallbackEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(offlineFallbackEnabled, forKey: "offlineFallbackEnabled") }
    }

    var offlineFallbackProvider: String = UserDefaults.standard.string(forKey: "offlineFallbackProvider") ?? "ollama" {
        didSet { UserDefaults.standard.set(offlineFallbackProvider, forKey: "offlineFallbackProvider") }
    }

    var offlineFallbackModel: String = UserDefaults.standard.string(forKey: "offlineFallbackModel") ?? "" {
        didSet { UserDefaults.standard.set(offlineFallbackModel, forKey: "offlineFallbackModel") }
    }

    // MARK: - ONNX TTS

    var onnxModelId: String = UserDefaults.standard.string(forKey: "onnxModelId") ?? "" {
        didSet { UserDefaults.standard.set(onnxModelId, forKey: "onnxModelId") }
    }

    var ttsOfflineFallbackEnabled: Bool = UserDefaults.standard.object(forKey: "ttsOfflineFallbackEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(ttsOfflineFallbackEnabled, forKey: "ttsOfflineFallbackEnabled") }
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

    // MARK: - Automation / Scheduler (J-3)

    var automationEnabled: Bool = UserDefaults.standard.object(forKey: "automationEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(automationEnabled, forKey: "automationEnabled") }
    }

    // MARK: - Budget Settings (G-4)

    var budgetEnabled: Bool = UserDefaults.standard.object(forKey: "budgetEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(budgetEnabled, forKey: "budgetEnabled") }
    }

    var monthlyBudgetUSD: Double = UserDefaults.standard.object(forKey: "monthlyBudgetUSD") as? Double ?? 10.0 {
        didSet { UserDefaults.standard.set(monthlyBudgetUSD, forKey: "monthlyBudgetUSD") }
    }

    var budgetAlert50: Bool = UserDefaults.standard.object(forKey: "budgetAlert50") as? Bool ?? true {
        didSet { UserDefaults.standard.set(budgetAlert50, forKey: "budgetAlert50") }
    }

    var budgetAlert80: Bool = UserDefaults.standard.object(forKey: "budgetAlert80") as? Bool ?? true {
        didSet { UserDefaults.standard.set(budgetAlert80, forKey: "budgetAlert80") }
    }

    var budgetAlert100: Bool = UserDefaults.standard.object(forKey: "budgetAlert100") as? Bool ?? true {
        didSet { UserDefaults.standard.set(budgetAlert100, forKey: "budgetAlert100") }
    }

    var budgetBlockOnExceed: Bool = UserDefaults.standard.object(forKey: "budgetBlockOnExceed") as? Bool ?? false {
        didSet { UserDefaults.standard.set(budgetBlockOnExceed, forKey: "budgetBlockOnExceed") }
    }

    // MARK: - Sync Settings (G-3)

    var autoSyncEnabled: Bool = UserDefaults.standard.object(forKey: "autoSyncEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: "autoSyncEnabled") }
    }

    var realtimeSyncEnabled: Bool = UserDefaults.standard.object(forKey: "realtimeSyncEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(realtimeSyncEnabled, forKey: "realtimeSyncEnabled") }
    }

    var syncConversations: Bool = UserDefaults.standard.object(forKey: "syncConversations") as? Bool ?? true {
        didSet { UserDefaults.standard.set(syncConversations, forKey: "syncConversations") }
    }

    var syncMemory: Bool = UserDefaults.standard.object(forKey: "syncMemory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(syncMemory, forKey: "syncMemory") }
    }

    var syncKanban: Bool = UserDefaults.standard.object(forKey: "syncKanban") as? Bool ?? true {
        didSet { UserDefaults.standard.set(syncKanban, forKey: "syncKanban") }
    }

    var syncProfiles: Bool = UserDefaults.standard.object(forKey: "syncProfiles") as? Bool ?? true {
        didSet { UserDefaults.standard.set(syncProfiles, forKey: "syncProfiles") }
    }

    var conflictResolutionStrategy: String = UserDefaults.standard.string(forKey: "conflictResolutionStrategy") ?? "lastWriteWins" {
        didSet { UserDefaults.standard.set(conflictResolutionStrategy, forKey: "conflictResolutionStrategy") }
    }

    // MARK: - Notification Center (H-3)

    var notificationCalendarEnabled: Bool = UserDefaults.standard.object(forKey: "notificationCalendarEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationCalendarEnabled, forKey: "notificationCalendarEnabled") }
    }

    var notificationKanbanEnabled: Bool = UserDefaults.standard.object(forKey: "notificationKanbanEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationKanbanEnabled, forKey: "notificationKanbanEnabled") }
    }

    var notificationReminderEnabled: Bool = UserDefaults.standard.object(forKey: "notificationReminderEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationReminderEnabled, forKey: "notificationReminderEnabled") }
    }

    var notificationMemoryEnabled: Bool = UserDefaults.standard.object(forKey: "notificationMemoryEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationMemoryEnabled, forKey: "notificationMemoryEnabled") }
    }

    var notificationSoundEnabled: Bool = UserDefaults.standard.object(forKey: "notificationSoundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationSoundEnabled, forKey: "notificationSoundEnabled") }
    }

    var notificationReplyEnabled: Bool = UserDefaults.standard.object(forKey: "notificationReplyEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationReplyEnabled, forKey: "notificationReplyEnabled") }
    }

    // MARK: - Menu Bar (H-1)

    var menuBarEnabled: Bool = UserDefaults.standard.object(forKey: "menuBarEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuBarEnabled, forKey: "menuBarEnabled") }
    }

    var menuBarGlobalShortcutEnabled: Bool = UserDefaults.standard.object(forKey: "menuBarGlobalShortcutEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuBarGlobalShortcutEnabled, forKey: "menuBarGlobalShortcutEnabled") }
    }

    // MARK: - Spotlight (H-4)

    var spotlightIndexingEnabled: Bool = UserDefaults.standard.object(forKey: "spotlightIndexingEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(spotlightIndexingEnabled, forKey: "spotlightIndexingEnabled") }
    }

    var spotlightIndexConversations: Bool = UserDefaults.standard.object(forKey: "spotlightIndexConversations") as? Bool ?? true {
        didSet { UserDefaults.standard.set(spotlightIndexConversations, forKey: "spotlightIndexConversations") }
    }

    var spotlightIndexPersonalMemory: Bool = UserDefaults.standard.object(forKey: "spotlightIndexPersonalMemory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(spotlightIndexPersonalMemory, forKey: "spotlightIndexPersonalMemory") }
    }

    var spotlightIndexAgentMemory: Bool = UserDefaults.standard.object(forKey: "spotlightIndexAgentMemory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(spotlightIndexAgentMemory, forKey: "spotlightIndexAgentMemory") }
    }

    var spotlightIndexWorkspaceMemory: Bool = UserDefaults.standard.object(forKey: "spotlightIndexWorkspaceMemory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(spotlightIndexWorkspaceMemory, forKey: "spotlightIndexWorkspaceMemory") }
    }

    // MARK: - Agent Delegation (J-2)

    var delegationEnabled: Bool = UserDefaults.standard.object(forKey: "delegationEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(delegationEnabled, forKey: "delegationEnabled") }
    }

    var delegationMaxChainDepth: Int = UserDefaults.standard.object(forKey: "delegationMaxChainDepth") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(delegationMaxChainDepth, forKey: "delegationMaxChainDepth") }
    }

    var delegationDefaultTimeoutSeconds: Int = UserDefaults.standard.object(forKey: "delegationDefaultTimeoutSeconds") as? Int ?? 120 {
        didSet { UserDefaults.standard.set(delegationDefaultTimeoutSeconds, forKey: "delegationDefaultTimeoutSeconds") }
    }

    // MARK: - Device Policy (J-1)

    var deviceSelectionPolicy: String = UserDefaults.standard.string(forKey: "deviceSelectionPolicy") ?? "priorityBased" {
        didSet { UserDefaults.standard.set(deviceSelectionPolicy, forKey: "deviceSelectionPolicy") }
    }

    var manualResponderDeviceId: String = UserDefaults.standard.string(forKey: "manualResponderDeviceId") ?? "" {
        didSet { UserDefaults.standard.set(manualResponderDeviceId, forKey: "manualResponderDeviceId") }
    }

    var deviceCloudSyncEnabled: Bool = UserDefaults.standard.object(forKey: "deviceCloudSyncEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(deviceCloudSyncEnabled, forKey: "deviceCloudSyncEnabled") }
    }

    var currentDeviceName: String = UserDefaults.standard.string(forKey: "currentDeviceName") ?? "" {
        didSet { UserDefaults.standard.set(currentDeviceName, forKey: "currentDeviceName") }
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

    /// Ephemeral settings deep-link target; not persisted.
    var pendingSettingsDeepLinkSection: String?

    /// Setup completeness score for activation UX.
    func setupHealthReport(hasProviderAPIKey: Bool) -> SetupHealthReport {
        var issues: [SetupHealthIssue] = []

        if currentProvider.requiresAPIKey && !hasProviderAPIKey {
            issues.append(
                SetupHealthIssue(
                    id: "api_key_missing",
                    title: "API 키 설정 필요",
                    detail: "\(currentProvider.rawValue.uppercased()) API 키가 없어 응답 생성이 제한됩니다.",
                    sectionRawValue: "api-key",
                    weight: 40
                )
            )
        }

        let supabaseURLMissing = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let supabaseKeyMissing = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if autoSyncEnabled && (supabaseURLMissing || supabaseKeyMissing) {
            issues.append(
                SetupHealthIssue(
                    id: "sync_config_missing",
                    title: "동기화 연동 설정 필요",
                    detail: "자동 동기화가 켜져 있지만 Supabase 설정이 비어 있습니다.",
                    sectionRawValue: "account",
                    weight: 20
                )
            )
        }

        if proactiveSuggestionEnabled && suggestionNotificationChannel == NotificationChannel.off.rawValue {
            issues.append(
                SetupHealthIssue(
                    id: "proactive_channel_off",
                    title: "프로액티브 알림 채널 비활성",
                    detail: "프로액티브 제안은 켜져 있으나 전달 채널이 꺼져 있습니다.",
                    sectionRawValue: "proactive-suggestion",
                    weight: 15
                )
            )
        }

        if heartbeatEnabled && heartbeatNotificationChannel == NotificationChannel.off.rawValue {
            issues.append(
                SetupHealthIssue(
                    id: "heartbeat_channel_off",
                    title: "하트비트 알림 채널 비활성",
                    detail: "하트비트는 켜져 있으나 알림 채널이 꺼져 있습니다.",
                    sectionRawValue: "heartbeat",
                    weight: 15
                )
            )
        }

        if defaultUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                SetupHealthIssue(
                    id: "default_user_missing",
                    title: "기본 사용자 프로필 필요",
                    detail: "가족/사용자 컨텍스트가 없어 개인화 품질이 낮아질 수 있습니다.",
                    sectionRawValue: "family",
                    weight: 10
                )
            )
        }

        let penalty = min(100, issues.reduce(0) { $0 + $1.weight })
        return SetupHealthReport(score: max(0, 100 - penalty), issues: issues)
    }

    // MARK: - Memory Consolidation (I-2)

    var memoryConsolidationEnabled: Bool = UserDefaults.standard.object(forKey: "memoryConsolidationEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(memoryConsolidationEnabled, forKey: "memoryConsolidationEnabled") }
    }

    var memoryConsolidationMinMessages: Int = UserDefaults.standard.object(forKey: "memoryConsolidationMinMessages") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(memoryConsolidationMinMessages, forKey: "memoryConsolidationMinMessages") }
    }

    var memoryConsolidationModel: String = UserDefaults.standard.string(forKey: "memoryConsolidationModel") ?? "light" {
        didSet { UserDefaults.standard.set(memoryConsolidationModel, forKey: "memoryConsolidationModel") }
    }

    var memoryConsolidationBannerEnabled: Bool = UserDefaults.standard.object(forKey: "memoryConsolidationBannerEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(memoryConsolidationBannerEnabled, forKey: "memoryConsolidationBannerEnabled") }
    }

    var memoryWorkspaceSizeLimit: Int = UserDefaults.standard.object(forKey: "memoryWorkspaceSizeLimit") as? Int ?? 10000 {
        didSet { UserDefaults.standard.set(memoryWorkspaceSizeLimit, forKey: "memoryWorkspaceSizeLimit") }
    }

    var memoryAgentSizeLimit: Int = UserDefaults.standard.object(forKey: "memoryAgentSizeLimit") as? Int ?? 5000 {
        didSet { UserDefaults.standard.set(memoryAgentSizeLimit, forKey: "memoryAgentSizeLimit") }
    }

    var memoryPersonalSizeLimit: Int = UserDefaults.standard.object(forKey: "memoryPersonalSizeLimit") as? Int ?? 8000 {
        didSet { UserDefaults.standard.set(memoryPersonalSizeLimit, forKey: "memoryPersonalSizeLimit") }
    }

    var memoryAutoArchiveEnabled: Bool = UserDefaults.standard.object(forKey: "memoryAutoArchiveEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(memoryAutoArchiveEnabled, forKey: "memoryAutoArchiveEnabled") }
    }

    // MARK: - RAG (I-1)

    var ragEnabled: Bool = UserDefaults.standard.object(forKey: "ragEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(ragEnabled, forKey: "ragEnabled") }
    }

    var ragEmbeddingModel: String = UserDefaults.standard.string(forKey: "ragEmbeddingModel") ?? "text-embedding-3-small" {
        didSet { UserDefaults.standard.set(ragEmbeddingModel, forKey: "ragEmbeddingModel") }
    }

    var ragTopK: Int = UserDefaults.standard.object(forKey: "ragTopK") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(ragTopK, forKey: "ragTopK") }
    }

    var ragMinSimilarity: Double = UserDefaults.standard.object(forKey: "ragMinSimilarity") as? Double ?? 0.3 {
        didSet { UserDefaults.standard.set(ragMinSimilarity, forKey: "ragMinSimilarity") }
    }

    var ragAutoSearch: Bool = UserDefaults.standard.object(forKey: "ragAutoSearch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(ragAutoSearch, forKey: "ragAutoSearch") }
    }

    var ragChunkSize: Int = UserDefaults.standard.object(forKey: "ragChunkSize") as? Int ?? 500 {
        didSet { UserDefaults.standard.set(ragChunkSize, forKey: "ragChunkSize") }
    }

    var ragChunkOverlap: Int = UserDefaults.standard.object(forKey: "ragChunkOverlap") as? Int ?? 100 {
        didSet { UserDefaults.standard.set(ragChunkOverlap, forKey: "ragChunkOverlap") }
    }

    // MARK: - Feedback (I-4)

    var feedbackEnabled: Bool = UserDefaults.standard.object(forKey: "feedbackEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(feedbackEnabled, forKey: "feedbackEnabled") }
    }

    var feedbackShowOnHover: Bool = UserDefaults.standard.object(forKey: "feedbackShowOnHover") as? Bool ?? true {
        didSet { UserDefaults.standard.set(feedbackShowOnHover, forKey: "feedbackShowOnHover") }
    }

    // MARK: - Resource Optimizer (J-5)

    var resourceAutoTaskEnabled: Bool = UserDefaults.standard.object(forKey: "resourceAutoTaskEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(resourceAutoTaskEnabled, forKey: "resourceAutoTaskEnabled") }
    }

    var resourceAutoTaskOnlyWasteRisk: Bool = UserDefaults.standard.object(forKey: "resourceAutoTaskOnlyWasteRisk") as? Bool ?? true {
        didSet { UserDefaults.standard.set(resourceAutoTaskOnlyWasteRisk, forKey: "resourceAutoTaskOnlyWasteRisk") }
    }

    var resourceAutoTaskTypes: [String] = UserDefaults.standard.stringArray(forKey: "resourceAutoTaskTypes") ?? AutoTaskType.allCases.map(\.rawValue) {
        didSet { UserDefaults.standard.set(resourceAutoTaskTypes, forKey: "resourceAutoTaskTypes") }
    }

    // MARK: - Terminal (K-1)

    var terminalShellPath: String = UserDefaults.standard.string(forKey: "terminalShellPath") ?? "/bin/zsh" {
        didSet { UserDefaults.standard.set(terminalShellPath, forKey: "terminalShellPath") }
    }

    var terminalFontSize: Int = UserDefaults.standard.object(forKey: "terminalFontSize") as? Int ?? 14 {
        didSet { UserDefaults.standard.set(terminalFontSize, forKey: "terminalFontSize") }
    }

    var terminalMaxBufferLines: Int = UserDefaults.standard.object(forKey: "terminalMaxBufferLines") as? Int ?? 10000 {
        didSet { UserDefaults.standard.set(terminalMaxBufferLines, forKey: "terminalMaxBufferLines") }
    }

    var terminalCommandTimeout: Int = UserDefaults.standard.object(forKey: "terminalCommandTimeout") as? Int ?? 300 {
        didSet { UserDefaults.standard.set(terminalCommandTimeout, forKey: "terminalCommandTimeout") }
    }

    var terminalMaxSessions: Int = UserDefaults.standard.object(forKey: "terminalMaxSessions") as? Int ?? 8 {
        didSet { UserDefaults.standard.set(terminalMaxSessions, forKey: "terminalMaxSessions") }
    }

    var terminalConfirmOnClose: Bool = UserDefaults.standard.object(forKey: "terminalConfirmOnClose") as? Bool ?? true {
        didSet { UserDefaults.standard.set(terminalConfirmOnClose, forKey: "terminalConfirmOnClose") }
    }

    var terminalLLMEnabled: Bool = UserDefaults.standard.object(forKey: "terminalLLMEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(terminalLLMEnabled, forKey: "terminalLLMEnabled") }
    }

    var terminalLLMConfirmAlways: Bool = UserDefaults.standard.object(forKey: "terminalLLMConfirmAlways") as? Bool ?? true {
        didSet { UserDefaults.standard.set(terminalLLMConfirmAlways, forKey: "terminalLLMConfirmAlways") }
    }

    var terminalAutoShowPanel: Bool = UserDefaults.standard.object(forKey: "terminalAutoShowPanel") as? Bool ?? true {
        didSet { UserDefaults.standard.set(terminalAutoShowPanel, forKey: "terminalAutoShowPanel") }
    }

    var terminalPanelHeight: Double = UserDefaults.standard.object(forKey: "terminalPanelHeight") as? Double ?? 200 {
        didSet { UserDefaults.standard.set(terminalPanelHeight, forKey: "terminalPanelHeight") }
    }

    // MARK: - Proactive Suggestions (K-2)

    var proactiveSuggestionEnabled: Bool = UserDefaults.standard.object(forKey: "proactiveSuggestionEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(proactiveSuggestionEnabled, forKey: "proactiveSuggestionEnabled") }
    }

    var proactiveSuggestionIdleMinutes: Int = UserDefaults.standard.object(forKey: "proactiveSuggestionIdleMinutes") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(proactiveSuggestionIdleMinutes, forKey: "proactiveSuggestionIdleMinutes") }
    }

    var proactiveSuggestionCooldownMinutes: Int = UserDefaults.standard.object(forKey: "proactiveSuggestionCooldownMinutes") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(proactiveSuggestionCooldownMinutes, forKey: "proactiveSuggestionCooldownMinutes") }
    }

    var proactiveDailyCap: Int = UserDefaults.standard.object(forKey: "proactiveDailyCap") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(proactiveDailyCap, forKey: "proactiveDailyCap") }
    }

    var proactiveSuggestionQuietHoursEnabled: Bool = UserDefaults.standard.object(forKey: "proactiveSuggestionQuietHoursEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(proactiveSuggestionQuietHoursEnabled, forKey: "proactiveSuggestionQuietHoursEnabled") }
    }

    var suggestionTypeNewsEnabled: Bool = UserDefaults.standard.object(forKey: "suggestionTypeNewsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(suggestionTypeNewsEnabled, forKey: "suggestionTypeNewsEnabled") }
    }

    var suggestionTypeDeepDiveEnabled: Bool = UserDefaults.standard.object(forKey: "suggestionTypeDeepDiveEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(suggestionTypeDeepDiveEnabled, forKey: "suggestionTypeDeepDiveEnabled") }
    }

    var suggestionTypeResearchEnabled: Bool = UserDefaults.standard.object(forKey: "suggestionTypeResearchEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(suggestionTypeResearchEnabled, forKey: "suggestionTypeResearchEnabled") }
    }

    var suggestionTypeKanbanEnabled: Bool = UserDefaults.standard.object(forKey: "suggestionTypeKanbanEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(suggestionTypeKanbanEnabled, forKey: "suggestionTypeKanbanEnabled") }
    }

    var suggestionTypeMemoryEnabled: Bool = UserDefaults.standard.object(forKey: "suggestionTypeMemoryEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(suggestionTypeMemoryEnabled, forKey: "suggestionTypeMemoryEnabled") }
    }

    var suggestionTypeCostEnabled: Bool = UserDefaults.standard.object(forKey: "suggestionTypeCostEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(suggestionTypeCostEnabled, forKey: "suggestionTypeCostEnabled") }
    }

    var notificationProactiveSuggestionEnabled: Bool {
        get {
            let channel = NotificationChannel(rawValue: suggestionNotificationChannel) ?? .off
            return channel.deliversToApp
        }
        set {
            let current = NotificationChannel(rawValue: suggestionNotificationChannel) ?? .off
            switch (newValue, current) {
            case (true, .telegramOnly):
                suggestionNotificationChannel = NotificationChannel.both.rawValue
            case (true, .off):
                suggestionNotificationChannel = NotificationChannel.appOnly.rawValue
            case (true, _):
                break
            case (false, .both):
                suggestionNotificationChannel = NotificationChannel.telegramOnly.rawValue
            case (false, .appOnly):
                suggestionNotificationChannel = NotificationChannel.off.rawValue
            case (false, _):
                break
            }
            UserDefaults.standard.set(newValue, forKey: "notificationProactiveSuggestionEnabled")
        }
    }

    var proactiveSuggestionMenuBarEnabled: Bool = UserDefaults.standard.object(forKey: "proactiveSuggestionMenuBarEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(proactiveSuggestionMenuBarEnabled, forKey: "proactiveSuggestionMenuBarEnabled") }
    }

    // MARK: - External Tool (K-4)

    var externalToolEnabled: Bool = UserDefaults.standard.object(forKey: "externalToolEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(externalToolEnabled, forKey: "externalToolEnabled") }
    }

    var externalToolHealthCheckIntervalSeconds: Int = UserDefaults.standard.object(forKey: "externalToolHealthCheckIntervalSeconds") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(externalToolHealthCheckIntervalSeconds, forKey: "externalToolHealthCheckIntervalSeconds") }
    }

    var externalToolOutputCaptureLines: Int = UserDefaults.standard.object(forKey: "externalToolOutputCaptureLines") as? Int ?? 100 {
        didSet { UserDefaults.standard.set(externalToolOutputCaptureLines, forKey: "externalToolOutputCaptureLines") }
    }

    var externalToolAutoRestart: Bool = UserDefaults.standard.object(forKey: "externalToolAutoRestart") as? Bool ?? false {
        didSet { UserDefaults.standard.set(externalToolAutoRestart, forKey: "externalToolAutoRestart") }
    }

    var externalToolTmuxPath: String = UserDefaults.standard.string(forKey: "externalToolTmuxPath") ?? "/usr/bin/tmux" {
        didSet { UserDefaults.standard.set(externalToolTmuxPath, forKey: "externalToolTmuxPath") }
    }

    var externalToolSessionPrefix: String = UserDefaults.standard.string(forKey: "externalToolSessionPrefix") ?? "dochi-" {
        didSet { UserDefaults.standard.set(externalToolSessionPrefix, forKey: "externalToolSessionPrefix") }
    }

    // MARK: - Interest Discovery (K-3)

    var interestDiscoveryEnabled: Bool = UserDefaults.standard.object(forKey: "interestDiscoveryEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(interestDiscoveryEnabled, forKey: "interestDiscoveryEnabled") }
    }

    var interestDiscoveryMode: String = UserDefaults.standard.string(forKey: "interestDiscoveryMode") ?? "auto" {
        didSet { UserDefaults.standard.set(interestDiscoveryMode, forKey: "interestDiscoveryMode") }
    }

    var interestExpirationDays: Int = UserDefaults.standard.object(forKey: "interestExpirationDays") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(interestExpirationDays, forKey: "interestExpirationDays") }
    }

    var interestMinDetectionCount: Int = UserDefaults.standard.object(forKey: "interestMinDetectionCount") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(interestMinDetectionCount, forKey: "interestMinDetectionCount") }
    }

    var interestIncludeInPrompt: Bool = UserDefaults.standard.object(forKey: "interestIncludeInPrompt") as? Bool ?? true {
        didSet { UserDefaults.standard.set(interestIncludeInPrompt, forKey: "interestIncludeInPrompt") }
    }

    // MARK: - Telegram Proactive Notifications (K-6)

    /// Heartbeat alert notification channel: appOnly / telegramOnly / both / off
    var heartbeatNotificationChannel: String =
        UserDefaults.standard.string(forKey: "heartbeatNotificationChannel") ?? "appOnly" {
        didSet { UserDefaults.standard.set(heartbeatNotificationChannel, forKey: "heartbeatNotificationChannel") }
    }

    /// Proactive suggestion notification channel: appOnly / telegramOnly / both / off
    var suggestionNotificationChannel: String =
        UserDefaults.standard.string(forKey: "suggestionNotificationChannel") ?? NotificationChannel.off.rawValue {
        didSet { UserDefaults.standard.set(suggestionNotificationChannel, forKey: "suggestionNotificationChannel") }
    }

    /// Skip Telegram delivery when app is active/foreground
    var telegramSkipWhenAppActive: Bool =
        UserDefaults.standard.object(forKey: "telegramSkipWhenAppActive") as? Bool ?? true {
        didSet { UserDefaults.standard.set(telegramSkipWhenAppActive, forKey: "telegramSkipWhenAppActive") }
    }

    // MARK: - Guide (UX-9) / App Guide (K-5)

    /// AI 앱 가이드 도구 활성화 여부
    var appGuideEnabled: Bool = UserDefaults.standard.object(forKey: "appGuideEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(appGuideEnabled, forKey: "appGuideEnabled") }
    }

    /// 인앱 힌트 표시 여부 (hintsGloballyDisabled의 반전)
    var hintsEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "hintsGloballyDisabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "hintsGloballyDisabled") }
    }

    /// 기능 투어 완료 여부
    var featureTourCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "featureTourCompleted") }
        set { UserDefaults.standard.set(newValue, forKey: "featureTourCompleted") }
    }

    /// 기능 투어 건너뛰기 여부
    var featureTourSkipped: Bool {
        get { UserDefaults.standard.bool(forKey: "featureTourSkipped") }
        set { UserDefaults.standard.set(newValue, forKey: "featureTourSkipped") }
    }

    /// 기능 투어 재안내 배너 닫음 여부
    var featureTourBannerDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: "featureTourBannerDismissed") }
        set { UserDefaults.standard.set(newValue, forKey: "featureTourBannerDismissed") }
    }

    /// 모든 힌트 표시 상태를 초기화
    func resetAllHints() {
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("hint_seen_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set(false, forKey: "hintsGloballyDisabled")
    }

    /// 기능 투어 상태를 초기화
    func resetFeatureTour() {
        UserDefaults.standard.set(false, forKey: "featureTourCompleted")
        UserDefaults.standard.set(false, forKey: "featureTourSkipped")
        UserDefaults.standard.set(false, forKey: "featureTourBannerDismissed")
    }
}
