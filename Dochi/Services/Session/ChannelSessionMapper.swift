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
@MainActor
final class ChannelSessionMapper {

    // MARK: - Messenger Mapping Table

    /// Maps external messenger chat IDs to internal conversation IDs.
    /// Key: external chat identifier (e.g. "\(chatId)"), Value: conversationId
    private var messengerMappings: [String: String] = [:]

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
        Log.app.debug("ChannelSessionMapper: registered messenger mapping \(externalChatId) -> \(conversationId)")
    }

    /// Remove a messenger mapping by external chat ID.
    func removeMessengerMapping(externalChatId: String) {
        messengerMappings.removeValue(forKey: externalChatId)
    }

    /// Look up the internal conversationId for a messenger chat ID.
    func messengerConversationId(for externalChatId: String) -> String? {
        messengerMappings[externalChatId]
    }

    /// Return all current messenger mappings (for diagnostics).
    var allMessengerMappings: [String: String] {
        messengerMappings
    }
}
