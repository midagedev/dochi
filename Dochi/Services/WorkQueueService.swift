import Foundation
import os

@MainActor
@Observable
final class WorkQueueService: WorkQueueServiceProtocol {
    private struct WorkQueueFile: Codable {
        let items: [WorkItem]
    }

    private let baseURL: URL
    private let maxItems: Int
    private let dedupeCooldown: TimeInterval

    private(set) var items: [WorkItem] = []

    init(
        baseURL: URL? = nil,
        maxItems: Int = 500,
        dedupeCooldown: TimeInterval = 5 * 60
    ) {
        let appSupport = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Dochi")
        self.baseURL = appSupport
        self.maxItems = max(1, maxItems)
        self.dedupeCooldown = max(1, dedupeCooldown)
        loadFromDisk()
        pruneExpiredItems(now: Date())
    }

    @discardableResult
    func enqueue(_ draft: WorkItemDraft, now: Date) -> WorkItem? {
        let dedupeKey = draft.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dedupeKey.isEmpty else {
            Log.storage.warning("WorkQueue enqueue skipped due to empty dedupe key")
            return nil
        }

        if let duplicate = items.first(where: {
            $0.dedupeKey == dedupeKey
                && now.timeIntervalSince($0.createdAt) < dedupeCooldown
                && $0.status != .expired
        }) {
            Log.storage.debug("WorkQueue dedupe skip: \(duplicate.dedupeKey)")
            return nil
        }

        let repositoryRoot = draft.repositoryRoot?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAt = draft.ttl.flatMap { ttl in
            ttl > 0 ? now.addingTimeInterval(ttl) : nil
        }
        let item = WorkItem(
            source: draft.source,
            title: draft.title,
            detail: draft.detail,
            repositoryRoot: repositoryRoot?.isEmpty == true ? nil : repositoryRoot,
            severity: draft.severity,
            suggestedAction: draft.suggestedAction,
            dedupeKey: dedupeKey,
            status: .queued,
            createdAt: now,
            dueAt: draft.dueAt,
            expiresAt: expiresAt,
            updatedAt: now
        )

        items.append(item)
        trimToMaxItems()
        saveToDisk()
        return item
    }

    @discardableResult
    func transitionItem(id: UUID, to status: WorkItemStatus, now: Date) -> WorkItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let current = items[index]

        guard current.status.canTransition(to: status) else {
            Log.storage.warning("WorkQueue invalid transition: \(current.status.rawValue) -> \(status.rawValue)")
            return nil
        }

        if current.status == status {
            return current
        }

        var updated = current
        updated.status = status
        updated.updatedAt = now
        items[index] = updated
        saveToDisk()
        return updated
    }

    func recentItems(limit: Int, status: WorkItemStatus?, now: Date) -> [WorkItem] {
        guard limit > 0 else { return [] }
        pruneExpiredItems(now: now)

        let filtered = status.map { status in
            items.filter { $0.status == status }
        } ?? items
        return Array(filtered.sorted(by: Self.sortItems).prefix(limit))
    }

    func pruneExpiredItems(now: Date) {
        var didMutate = false
        for index in items.indices {
            guard items[index].status != .expired,
                  items[index].status != .dismissed,
                  let expiresAt = items[index].expiresAt,
                  expiresAt <= now else {
                continue
            }
            items[index].status = .expired
            items[index].updatedAt = now
            didMutate = true
        }

        if didMutate {
            saveToDisk()
        }
    }

    // MARK: - Persistence

    private var filePath: URL {
        baseURL.appendingPathComponent("work_queue.json")
    }

    private func loadFromDisk() {
        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(WorkQueueFile.self, from: data)
            items = file.items
            trimToMaxItems()
            Log.storage.debug("Loaded \(self.items.count) work queue item(s)")
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                Log.storage.debug("No work queue file found, starting fresh")
            } else {
                Log.storage.warning("Failed to load work queue: \(error.localizedDescription)")
            }
        }
    }

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let payload = WorkQueueFile(items: items)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: filePath, options: .atomic)
        } catch {
            Log.storage.error("Failed to save work queue: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func trimToMaxItems() {
        guard items.count > maxItems else { return }
        items = Array(items.sorted { $0.updatedAt < $1.updatedAt }.suffix(maxItems))
    }

    private static func sortItems(lhs: WorkItem, rhs: WorkItem) -> Bool {
        if lhs.status != rhs.status {
            return statusSortOrder(lhs.status) < statusSortOrder(rhs.status)
        }
        if lhs.severity.priority != rhs.severity.priority {
            return lhs.severity.priority > rhs.severity.priority
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func statusSortOrder(_ status: WorkItemStatus) -> Int {
        switch status {
        case .queued:
            return 0
        case .notified:
            return 1
        case .deferred:
            return 2
        case .accepted:
            return 3
        case .dismissed:
            return 4
        case .expired:
            return 5
        }
    }
}
