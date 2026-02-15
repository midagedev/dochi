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

    var ragEmbeddingProvider: String = UserDefaults.standard.string(forKey: "ragEmbeddingProvider") ?? "openai" {
        didSet { UserDefaults.standard.set(ragEmbeddingProvider, forKey: "ragEmbeddingProvider") }
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

    // MARK: - Guide (UX-9)

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
