import XCTest
@testable import Dochi

@MainActor
final class HeartbeatChangeJournalServiceTests: XCTestCase {
    private func makeEvent(
        source: HeartbeatChangeSource = .git,
        eventType: HeartbeatChangeEventType = .gitBranchChanged,
        targetId: String
    ) -> HeartbeatChangeEvent {
        HeartbeatChangeEvent(
            source: source,
            eventType: eventType,
            severity: .info,
            targetId: targetId,
            title: "test",
            detail: "test detail",
            metadata: [:],
            timestamp: Date()
        )
    }

    func testAppendPersistsAndLoadsEntries() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-change-journal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let writer = HeartbeatChangeJournalService(baseURL: tempRoot, maxEntries: 10)
        writer.append(events: [makeEvent(targetId: "repo-a")])
        XCTAssertEqual(writer.entries.count, 1)

        let reader = HeartbeatChangeJournalService(baseURL: tempRoot, maxEntries: 10)
        XCTAssertEqual(reader.entries.count, 1)
        XCTAssertEqual(reader.entries.first?.event.targetId, "repo-a")
    }

    func testHistoryCapKeepsMostRecentEntries() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-change-journal-cap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = HeartbeatChangeJournalService(baseURL: tempRoot, maxEntries: 3)
        service.append(events: [
            makeEvent(targetId: "1"),
            makeEvent(targetId: "2"),
            makeEvent(targetId: "3"),
            makeEvent(targetId: "4"),
            makeEvent(targetId: "5"),
        ])

        XCTAssertEqual(service.entries.count, 3)
        XCTAssertEqual(service.entries.map(\.event.targetId), ["3", "4", "5"])
    }

    func testRecentEntriesSupportsSourceFilter() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-change-journal-filter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = HeartbeatChangeJournalService(baseURL: tempRoot, maxEntries: 10)
        service.append(events: [
            makeEvent(source: .git, eventType: .gitBranchChanged, targetId: "repo-a"),
            makeEvent(source: .codingSession, eventType: .codingSessionStarted, targetId: "session-a"),
            makeEvent(source: .codingSession, eventType: .codingSessionEnded, targetId: "session-b"),
        ])

        let codingRecent = service.recentEntries(limit: 5, source: .codingSession)
        XCTAssertEqual(codingRecent.count, 2)
        XCTAssertTrue(codingRecent.allSatisfy { $0.event.source == .codingSession })
        XCTAssertEqual(codingRecent.first?.event.targetId, "session-b")
    }
}
