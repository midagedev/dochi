import Foundation

/// Maps channel-specific identifiers to internal conversation IDs.
///
/// Each channel (voice, text, messenger) has its own way of identifying
/// a conversation. This mapper provides a unified interface for resolving
/// any channel input to a Dochi `conversationId`.
///
/// - `voice` / `text`: The conversationId is used directly (1:1 mapping).
/// - `messenger`: An external chat ID (e.g. Telegram chatId) is mapped to
///   an internal conversationId via a lookup table.
///
/// Messenger mappings are persisted to `channel_mappings.json` under the
/// app's data directory so they survive app restarts.
@MainActor
final class ChannelSessionMapper {

    // MARK: - Persistence

    private let fileURL: URL?

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    // MARK: - Messenger Mapping Table

    /// Maps external messenger chat IDs to internal conversation IDs.
    /// Key: external chat identifier (e.g. "\(chatId)"), Value: conversationId
    private var messengerMappings: [String: String] = [:]

    // MARK: - Init

    /// Create a mapper with optional file-based persistence.
    ///
    /// - Parameter baseURL: Directory for `channel_mappings.json`.
    ///   If `nil`, uses `~/Library/Application Support/Dochi/`.
    ///   Pass an explicit temp directory in tests.
    init(baseURL: URL? = nil) {
        let base = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("Dochi")
        self.fileURL = base?.appendingPathComponent("channel_mappings.json")
        load()
    }

    /// Create a mapper without persistence (in-memory only, for lightweight tests).
    init(inMemory: Bool) {
        self.fileURL = nil
    }

    // MARK: - Resolve

    /// Resolve a channel-specific identifier to an internal conversationId.
    ///
    /// - Parameters:
    ///   - channel: The source channel.
    ///   - identifier: The channel-native identifier.
    ///     - For `voice`/`text`: this is the Dochi conversationId (UUID string).
    ///     - For `messenger`: this is the external chat ID (e.g. Telegram chatId).
    /// - Returns: The resolved internal conversationId, or `nil` if the mapping
    ///   does not exist (messenger only; voice/text always return the input).
    func resolveConversationId(channel: SessionChannel, identifier: String) -> String? {
        switch channel {
        case .voice, .text:
            // Local channels use the Dochi conversationId directly.
            return identifier
        case .messenger:
            return messengerMappings[identifier]
        }
    }

    // MARK: - Messenger Mapping CRUD

    /// Register a mapping from an external messenger chat ID to an internal conversationId.
    func registerMessengerMapping(externalChatId: String, conversationId: String) {
        messengerMappings[externalChatId] = conversationId
        save()
        Log.app.debug("ChannelSessionMapper: registered messenger mapping \(externalChatId) -> \(conversationId)")
    }

    /// Remove a messenger mapping by external chat ID.
    func removeMessengerMapping(externalChatId: String) {
        messengerMappings.removeValue(forKey: externalChatId)
        save()
    }

    /// Look up the internal conversationId for a messenger chat ID.
    func messengerConversationId(for externalChatId: String) -> String? {
        messengerMappings[externalChatId]
    }

    /// Return all current messenger mappings (for diagnostics).
    var allMessengerMappings: [String: String] {
        messengerMappings
    }

    // MARK: - Persistence (Private)

    private func load() {
        guard let url = fileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            messengerMappings = try Self.decoder.decode([String: String].self, from: data)
            Log.app.info("ChannelSessionMapper: loaded \(self.messengerMappings.count) messenger mapping(s)")
        } catch {
            Log.app.error("ChannelSessionMapper: failed to load mappings — \(error.localizedDescription)")
            messengerMappings = [:]
        }
    }

    private func save() {
        guard let url = fileURL else { return }

        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(messengerMappings)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.app.error("ChannelSessionMapper: failed to save mappings — \(error.localizedDescription)")
        }
    }
}
