import Foundation

enum NativeSessionStatus: String, Codable, Sendable {
    case active
    case interrupted
}

struct NativeSessionRecord: Codable, Sendable, Equatable {
    let resumeKey: String
    let workspaceId: String
    let agentId: String
    let conversationId: String
    var userId: String?
    var status: NativeSessionStatus
    let createdAt: Date
    var updatedAt: Date
}

private struct NativeSessionStoreData: Codable, Sendable {
    var records: [NativeSessionRecord]
    var version: Int

    init(records: [NativeSessionRecord] = [], version: Int = 1) {
        self.records = records
        self.version = version
    }
}

@MainActor
final class NativeSessionStore {
    private let fileURL: URL
    private var store: NativeSessionStoreData
    private var resumeKeyIndex: [String: Int] = [:]

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    private static let legacyDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(baseURL: URL? = nil) {
        let base = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Dochi")
        self.fileURL = base.appendingPathComponent("native_sessions.json")
        self.store = NativeSessionStoreData()
        load()
    }

    static func makeResumeKey(
        workspaceId: UUID,
        agentId: String,
        conversationId: UUID
    ) -> String {
        makeResumeKey(
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId.uuidString
        )
    }

    static func makeResumeKey(
        workspaceId: String,
        agentId: String,
        conversationId: String
    ) -> String {
        "\(workspaceId):\(agentId):\(conversationId)"
    }

    @discardableResult
    func activate(
        workspaceId: UUID,
        agentId: String,
        conversationId: UUID,
        userId: String? = nil
    ) -> NativeSessionRecord {
        upsert(
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId.uuidString,
            userId: userId,
            status: .active
        )
    }

    @discardableResult
    func interrupt(
        workspaceId: UUID,
        agentId: String,
        conversationId: UUID,
        userId: String? = nil
    ) -> NativeSessionRecord {
        upsert(
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId.uuidString,
            userId: userId,
            status: .interrupted
        )
    }

    @discardableResult
    func recoverIfInterrupted(
        workspaceId: UUID,
        agentId: String,
        conversationId: UUID,
        userId: String? = nil
    ) -> NativeSessionRecord? {
        let resumeKey = Self.makeResumeKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId
        )
        guard let existing = record(forResumeKey: resumeKey),
              existing.status == .interrupted else {
            return nil
        }
        return activate(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: userId
        )
    }

    func record(
        workspaceId: UUID,
        agentId: String,
        conversationId: UUID
    ) -> NativeSessionRecord? {
        record(forResumeKey: Self.makeResumeKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId
        ))
    }

    func latestRecords(
        workspaceId: UUID,
        agentId: String,
        userId: String? = nil,
        statuses: Set<NativeSessionStatus> = [.active, .interrupted]
    ) -> [NativeSessionRecord] {
        guard let normalizedUserId = Self.normalizeUserId(userId) else {
            return []
        }

        return store.records
            .reversed()
            .filter { record in
                guard record.workspaceId == workspaceId.uuidString,
                      record.agentId == agentId,
                      statuses.contains(record.status) else {
                    return false
                }

                guard let recordUserId = Self.normalizeUserId(record.userId) else {
                    // Backward-compat: include legacy records without user id and
                    // rely on conversation user ownership checks during restore.
                    return true
                }
                return recordUserId == normalizedUserId
            }
    }

    func remove(
        workspaceId: UUID,
        agentId: String,
        conversationId: UUID
    ) {
        let resumeKey = Self.makeResumeKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId
        )
        guard let index = resumeKeyIndex[resumeKey] else { return }
        store.records.remove(at: index)
        rebuildIndex()
        save()
    }

    var allRecords: [NativeSessionRecord] {
        store.records
    }

    private func record(forResumeKey resumeKey: String) -> NativeSessionRecord? {
        guard let index = resumeKeyIndex[resumeKey],
              index < store.records.count else {
            return nil
        }
        return store.records[index]
    }

    @discardableResult
    private func upsert(
        workspaceId: String,
        agentId: String,
        conversationId: String,
        userId: String?,
        status: NativeSessionStatus
    ) -> NativeSessionRecord {
        let resumeKey = Self.makeResumeKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId
        )
        let now = Date()
        let normalizedIncomingUserId = Self.normalizeUserId(userId)

        if let index = resumeKeyIndex[resumeKey], index < store.records.count {
            var existing = store.records.remove(at: index)
            existing.status = status

            if let existingUserId = Self.normalizeUserId(existing.userId) {
                existing.userId = existingUserId
            } else {
                existing.userId = normalizedIncomingUserId
            }

            existing.updatedAt = now
            store.records.append(existing)
            rebuildIndex()
            save()
            return existing
        }

        let record = NativeSessionRecord(
            resumeKey: resumeKey,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: normalizedIncomingUserId,
            status: status,
            createdAt: now,
            updatedAt: now
        )
        store.records.append(record)
        rebuildIndex()
        save()
        return record
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            store = NativeSessionStoreData()
            rebuildIndex()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let decoded = try? Self.decoder.decode(NativeSessionStoreData.self, from: data) {
                store = decoded
            } else if let legacyDecoded = try? Self.legacyDecoder.decode(NativeSessionStoreData.self, from: data) {
                store = legacyDecoded
                store.records = Self.normalizedLegacyRecordOrder(store.records)
                save()
            } else {
                throw NSError(
                    domain: "NativeSessionStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported native session store format"]
                )
            }
        } catch {
            Log.runtime.error("Failed to load native session store: \(error.localizedDescription)")
            store = NativeSessionStoreData()
        }
        rebuildIndex()
    }

    private func save() {
        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try Self.encoder.encode(store)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.runtime.error("Failed to save native session store: \(error.localizedDescription)")
        }
    }

    private func rebuildIndex() {
        resumeKeyIndex.removeAll()
        for (index, record) in store.records.enumerated() {
            resumeKeyIndex[record.resumeKey] = index
        }
    }

    private static func normalizeUserId(_ userId: String?) -> String? {
        guard let trimmed = userId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedLegacyRecordOrder(_ records: [NativeSessionRecord]) -> [NativeSessionRecord] {
        records
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.updatedAt != rhs.element.updatedAt {
                    return lhs.element.updatedAt < rhs.element.updatedAt
                }
                if lhs.element.createdAt != rhs.element.createdAt {
                    return lhs.element.createdAt < rhs.element.createdAt
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
