import XCTest
@testable import Dochi

// MARK: - Mock Handler

@MainActor
final class MockPeerMessageHandler: PeerMessageHandler {
    var handledMessages: [PeerMessage] = []
    var shouldSucceed = true

    func handle(message: PeerMessage) async -> Bool {
        handledMessages.append(message)
        return shouldSucceed
    }
}

// MARK: - Tests

@MainActor
final class PeerMessageTests: XCTestCase {
    private let deviceA = UUID()
    private let deviceB = UUID()
    private let workspace = UUID()
    private var router: PeerMessageRouter!

    override func setUp() {
        super.setUp()
        router = PeerMessageRouter(localDeviceId: deviceA, workspaceId: workspace)
    }

    // MARK: - PeerMessageType

    func testMessageTypeDisplayNames() {
        XCTAssertEqual(PeerMessageType.text.displayName, "텍스트")
        XCTAssertEqual(PeerMessageType.ttsRequest.displayName, "TTS 요청")
        XCTAssertEqual(PeerMessageType.command.displayName, "명령")
        XCTAssertEqual(PeerMessageType.notification.displayName, "알림")
        XCTAssertEqual(PeerMessageType.taskResult.displayName, "태스크 결과")
    }

    func testMessageTypeCodable() throws {
        for type in PeerMessageType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(PeerMessageType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    // MARK: - PeerMessage Model

    func testMessageInitDefaults() {
        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceA,
            receiverDeviceId: deviceB,
            type: .text
        )
        XCTAssertEqual(msg.workspaceId, workspace)
        XCTAssertEqual(msg.senderDeviceId, deviceA)
        XCTAssertEqual(msg.receiverDeviceId, deviceB)
        XCTAssertEqual(msg.type, .text)
        XCTAssertEqual(msg.status, .queued)
        XCTAssertNil(msg.deliveredAt)
        XCTAssertNil(msg.processedAt)
        XCTAssertNil(msg.errorMessage)
    }

    func testMessagePayloadParsing() {
        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceA,
            receiverDeviceId: deviceB,
            type: .text,
            payloadJSON: "{\"text\":\"hello\",\"lang\":\"ko\"}"
        )
        XCTAssertEqual(msg.payload["text"] as? String, "hello")
        XCTAssertEqual(msg.payload["lang"] as? String, "ko")
    }

    func testMessagePayloadInvalidJSON() {
        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceA,
            receiverDeviceId: deviceB,
            type: .text,
            payloadJSON: "invalid"
        )
        XCTAssertTrue(msg.payload.isEmpty)
    }

    func testMessageIsExpired() {
        let expired = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceA,
            receiverDeviceId: deviceB,
            type: .text,
            expiresAt: Date().addingTimeInterval(-60)
        )
        XCTAssertTrue(expired.isExpired)

        let notExpired = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceA,
            receiverDeviceId: deviceB,
            type: .text,
            expiresAt: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(notExpired.isExpired)
    }

    func testMessageIsExpiredNoDeadline() {
        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceA,
            receiverDeviceId: deviceB,
            type: .text
        )
        XCTAssertFalse(msg.isExpired)
    }

    func testMessageCodableRoundtrip() throws {
        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceA,
            receiverDeviceId: deviceB,
            type: .ttsRequest,
            payloadJSON: "{\"text\":\"안녕\"}",
            expiresAt: Date().addingTimeInterval(3600)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(msg)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PeerMessage.self, from: data)

        XCTAssertEqual(decoded.id, msg.id)
        XCTAssertEqual(decoded.workspaceId, workspace)
        XCTAssertEqual(decoded.type, .ttsRequest)
        XCTAssertEqual(decoded.status, .queued)
        XCTAssertNotNil(decoded.expiresAt)
    }

    func testMessageCodingKeysSnakeCase() throws {
        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceA,
            receiverDeviceId: deviceB,
            type: .command,
            payloadJSON: "{}"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["workspace_id"])
        XCTAssertNotNil(json["sender_device_id"])
        XCTAssertNotNil(json["receiver_device_id"])
        XCTAssertNotNil(json["payload_json"])
        XCTAssertNotNil(json["created_at"])
    }

    // MARK: - Router: Send

    func testSendAddsToOutbox() {
        let msg = router.send(to: deviceB, type: .text, payloadJSON: "{\"text\":\"hi\"}")
        XCTAssertEqual(msg.status, .queued)
        XCTAssertEqual(msg.senderDeviceId, deviceA)
        XCTAssertEqual(msg.receiverDeviceId, deviceB)
        XCTAssertEqual(msg.workspaceId, workspace)
        XCTAssertNotNil(msg.expiresAt)
        XCTAssertEqual(router.pendingOutbox().count, 1)
    }

    func testSendMultiple() {
        router.send(to: deviceB, type: .text)
        router.send(to: deviceB, type: .ttsRequest)
        router.send(to: deviceB, type: .notification)
        XCTAssertEqual(router.pendingOutbox().count, 3)
    }

    func testSendCustomTTL() {
        let msg = router.send(to: deviceB, type: .text, ttl: 60)
        let expiresAt = msg.expiresAt!
        // Should expire within ~60-62 seconds
        let interval = expiresAt.timeIntervalSince(msg.createdAt)
        XCTAssertEqual(interval, 60, accuracy: 2)
    }

    // MARK: - Router: Receive

    func testReceiveWithHandler() async {
        let handler = MockPeerMessageHandler()
        router.registerHandler(handler, for: .text)

        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .text,
            payloadJSON: "{\"text\":\"hello\"}"
        )
        await router.receive(message: msg)

        XCTAssertEqual(handler.handledMessages.count, 1)
        let stored = router.inbox[msg.id]!
        XCTAssertEqual(stored.status, .processed)
        XCTAssertNotNil(stored.deliveredAt)
        XCTAssertNotNil(stored.processedAt)
    }

    func testReceiveWithFailingHandler() async {
        let handler = MockPeerMessageHandler()
        handler.shouldSucceed = false
        router.registerHandler(handler, for: .command)

        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .command
        )
        await router.receive(message: msg)

        let stored = router.inbox[msg.id]!
        XCTAssertEqual(stored.status, .failed)
        XCTAssertNotNil(stored.errorMessage)
    }

    func testReceiveNoHandler() async {
        // No handler registered for .notification
        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .notification
        )
        await router.receive(message: msg)

        let stored = router.inbox[msg.id]!
        XCTAssertEqual(stored.status, .failed)
        XCTAssertTrue(stored.errorMessage?.contains("핸들러") ?? false)
    }

    func testReceiveExpiredMessage() async {
        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .text,
            expiresAt: Date().addingTimeInterval(-60) // already expired
        )
        await router.receive(message: msg)

        let stored = router.inbox[msg.id]!
        XCTAssertEqual(stored.status, .expired)
    }

    // MARK: - Router: Deliver Queued

    func testDeliverQueuedMessages() async {
        let handler = MockPeerMessageHandler()
        router.registerHandler(handler, for: .text)
        router.registerHandler(handler, for: .notification)

        let messages = [
            PeerMessage(
                workspaceId: workspace,
                senderDeviceId: deviceB,
                receiverDeviceId: deviceA,
                type: .text,
                payloadJSON: "{\"text\":\"msg1\"}"
            ),
            PeerMessage(
                workspaceId: workspace,
                senderDeviceId: deviceB,
                receiverDeviceId: deviceA,
                type: .notification,
                payloadJSON: "{\"text\":\"msg2\"}"
            ),
            // This one is for a different device — should be skipped
            PeerMessage(
                workspaceId: workspace,
                senderDeviceId: deviceB,
                receiverDeviceId: UUID(),
                type: .text
            ),
        ]

        await router.deliverQueued(messages: messages)
        XCTAssertEqual(handler.handledMessages.count, 2)
    }

    func testDeliverQueuedSkipsNonQueued() async {
        let handler = MockPeerMessageHandler()
        router.registerHandler(handler, for: .text)

        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .text,
            status: .delivered // not queued
        )
        await router.deliverQueued(messages: [msg])
        XCTAssertEqual(handler.handledMessages.count, 0)
    }

    // MARK: - Router: Query

    func testRecentInbox() async {
        let handler = MockPeerMessageHandler()
        router.registerHandler(handler, for: .text)

        for _ in 0..<5 {
            let msg = PeerMessage(
                workspaceId: workspace,
                senderDeviceId: deviceB,
                receiverDeviceId: deviceA,
                type: .text
            )
            await router.receive(message: msg)
        }

        let recent = router.recentInbox(limit: 3)
        XCTAssertEqual(recent.count, 3)
    }

    func testMarkSent() {
        let msg = router.send(to: deviceB, type: .text)
        XCTAssertEqual(router.outbox[msg.id]!.status, .queued)

        router.markSent(messageId: msg.id)
        XCTAssertEqual(router.outbox[msg.id]!.status, .delivered)
        XCTAssertNotNil(router.outbox[msg.id]!.deliveredAt)
    }

    func testMarkSentNonExistent() {
        router.markSent(messageId: UUID()) // should not crash
    }

    // MARK: - Router: Cleanup

    func testCleanupExpired() {
        // Send message with very short TTL (already expired)
        let msg = router.send(to: deviceB, type: .text, ttl: -60)
        XCTAssertEqual(router.outbox[msg.id]!.status, .queued)

        router.cleanupExpired()
        XCTAssertEqual(router.outbox[msg.id]!.status, .expired)
    }

    func testCleanupKeepsValidMessages() {
        let msg = router.send(to: deviceB, type: .text, ttl: 3600)
        router.cleanupExpired()
        XCTAssertEqual(router.outbox[msg.id]!.status, .queued)
    }

    func testPurgeRemovesOldProcessed() async {
        let handler = MockPeerMessageHandler()
        router.registerHandler(handler, for: .text)

        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .text,
            createdAt: Date().addingTimeInterval(-200_000)
        )
        await router.receive(message: msg)

        // Verify it's in inbox
        XCTAssertNotNil(router.inbox[msg.id])

        router.purge(olderThan: 86400)
        XCTAssertNil(router.inbox[msg.id])
    }

    func testPurgeKeepsRecentMessages() async {
        let handler = MockPeerMessageHandler()
        router.registerHandler(handler, for: .text)

        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .text
        )
        await router.receive(message: msg)

        router.purge(olderThan: 86400)
        XCTAssertNotNil(router.inbox[msg.id]) // recent, should stay
    }

    // MARK: - Router: Handler Registration

    func testRegisterMultipleHandlers() async {
        let textHandler = MockPeerMessageHandler()
        let ttsHandler = MockPeerMessageHandler()
        router.registerHandler(textHandler, for: .text)
        router.registerHandler(ttsHandler, for: .ttsRequest)

        let textMsg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .text
        )
        let ttsMsg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .ttsRequest
        )

        await router.receive(message: textMsg)
        await router.receive(message: ttsMsg)

        XCTAssertEqual(textHandler.handledMessages.count, 1)
        XCTAssertEqual(ttsHandler.handledMessages.count, 1)
    }

    func testReplaceHandler() async {
        let handler1 = MockPeerMessageHandler()
        let handler2 = MockPeerMessageHandler()
        router.registerHandler(handler1, for: .text)
        router.registerHandler(handler2, for: .text) // replace

        let msg = PeerMessage(
            workspaceId: workspace,
            senderDeviceId: deviceB,
            receiverDeviceId: deviceA,
            type: .text
        )
        await router.receive(message: msg)

        XCTAssertEqual(handler1.handledMessages.count, 0)
        XCTAssertEqual(handler2.handledMessages.count, 1)
    }
}
