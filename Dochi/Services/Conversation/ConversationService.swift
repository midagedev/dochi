import Foundation
import os

@MainActor
final class ConversationService: ConversationServiceProtocol {
    private let baseURL: URL

    init() {
        self.baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi/conversations")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func list() -> [Conversation] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: baseURL.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { load(id: UUID(uuidString: String($0.dropLast(5))) ?? UUID()) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func load(id: UUID) -> Conversation? {
        let url = baseURL.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Conversation.self, from: data)
        } catch {
            Log.storage.error("Failed to load conversation \(id): \(error.localizedDescription)")
            return nil
        }
    }

    func save(conversation: Conversation) {
        let url = baseURL.appendingPathComponent("\(conversation.id.uuidString).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(conversation)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.storage.error("Failed to save conversation: \(error.localizedDescription)")
        }
    }

    func delete(id: UUID) {
        let url = baseURL.appendingPathComponent("\(id.uuidString).json")
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.storage.error("Failed to delete conversation \(id): \(error.localizedDescription)")
        }
    }
}
