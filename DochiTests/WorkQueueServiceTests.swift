import XCTest
@testable import Dochi

@MainActor
final class WorkQueueServiceTests: XCTestCase {
    private func makeTempDirectory(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDraft(
        dedupeKey: String,
        severity: WorkItemSeverity = .info,
        repositoryRoot: String? = "/tmp/repo-a"
    ) -> WorkItemDraft {
        WorkItemDraft(
            source: .heartbeat,
            title: "work item",
            detail: "detail",
            repositoryRoot: repositoryRoot,
            severity: severity,
            suggestedAction: "bridge.orchestrator.status",
            dedupeKey: dedupeKey
        )
    }

    func testEnqueueDedupesWithinCooldownWindow() throws {
        let baseURL = try makeTempDirectory(prefix: "dochi-workqueue-dedupe")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let service = WorkQueueService(baseURL: baseURL, dedupeCooldown: 300)

        let first = service.enqueue(makeDraft(dedupeKey: "same-key"), now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNotNil(first)

        let duplicate = service.enqueue(makeDraft(dedupeKey: "same-key"), now: Date(timeIntervalSince1970: 1_700_000_120))
        XCTAssertNil(duplicate)
        XCTAssertEqual(service.items.count, 1)

        let afterCooldown = service.enqueue(makeDraft(dedupeKey: "same-key"), now: Date(timeIntervalSince1970: 1_700_000_301))
        XCTAssertNotNil(afterCooldown)
        XCTAssertEqual(service.items.count, 2)
    }

    func testTransitionItemAppliesValidStateChangesOnly() throws {
        let baseURL = try makeTempDirectory(prefix: "dochi-workqueue-transition")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let service = WorkQueueService(baseURL: baseURL, dedupeCooldown: 60)

        let queued = try XCTUnwrap(service.enqueue(makeDraft(dedupeKey: "transition-key"), now: Date(timeIntervalSince1970: 1_700_000_000)))
        let notified = service.transitionItem(
            id: queued.id,
            to: .notified,
            now: Date(timeIntervalSince1970: 1_700_000_010)
        )
        XCTAssertEqual(notified?.status, .notified)

        let accepted = service.transitionItem(
            id: queued.id,
            to: .accepted,
            now: Date(timeIntervalSince1970: 1_700_000_020)
        )
        XCTAssertEqual(accepted?.status, .accepted)

        let invalid = service.transitionItem(
            id: queued.id,
            to: .queued,
            now: Date(timeIntervalSince1970: 1_700_000_030)
        )
        XCTAssertNil(invalid)
        XCTAssertEqual(service.items.first?.status, .accepted)
    }

    func testPruneExpiredMarksItemsExpiredAndRecentSortingPrioritizesSeverity() throws {
        let baseURL = try makeTempDirectory(prefix: "dochi-workqueue-expire")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let service = WorkQueueService(baseURL: baseURL, dedupeCooldown: 60)
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        _ = service.enqueue(
            WorkItemDraft(
                source: .heartbeat,
                title: "old warning",
                detail: "detail",
                repositoryRoot: "/tmp/repo-a",
                severity: .warning,
                suggestedAction: "bridge.orchestrator.status",
                dedupeKey: "expire-key",
                ttl: 30
            ),
            now: baseTime
        )
        _ = service.enqueue(
            WorkItemDraft(
                source: .heartbeat,
                title: "new critical",
                detail: "detail",
                repositoryRoot: "/tmp/repo-b",
                severity: .critical,
                suggestedAction: "bridge.orchestrator.status",
                dedupeKey: "critical-key"
            ),
            now: baseTime.addingTimeInterval(10)
        )

        service.pruneExpiredItems(now: baseTime.addingTimeInterval(31))
        let expired = service.items.first(where: { $0.dedupeKey == "expire-key" })
        XCTAssertEqual(expired?.status, .expired)

        let recent = service.recentItems(limit: 10, status: nil, now: baseTime.addingTimeInterval(31))
        XCTAssertEqual(recent.first?.dedupeKey, "critical-key")
    }
}
