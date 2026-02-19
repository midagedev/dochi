import XCTest
@testable import Dochi

final class BridgeSchemaTests: XCTestCase {

    // MARK: - BridgeErrorCode

    func testErrorCodeRawValues() {
        XCTAssertEqual(BridgeErrorCode.parseError.rawValue, -32700)
        XCTAssertEqual(BridgeErrorCode.invalidRequest.rawValue, -32600)
        XCTAssertEqual(BridgeErrorCode.methodNotFound.rawValue, -32601)
        XCTAssertEqual(BridgeErrorCode.invalidParams.rawValue, -32602)
        XCTAssertEqual(BridgeErrorCode.internalError.rawValue, -32603)
        XCTAssertEqual(BridgeErrorCode.sessionNotFound.rawValue, -32001)
        XCTAssertEqual(BridgeErrorCode.sessionAlreadyClosed.rawValue, -32002)
        XCTAssertEqual(BridgeErrorCode.runtimeNotReady.rawValue, -32003)
        XCTAssertEqual(BridgeErrorCode.sessionLimitExceeded.rawValue, -32004)
    }

    func testErrorCodeCodableRoundTrip() throws {
        let codes: [BridgeErrorCode] = [
            .parseError, .invalidRequest, .methodNotFound, .invalidParams,
            .internalError, .sessionNotFound, .sessionAlreadyClosed,
            .runtimeNotReady, .sessionLimitExceeded,
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for code in codes {
            let data = try encoder.encode(code)
            let decoded = try decoder.decode(BridgeErrorCode.self, from: data)
            XCTAssertEqual(decoded, code)
        }
    }

    // MARK: - SessionOpenParams

    func testSessionOpenParamsEncoding() throws {
        let params = SessionOpenParams(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "dev-1",
            sdkSessionId: nil
        )
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(SessionOpenParams.self, from: data)

        XCTAssertEqual(decoded.workspaceId, "ws-1")
        XCTAssertEqual(decoded.agentId, "agent-1")
        XCTAssertEqual(decoded.conversationId, "conv-1")
        XCTAssertEqual(decoded.userId, "user-1")
        XCTAssertEqual(decoded.deviceId, "dev-1")
        XCTAssertNil(decoded.sdkSessionId)
    }

    func testSessionOpenParamsWithSdkSessionId() throws {
        let json = """
        {"workspaceId":"ws","agentId":"a","conversationId":"c","userId":"u","deviceId":"d","sdkSessionId":"sdk-123"}
        """
        let params = try JSONDecoder().decode(SessionOpenParams.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(params.sdkSessionId, "sdk-123")
    }

    // MARK: - SessionOpenResult

    func testSessionOpenResultDecoding() throws {
        let json = """
        {"sessionId":"s-1","sdkSessionId":"sdk-1","created":true}
        """
        let result = try JSONDecoder().decode(SessionOpenResult.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(result.sessionId, "s-1")
        XCTAssertEqual(result.sdkSessionId, "sdk-1")
        XCTAssertTrue(result.created)
    }

    func testSessionOpenResultReuse() throws {
        let json = """
        {"sessionId":"s-1","sdkSessionId":"sdk-1","created":false}
        """
        let result = try JSONDecoder().decode(SessionOpenResult.self, from: json.data(using: .utf8)!)
        XCTAssertFalse(result.created)
    }

    // MARK: - SessionRunParams/Result

    func testSessionRunParamsEncoding() throws {
        let params = SessionRunParams(
            sessionId: "s-1",
            input: "Hello",
            contextSnapshotRef: "snap-1",
            permissionMode: "auto"
        )
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(SessionRunParams.self, from: data)

        XCTAssertEqual(decoded.sessionId, "s-1")
        XCTAssertEqual(decoded.input, "Hello")
        XCTAssertEqual(decoded.contextSnapshotRef, "snap-1")
        XCTAssertEqual(decoded.permissionMode, "auto")
    }

    func testSessionRunResultDecoding() throws {
        let json = """
        {"accepted":true,"sessionId":"s-1"}
        """
        let result = try JSONDecoder().decode(SessionRunResult.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.sessionId, "s-1")
    }

    // MARK: - SessionInterrupt

    func testSessionInterruptRoundTrip() throws {
        let params = SessionInterruptParams(sessionId: "s-1")
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(SessionInterruptParams.self, from: data)
        XCTAssertEqual(decoded.sessionId, "s-1")

        let resultJson = """
        {"interrupted":true,"sessionId":"s-1"}
        """
        let result = try JSONDecoder().decode(SessionInterruptResult.self, from: resultJson.data(using: .utf8)!)
        XCTAssertTrue(result.interrupted)
    }

    // MARK: - SessionClose

    func testSessionCloseRoundTrip() throws {
        let params = SessionCloseParams(sessionId: "s-1")
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(SessionCloseParams.self, from: data)
        XCTAssertEqual(decoded.sessionId, "s-1")

        let resultJson = """
        {"closed":true,"sessionId":"s-1"}
        """
        let result = try JSONDecoder().decode(SessionCloseResult.self, from: resultJson.data(using: .utf8)!)
        XCTAssertTrue(result.closed)
    }

    // MARK: - SessionList

    func testSessionListResultDecoding() throws {
        let json = """
        {"sessions":[{"sessionId":"s-1","sdkSessionId":"sdk-1","workspaceId":"ws","agentId":"a","conversationId":"c","status":"active","createdAt":"2026-01-01T00:00:00Z"}]}
        """
        let result = try JSONDecoder().decode(SessionListResult.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions[0].sessionId, "s-1")
        XCTAssertEqual(result.sessions[0].status, "active")
    }

    func testSessionListResultEmpty() throws {
        let json = """
        {"sessions":[]}
        """
        let result = try JSONDecoder().decode(SessionListResult.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(result.sessions.isEmpty)
    }

    // MARK: - BridgeEvent

    func testBridgeEventDecoding() throws {
        let json = """
        {"eventId":"e-1","timestamp":"2026-01-01T00:00:00Z","sessionId":"s-1","workspaceId":"ws","agentId":"a","eventType":"session.started","payload":null}
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.eventId, "e-1")
        XCTAssertEqual(event.eventType, .sessionStarted)
        XCTAssertEqual(event.sessionId, "s-1")
    }

    func testBridgeEventTypeRawValues() {
        XCTAssertEqual(BridgeEventType.runtimeReady.rawValue, "runtime.ready")
        XCTAssertEqual(BridgeEventType.sessionStarted.rawValue, "session.started")
        XCTAssertEqual(BridgeEventType.sessionPartial.rawValue, "session.partial")
        XCTAssertEqual(BridgeEventType.sessionCompleted.rawValue, "session.completed")
        XCTAssertEqual(BridgeEventType.sessionFailed.rawValue, "session.failed")
        XCTAssertEqual(BridgeEventType.approvalRequired.rawValue, "approval.required")
        XCTAssertEqual(BridgeEventType.policyBlocked.rawValue, "policy.blocked")
    }

    func testBridgeEventWithPayload() throws {
        let json = """
        {"eventId":"e-2","timestamp":"2026-01-01T00:00:00Z","sessionId":null,"workspaceId":null,"agentId":null,"eventType":"runtime.ready","payload":{"socketPath":"/tmp/test.sock"}}
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.eventType, .runtimeReady)
        XCTAssertNil(event.sessionId)

        if case .object(let dict) = event.payload {
            XCTAssertEqual(dict["socketPath"]?.stringValue, "/tmp/test.sock")
        } else {
            XCTFail("Expected object payload")
        }
    }

    // MARK: - EventAck

    func testEventAckRoundTrip() throws {
        let ack = EventAck(lastEventId: "e-42")
        let data = try JSONEncoder().encode(ack)
        let decoded = try JSONDecoder().decode(EventAck.self, from: data)
        XCTAssertEqual(decoded.lastEventId, "e-42")
    }
}
