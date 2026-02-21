import Foundation
import os

@MainActor
@Observable
final class HeartbeatChangeJournalService: HeartbeatChangeJournalProtocol {
    private struct ChangeJournalFile: Codable {
        let entries: [ChangeJournalEntry]
    }

    private let baseURL: URL
    private let maxEntries: Int

    private(set) var entries: [ChangeJournalEntry] = []

    init(baseURL: URL? = nil, maxEntries: Int = 300) {
        let appSupport = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Dochi")
        self.baseURL = appSupport
        self.maxEntries = max(1, maxEntries)
        loadFromDisk()
    }

    func append(events: [HeartbeatChangeEvent]) {
        guard !events.isEmpty else { return }

        let additions = events.map { ChangeJournalEntry(event: $0) }
        entries.append(contentsOf: additions)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        saveToDisk()
    }

    func recentEntries(limit: Int, source: HeartbeatChangeSource? = nil) -> [ChangeJournalEntry] {
        guard limit > 0 else { return [] }
        let filtered: [ChangeJournalEntry]
        if let source {
            filtered = entries.filter { $0.event.source == source }
        } else {
            filtered = entries
        }
        return Array(filtered.suffix(limit).reversed())
    }

    // MARK: - Persistence

    private var filePath: URL {
        baseURL.appendingPathComponent("heartbeat_change_journal.json")
    }

    private func loadFromDisk() {
        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(ChangeJournalFile.self, from: data)
            entries = Array(file.entries.suffix(maxEntries))
            Log.storage.debug("Loaded \(self.entries.count) heartbeat change journal entries")
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                Log.storage.debug("No heartbeat change journal file found, starting fresh")
            } else {
                Log.storage.warning("Failed to load heartbeat change journal: \(error.localizedDescription)")
            }
        }
    }

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let payload = ChangeJournalFile(entries: entries)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: filePath, options: .atomic)
        } catch {
            Log.storage.error("Failed to save heartbeat change journal: \(error.localizedDescription)")
        }
    }
}
