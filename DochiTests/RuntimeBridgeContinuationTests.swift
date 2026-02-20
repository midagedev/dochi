import XCTest
@testable import Dochi

/// Tests for the continuation registration race fix in RuntimeBridgeService (issue #301).
@MainActor
final class RuntimeBridgeContinuationTests: XCTestCase {

    func testContinuationRegisteredSynchronouslyOnRunSession() {
        let service = RuntimeBridgeService(
            socketPath: "/tmp/test-dochi-\(UUID().uuidString).sock",
            runtimeExecutablePath: "/dev/null"
        )

        let sessionId = "test-session-\(UUID().uuidString)"
        let params = SessionRunParams(
            sessionId: sessionId,
            input: "hello",
            contextSnapshotRef: nil,
            permissionMode: nil
        )

        XCTAssertNil(service.sessionContinuations[sessionId])
        let _ = service.runSession(params: params)
        XCTAssertNotNil(
            service.sessionContinuations[sessionId],
            "Continuation must be registered synchronously when runSession returns"
        )
    }

    func testEarlyNotificationIsDeliveredToStream() async throws {
        let service = RuntimeBridgeService(
            socketPath: "/tmp/test-dochi-\(UUID().uuidString).sock",
            runtimeExecutablePath: "/dev/null"
        )

        let sessionId = "test-session-\(UUID().uuidString)"
        let params = SessionRunParams(
            sessionId: sessionId,
            input: "hello",
            contextSnapshotRef: nil,
            permissionMode: nil
        )

        let stream = service.runSession(params: params)

        let notification = JsonRpcNotification(
            jsonrpc: "2.0",
            method: "bridge.event",
            params: [
                "eventId": .string("evt-001"),
                "timestamp": .string("2026-02-20T00:00:00Z"),
                "sessionId": .string(sessionId),
                "workspaceId": .string("ws-1"),
                "agentId": .string("agent-1"),
                "eventType": .string("session.partial"),
                "payload": .object(["text": .string("Hello world")]),
            ]
        )
        service.handleNotification(notification)

        let completionNotification = JsonRpcNotification(
            jsonrpc: "2.0",
            method: "bridge.event",
            params: [
                "eventId": .string("evt-002"),
                "timestamp": .string("2026-02-20T00:00:01Z"),
                "sessionId": .string(sessionId),
                "workspaceId": .string("ws-1"),
                "agentId": .string("agent-1"),
                "eventType": .string("session.completed"),
                "payload": .null,
            ]
        )
        service.handleNotification(completionNotification)

        var receivedEvents: [BridgeEvent] = []
        for try await event in stream {
            receivedEvents.append(event)
        }

        XCTAssertGreaterThanOrEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.eventType, .sessionPartial)
        XCTAssertEqual(receivedEvents.first?.eventId, "evt-001")
    }

    func testContinuationCleanedUpOnSessionCompleted() async throws {
        let service = RuntimeBridgeService(
            socketPath: "/tmp/test-dochi-\(UUID().uuidString).sock",
            runtimeExecutablePath: "/dev/null"
        )

        let sessionId = "test-session-\(UUID().uuidString)"
        let params = SessionRunParams(
            sessionId: sessionId,
            input: "hello",
            contextSnapshotRef: nil,
            permissionMode: nil
        )

        let stream = service.runSession(params: params)
        XCTAssertNotNil(service.sessionContinuations[sessionId])

        let completionNotification = JsonRpcNotification(
            jsonrpc: "2.0",
            method: "bridge.event",
            params: [
                "eventId": .string("evt-done"),
                "timestamp": .string("2026-02-20T00:00:00Z"),
                "sessionId": .string(sessionId),
                "workspaceId": .null,
                "agentId": .null,
                "eventType": .string("session.completed"),
                "payload": .null,
            ]
        )
        service.handleNotification(completionNotification)

        for try await _ in stream { }

        XCTAssertNil(service.sessionContinuations[sessionId])
    }

    func testMultipleSessionsReceiveOwnContinuations() {
        let service = RuntimeBridgeService(
            socketPath: "/tmp/test-dochi-\(UUID().uuidString).sock",
            runtimeExecutablePath: "/dev/null"
        )

        let _ = service.runSession(params: SessionRunParams(
            sessionId: "session-A", input: "a", contextSnapshotRef: nil, permissionMode: nil
        ))
        let _ = service.runSession(params: SessionRunParams(
            sessionId: "session-B", input: "b", contextSnapshotRef: nil, permissionMode: nil
        ))

        XCTAssertNotNil(service.sessionContinuations["session-A"])
        XCTAssertNotNil(service.sessionContinuations["session-B"])
        XCTAssertEqual(service.sessionContinuations.count, 2)
    }
}
