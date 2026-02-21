import Foundation

@MainActor
protocol HeartbeatChangeJournalProtocol: AnyObject, Sendable {
    var entries: [ChangeJournalEntry] { get }
    func append(events: [HeartbeatChangeEvent])
    func recentEntries(limit: Int, source: HeartbeatChangeSource?) -> [ChangeJournalEntry]
}

extension HeartbeatChangeJournalProtocol {
    func recentEntries(limit: Int) -> [ChangeJournalEntry] {
        recentEntries(limit: limit, source: nil)
    }
}
