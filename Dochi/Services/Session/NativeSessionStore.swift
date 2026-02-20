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
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
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
        store.records
            .filter { record in
                guard record.workspaceId == workspaceId.uuidString,
                      record.agentId == agentId,
                      statuses.contains(record.status) else {
                    return false
                }

                guard let userId, !userId.isEmpty else { return true }
                return record.userId == nil || record.userId == userId
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
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

        if let index = resumeKeyIndex[resumeKey], index < store.records.count {
            store.records[index].status = status
            store.records[index].userId = userId
            store.records[index].updatedAt = now
            save()
            return store.records[index]
        }

        let record = NativeSessionRecord(
            resumeKey: resumeKey,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: userId,
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
            store = try Self.decoder.decode(NativeSessionStoreData.self, from: data)
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
}
