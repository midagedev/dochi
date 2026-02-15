import Foundation

// MARK: - ShortcutExecutionLog

/// Shortcut 실행 기록 모델
struct ShortcutExecutionLog: Codable, Identifiable, Sendable {
    let id: UUID
    let actionName: String
    let timestamp: Date
    let success: Bool
    let resultSummary: String
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        actionName: String,
        timestamp: Date = Date(),
        success: Bool,
        resultSummary: String,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.actionName = actionName
        self.timestamp = timestamp
        self.success = success
        self.resultSummary = resultSummary
        self.errorMessage = errorMessage
    }
}

// MARK: - ShortcutExecutionLogStore

/// Shortcut 실행 기록 파일 저장소 (FIFO, 최대 50건)
@MainActor
final class ShortcutExecutionLogStore {
    static let maxLogs = 50

    private let fileURL: URL

    init(baseURL: URL? = nil) {
        let base = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        self.fileURL = base.appendingPathComponent("shortcut_logs.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func loadLogs() -> [ShortcutExecutionLog] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ShortcutExecutionLog].self, from: data)) ?? []
    }

    func saveLogs(_ logs: [ShortcutExecutionLog]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(logs)
            try data.write(to: fileURL)
        } catch {
            Log.app.error("Failed to save shortcut execution logs: \(error.localizedDescription)")
        }
    }

    func appendLog(_ log: ShortcutExecutionLog) {
        var logs = loadLogs()
        logs.insert(log, at: 0)
        if logs.count > Self.maxLogs {
            logs = Array(logs.prefix(Self.maxLogs))
        }
        saveLogs(logs)
    }
}
