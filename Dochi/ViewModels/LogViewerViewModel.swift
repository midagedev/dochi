import Foundation
import OSLog
import AppKit

struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let category: String
    let level: OSLogEntryLog.Level
    let composedMessage: String

    var levelLabel: String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "undefined"
        }
    }
}

@MainActor
@Observable
final class LogViewerViewModel {
    var entries: [LogEntry] = []
    var selectedCategory: String?
    var selectedLevel: OSLogEntryLog.Level?
    var searchText: String = ""
    var isAutoRefresh: Bool = false {
        didSet {
            if isAutoRefresh {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
    }
    var lastRefreshDate: Date?

    private var refreshTask: Task<Void, Never>?

    var filteredEntries: [LogEntry] {
        entries.filter { entry in
            if let cat = selectedCategory, entry.category != cat {
                return false
            }
            if let lvl = selectedLevel, entry.level != lvl {
                return false
            }
            if !searchText.isEmpty,
               !entry.composedMessage.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            return true
        }
    }

    func fetchLogs() {
        Task {
            let fetched = await Self.queryLogStore()
            self.entries = fetched
            self.lastRefreshDate = Date()
        }
    }

    private static func queryLogStore() async -> [LogEntry] {
        await Task.detached {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let since = store.position(date: Date().addingTimeInterval(-3600))
                let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
                let rawEntries = try store.getEntries(at: since, matching: predicate)

                var result: [LogEntry] = []
                for entry in rawEntries {
                    guard let logEntry = entry as? OSLogEntryLog else { continue }
                    result.append(LogEntry(
                        id: UUID(),
                        date: logEntry.date,
                        category: logEntry.category,
                        level: logEntry.level,
                        composedMessage: logEntry.composedMessage
                    ))
                    if result.count >= 5000 { break }
                }
                return result
            } catch {
                Log.app.error("Failed to query OSLogStore: \(error.localizedDescription)")
                return []
            }
        }.value
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                let fetched = await Self.queryLogStore()
                self.entries = fetched
                self.lastRefreshDate = Date()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func copyEntries() {
        let text = filteredEntries.map { entry in
            let ts = Self.timeFormatter.string(from: entry.date)
            return "\(ts) | \(entry.category) | \(entry.levelLabel) | \(entry.composedMessage)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clearEntries() {
        entries = []
        lastRefreshDate = nil
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
