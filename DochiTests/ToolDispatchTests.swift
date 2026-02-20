import XCTest
@testable import Dochi

final class ToolDispatchTests: XCTestCase {

    // MARK: - Schema Types

    func testToolDispatchParamsEncodeDecode() throws {
        let params = ToolDispatchParams(
            toolCallId: "tc-1",
            toolName: "calendar.today",
            arguments: ["count": .int(5), "query": .string("meetings")],
            sessionId: "s-1",
            riskLevel: "safe"
        )

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(ToolDispatchParams.self, from: data)

        XCTAssertEqual(decoded.toolCallId, "tc-1")
        XCTAssertEqual(decoded.toolName, "calendar.today")
        XCTAssertEqual(decoded.sessionId, "s-1")
        XCTAssertEqual(decoded.riskLevel, "safe")

        if case .int(let count) = decoded.arguments["count"] {
            XCTAssertEqual(count, 5)
        } else {
            XCTFail("Expected int argument 'count'")
        }
    }

    func testToolResultParamsEncodeDecode() throws {
        let params = ToolResultParams(
            toolCallId: "tc-1",
            sessionId: "s-1",
            success: true,
            content: "3 meetings found",
            errorCode: nil
        )

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(ToolResultParams.self, from: data)

        XCTAssertEqual(decoded.toolCallId, "tc-1")
        XCTAssertEqual(decoded.sessionId, "s-1")
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.content, "3 meetings found")
        XCTAssertNil(decoded.errorCode)
    }

    func testToolResultParamsWithErrorCode() throws {
        let params = ToolResultParams(
            toolCallId: "tc-2",
            sessionId: "s-1",
            success: false,
            content: "Tool not found",
            errorCode: BridgeErrorCode.toolNotFound.rawValue
        )

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(ToolResultParams.self, from: data)

        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.errorCode, -32010)
    }

    func testToolResultAckEncodeDecode() throws {
        let ack = ToolResultAck(received: true, toolCallId: "tc-1")

        let data = try JSONEncoder().encode(ack)
        let decoded = try JSONDecoder().decode(ToolResultAck.self, from: data)

        XCTAssertTrue(decoded.received)
        XCTAssertEqual(decoded.toolCallId, "tc-1")
    }

    // MARK: - Error Codes

    func testToolErrorCodes() {
        XCTAssertEqual(BridgeErrorCode.toolNotFound.rawValue, -32010)
        XCTAssertEqual(BridgeErrorCode.toolExecutionFailed.rawValue, -32011)
        XCTAssertEqual(BridgeErrorCode.toolTimeout.rawValue, -32012)
        XCTAssertEqual(BridgeErrorCode.toolPermissionDenied.rawValue, -32013)
    }

    // MARK: - Timeout Policy

    func testTimeoutPolicyDefaults() {
        XCTAssertEqual(ToolTimeoutPolicy.safe, 30)
        XCTAssertEqual(ToolTimeoutPolicy.sensitive, 60)
        XCTAssertEqual(ToolTimeoutPolicy.restricted, 120)
    }

    @MainActor
    func testToolDispatchHandlerTimeout() {
        XCTAssertEqual(ToolDispatchHandler.timeout(for: "safe"), 30)
        XCTAssertEqual(ToolDispatchHandler.timeout(for: "sensitive"), 60)
        XCTAssertEqual(ToolDispatchHandler.timeout(for: "restricted"), 120)
        XCTAssertEqual(ToolDispatchHandler.timeout(for: "unknown"), 30) // defaults to safe
    }

    // MARK: - BridgeEventType

    func testToolDispatchEventType() throws {
        let json = """
        {
            "eventId": "e-1",
            "timestamp": "2024-01-01T00:00:00Z",
            "sessionId": "s-1",
            "eventType": "tool.dispatch",
            "payload": {
                "toolCallId": "tc-1",
                "toolName": "calendar.today",
                "arguments": {},
                "riskLevel": "safe"
            }
        }
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.eventType, .toolDispatch)
        XCTAssertEqual(event.sessionId, "s-1")
    }

    // MARK: - ToolDispatchHandler Unit Tests

    @MainActor
    func testToolDispatchHandlerCallsToolService() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(
            toolCallId: "tc-1",
            content: "Today: 2 meetings"
        )

        let handler = ToolDispatchHandler(toolService: mockToolService)

        // Create a tool.dispatch event
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("calendar.today"),
                "arguments": .object(["count": .int(5)]),
                "riskLevel": .string("safe"),
            ])
        )

        handler.handleDispatch(event: event)

        // Wait for the async task to complete
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockToolService.executeCallCount, 1)
        XCTAssertEqual(mockToolService.lastExecutedName, "calendar.today")

        // Verify arguments were converted from AnyCodableValue to native
        if let count = mockToolService.lastArguments?["count"] as? Int {
            XCTAssertEqual(count, 5)
        } else {
            XCTFail("Expected integer argument 'count'")
        }
    }

    @MainActor
    func testToolDispatchHandlerIgnoresInvalidPayload() async throws {
        let mockToolService = MockBuiltInToolService()
        let handler = ToolDispatchHandler(toolService: mockToolService)

        // Missing toolCallId
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object(["toolName": .string("test")])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(mockToolService.executeCallCount, 0)
    }

    @MainActor
    func testToolDispatchHandlerIgnoresNilSessionId() async throws {
        let mockToolService = MockBuiltInToolService()
        let handler = ToolDispatchHandler(toolService: mockToolService)

        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: nil,
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("test"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(mockToolService.executeCallCount, 0)
    }

    @MainActor
    func testToolDispatchHandlerDefaultsToSafeRiskLevel() async throws {
        let mockToolService = MockBuiltInToolService()
        let handler = ToolDispatchHandler(toolService: mockToolService)

        // No riskLevel in payload
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("test"),
                "arguments": .object([:]),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(100))

        // Should still execute (defaults to "safe" timeout)
        XCTAssertEqual(mockToolService.executeCallCount, 1)
    }

    // MARK: - AnyCodableValue → Native Conversion

    func testAnyCodableValueToNativeString() {
        let value = AnyCodableValue.string("hello")
        let native = value.toNative()
        XCTAssertEqual(native as? String, "hello")
    }

    func testAnyCodableValueToNativeInt() {
        let value = AnyCodableValue.int(42)
        let native = value.toNative()
        XCTAssertEqual(native as? Int, 42)
    }

    func testAnyCodableValueToNativeDouble() {
        let value = AnyCodableValue.double(3.14)
        let native = value.toNative()
        XCTAssertEqual(native as? Double, 3.14)
    }

    func testAnyCodableValueToNativeBool() {
        let value = AnyCodableValue.bool(true)
        let native = value.toNative()
        XCTAssertEqual(native as? Bool, true)
    }

    func testAnyCodableValueToNativeNull() {
        let value = AnyCodableValue.null
        let native = value.toNative()
        XCTAssertTrue(native is NSNull)
    }

    func testAnyCodableValueToNativeArray() {
        let value = AnyCodableValue.array([.string("a"), .int(1)])
        let native = value.toNative() as? [Any]
        XCTAssertNotNil(native)
        XCTAssertEqual(native?.count, 2)
        XCTAssertEqual(native?.first as? String, "a")
        XCTAssertEqual(native?.last as? Int, 1)
    }

    func testAnyCodableValueToNativeNestedObject() {
        let value: [String: AnyCodableValue] = [
            "name": .string("test"),
            "nested": .object(["key": .int(42)]),
        ]
        let native = value.toNativeDict()
        XCTAssertEqual(native["name"] as? String, "test")

        let nested = native["nested"] as? [String: Any]
        XCTAssertEqual(nested?["key"] as? Int, 42)
    }

    // MARK: - Mock Bridge Tool Dispatch Configuration

    @MainActor
    func testMockBridgeConfigureToolDispatch() {
        let bridge = MockRuntimeBridgeService()
        let toolService = MockBuiltInToolService()

        bridge.configureToolDispatch(toolService: toolService)

        XCTAssertEqual(bridge.configureToolDispatchCallCount, 1)
        XCTAssertNotNil(bridge.lastToolService)
    }

    // MARK: - Codable Payload Decoding (decodePayload)

    @MainActor
    func testDecodePayloadInjectsSessionIdFromEnvelope() {
        // Payload has no sessionId, but event envelope does
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-envelope",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("test.tool"),
            ])
        )

        let decoded: ToolDispatchParams? = ToolDispatchHandler.decodePayload(event: event)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.sessionId, "s-envelope")
        XCTAssertEqual(decoded?.toolCallId, "tc-1")
        XCTAssertEqual(decoded?.toolName, "test.tool")
        XCTAssertEqual(decoded?.riskLevel, "safe") // default
        XCTAssertTrue(decoded?.arguments.isEmpty ?? false)
    }

    @MainActor
    func testDecodePayloadUsesPayloadSessionIdWhenPresent() {
        // Payload has its own sessionId — should take precedence
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-envelope",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("test.tool"),
                "sessionId": .string("s-payload"),
            ])
        )

        let decoded: ToolDispatchParams? = ToolDispatchHandler.decodePayload(event: event)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.sessionId, "s-payload")
    }

    @MainActor
    func testDecodePayloadReturnsNilForNilPayload() {
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: nil
        )

        let decoded: ToolDispatchParams? = ToolDispatchHandler.decodePayload(event: event)
        XCTAssertNil(decoded)
    }

    @MainActor
    func testDecodePayloadReturnsNilForNonObjectPayload() {
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .string("not an object")
        )

        let decoded: ToolDispatchParams? = ToolDispatchHandler.decodePayload(event: event)
        XCTAssertNil(decoded)
    }

    @MainActor
    func testDecodePayloadReturnsNilForMissingRequiredField() {
        // Missing toolCallId (required)
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolName": .string("test"),
            ])
        )

        let decoded: ToolDispatchParams? = ToolDispatchHandler.decodePayload(event: event)
        XCTAssertNil(decoded)
    }

    @MainActor
    func testDecodePayloadReturnsNilWhenNoSessionIdAnywhere() {
        // No sessionId in payload or event envelope
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: nil,
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("test"),
            ])
        )

        let decoded: ToolDispatchParams? = ToolDispatchHandler.decodePayload(event: event)
        XCTAssertNil(decoded) // sessionId is required in ToolDispatchParams
    }

    func testToolDispatchParamsDefaultsWhenDecodingMinimalJSON() throws {
        // Minimal JSON: only required fields
        let json = """
        {
            "toolCallId": "tc-1",
            "toolName": "test",
            "sessionId": "s-1"
        }
        """
        let decoded = try JSONDecoder().decode(ToolDispatchParams.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.riskLevel, "safe") // default
        XCTAssertTrue(decoded.arguments.isEmpty) // default
    }

    func testToolDispatchParamsMemberwise() {
        // Memberwise init defaults
        let params = ToolDispatchParams(toolCallId: "tc-1", toolName: "test", sessionId: "s-1")
        XCTAssertEqual(params.riskLevel, "safe")
        XCTAssertTrue(params.arguments.isEmpty)
    }

    func testApprovalRequestParamsDefaultsWhenDecodingMinimalJSON() throws {
        // Minimal JSON: only required fields
        let json = """
        {
            "approvalId": "a-1",
            "toolCallId": "tc-1",
            "sessionId": "s-1",
            "toolName": "test",
            "riskLevel": "sensitive"
        }
        """
        let decoded = try JSONDecoder().decode(ApprovalRequestParams.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.reason, "") // default
        XCTAssertEqual(decoded.argumentsSummary, "") // default
    }

    @MainActor
    func testDecodePayloadForApprovalRequest() {
        // ApprovalRequestParams via decodePayload with sessionId injection
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-envelope",
            workspaceId: nil,
            agentId: nil,
            eventType: .approvalRequired,
            payload: .object([
                "approvalId": .string("a-1"),
                "toolCallId": .string("tc-1"),
                "toolName": .string("fs.write"),
                "riskLevel": .string("sensitive"),
                "reason": .string("File system access"),
            ])
        )

        let decoded: ApprovalRequestParams? = ToolDispatchHandler.decodePayload(event: event)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.approvalId, "a-1")
        XCTAssertEqual(decoded?.sessionId, "s-envelope")
        XCTAssertEqual(decoded?.reason, "File system access")
        XCTAssertEqual(decoded?.argumentsSummary, "") // default
    }
}
