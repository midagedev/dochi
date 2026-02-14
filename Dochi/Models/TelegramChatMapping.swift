import Foundation

/// Maps a Telegram chat ID to a workspace and stores metadata.
struct TelegramChatMapping: Codable, Identifiable, Sendable {
    var id: Int64 { chatId }
    let chatId: Int64
    var workspaceId: UUID?
    var label: String   // Display name (username or chat title)
    var enabled: Bool

    init(chatId: Int64, workspaceId: UUID? = nil, label: String = "", enabled: Bool = true) {
        self.chatId = chatId
        self.workspaceId = workspaceId
        self.label = label
        self.enabled = enabled
    }
}

/// Manages Telegram chat ↔ workspace mappings persisted in AppSettings.
@MainActor
struct TelegramChatMappingStore {

    static func loadMappings(from settings: AppSettings) -> [TelegramChatMapping] {
        guard let data = settings.telegramChatMappingJSON.data(using: .utf8),
              let mappings = try? JSONDecoder().decode([TelegramChatMapping].self, from: data) else {
            return []
        }
        return mappings
    }

    static func saveMappings(_ mappings: [TelegramChatMapping], to settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(mappings),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        settings.telegramChatMappingJSON = json
    }

    /// Add or update a mapping for a given chat ID.
    static func upsert(chatId: Int64, label: String, workspaceId: UUID?, in settings: AppSettings) {
        var mappings = loadMappings(from: settings)
        if let idx = mappings.firstIndex(where: { $0.chatId == chatId }) {
            mappings[idx].label = label
            mappings[idx].workspaceId = workspaceId
        } else {
            mappings.append(TelegramChatMapping(chatId: chatId, workspaceId: workspaceId, label: label))
        }
        saveMappings(mappings, to: settings)
    }

    /// Remove a mapping by chat ID.
    static func remove(chatId: Int64, from settings: AppSettings) {
        var mappings = loadMappings(from: settings)
        mappings.removeAll { $0.chatId == chatId }
        saveMappings(mappings, to: settings)
    }
}
