import XCTest
@testable import Dochi

final class ControlPlaneStreamRegistryTests: XCTestCase {
    func testChatSessionReadAdvancesCursorAndDoneState() async {
        let registry = ControlPlaneStreamRegistry()
        let streamId = await registry.createChatSession(correlationId: "cid-1")

        await registry.appendChatEvent(
            streamId: streamId,
            type: "partial",
            timestamp: "2026-02-18T00:00:00.000Z",
            text: "hello"
        )
        await registry.appendChatEvent(
            streamId: streamId,
            type: "done",
            timestamp: "2026-02-18T00:00:01.000Z",
            text: "hello world"
        )
        await registry.finishChat(streamId: streamId, errorMessage: nil)

        let first = await registry.readChat(streamId: streamId, limit: 1)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.events.count, 1)
        XCTAssertFalse(first?.done ?? true)

        let second = await registry.readChat(streamId: streamId, limit: 10)
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.events.count, 1)
        XCTAssertTrue(second?.done ?? false)
    }

    func testCloseChatSessionRemovesSession() async {
        let registry = ControlPlaneStreamRegistry()
        let streamId = await registry.createChatSession(correlationId: "cid-close")

        let closed = await registry.closeChat(streamId: streamId)
        XCTAssertTrue(closed)

        let snapshot = await registry.readChat(streamId: streamId, limit: 10)
        XCTAssertNil(snapshot)
    }

    func testLogTailConsumesOnlyEntriesAfterCursor() async {
        let registry = ControlPlaneStreamRegistry()
        let now = Date()
        let tailId = await registry.createLogTailSession(
            correlationId: "cid-log",
            category: nil,
            level: nil,
            contains: nil,
            startAt: now
        )

        let oldEntry = DochiLogLine(date: now.addingTimeInterval(-2), category: "Tool", level: "info", message: "old")
        let newEntry = DochiLogLine(date: now.addingTimeInterval(1), category: "Tool", level: "info", message: "new")

        let first = await registry.consumeLogTailEntries(tailId: tailId, entries: [oldEntry, newEntry], limit: 10)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.events.count, 1)
        XCTAssertEqual(first?.events.first?.message, "new")

        let second = await registry.consumeLogTailEntries(tailId: tailId, entries: [oldEntry, newEntry], limit: 10)
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.events.count, 0)
    }
}
