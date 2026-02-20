import XCTest
@testable import Dochi

final class ToolDispatchTests: XCTestCase {
    @MainActor
    private final class RecordingToolContextStore: ToolContextStoreProtocol {
        private(set) var events: [ToolUsageEvent] = []

        func record(_ event: ToolUsageEvent) async {
            events.append(event)
        }

        func profile(workspaceId _: String, agentName _: String) async -> ToolContextProfile? {
            nil
        }

        func userPreference(workspaceId _: String) async -> UserToolPreference {
            UserToolPreference()
        }

        func updateUserPreference(_: UserToolPreference, workspaceId _: String) async {}

        func flushToDisk() async {}
    }

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
    func testToolDispatchHandlerRecordsUsageEvent() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(
            toolCallId: "tc-usage",
            content: "ok"
        )
        let toolContextStore = RecordingToolContextStore()
        let handler = ToolDispatchHandler(
            toolService: mockToolService,
            toolContextStore: toolContextStore
        )

        let event = BridgeEvent(
            eventId: "e-usage",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: "ws-1",
            agentId: "코디",
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-usage"),
                "toolName": .string("agent.list"),
                "arguments": .object([:]),
                "riskLevel": .string("safe"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(toolContextStore.events.count, 1)
        XCTAssertEqual(toolContextStore.events.first?.workspaceId, "ws-1")
        XCTAssertEqual(toolContextStore.events.first?.agentName, "코디")
        XCTAssertEqual(toolContextStore.events.first?.toolName, "agent.list")
        XCTAssertEqual(toolContextStore.events.first?.category, "agent")
        XCTAssertEqual(toolContextStore.events.first?.decision, .allowed)
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

    // MARK: - executeWithTimeout TaskGroup Race Tests (#305)

    @MainActor
    func testExecuteWithTimeout_FastExecution_ReturnsNormally() async {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-fast", content: "fast result")
        // No delay -- tool finishes immediately

        let handler = ToolDispatchHandler(toolService: mockToolService)

        let result = await handler.executeWithTimeout(
            toolName: "test.fast",
            toolCallId: "tc-fast",
            arguments: ["key": "value"],
            timeout: 5
        )

        XCTAssertEqual(result.content, "fast result")
        XCTAssertFalse(result.isError)
        XCTAssertEqual(mockToolService.executeCallCount, 1)
    }

    @MainActor
    func testExecuteWithTimeout_SlowExecution_ReturnsTimeout() async {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-slow", content: "should not see this")
        mockToolService.executeDelay = .seconds(10) // Much longer than timeout

        let handler = ToolDispatchHandler(toolService: mockToolService)

        let result = await handler.executeWithTimeout(
            toolName: "test.slow",
            toolCallId: "tc-slow",
            arguments: [:],
            timeout: 0.1 // 100ms timeout
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("timed out"))
        XCTAssertTrue(result.content.contains("test.slow"))
    }

    @MainActor
    func testExecuteWithTimeout_ArgumentsForwarded() async {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-args", content: "ok")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        let args: [String: Any] = ["query": "hello", "count": 42]
        let _ = await handler.executeWithTimeout(
            toolName: "test.args",
            toolCallId: "tc-args",
            arguments: args,
            timeout: 5
        )

        XCTAssertEqual(mockToolService.lastExecutedName, "test.args")
        XCTAssertEqual(mockToolService.lastArguments?["query"] as? String, "hello")
        XCTAssertEqual(mockToolService.lastArguments?["count"] as? Int, 42)
    }

    @MainActor
    func testExecuteWithTimeout_TimeoutIncludesToolNameAndDuration() async {
        let mockToolService = MockBuiltInToolService()
        mockToolService.executeDelay = .seconds(10)

        let handler = ToolDispatchHandler(toolService: mockToolService)

        let result = await handler.executeWithTimeout(
            toolName: "fs.write",
            toolCallId: "tc-msg",
            arguments: [:],
            timeout: 0.05
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.toolCallId, "tc-msg")
        // Verify the error message includes tool name and timeout duration
        XCTAssertTrue(result.content.contains("fs.write"))
        XCTAssertTrue(result.content.contains("0"))  // Int(0.05) == 0
    }

    @MainActor
    func testExecuteWithTimeout_ReturnsWithinExpectedTime() async {
        // Verify the function actually returns promptly on timeout
        // rather than blocking until the tool finishes.
        let mockToolService = MockBuiltInToolService()
        mockToolService.executeDelay = .seconds(60)  // tool would take 60s

        let handler = ToolDispatchHandler(toolService: mockToolService)

        let start = ContinuousClock.now
        let result = await handler.executeWithTimeout(
            toolName: "test.blocking",
            toolCallId: "tc-time",
            arguments: [:],
            timeout: 0.1
        )
        let elapsed = ContinuousClock.now - start

        XCTAssertTrue(result.isError)
        // Should return well within 2 seconds, not wait 60s for the tool
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    @MainActor
    func testExecuteWithTimeout_ConcurrentCallsDoNotInterfere() async {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-conc", content: "concurrent ok")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        // Launch multiple concurrent executeWithTimeout calls
        async let r1 = handler.executeWithTimeout(
            toolName: "tool.a", toolCallId: "tc-1", arguments: [:], timeout: 5
        )
        async let r2 = handler.executeWithTimeout(
            toolName: "tool.b", toolCallId: "tc-2", arguments: [:], timeout: 5
        )
        async let r3 = handler.executeWithTimeout(
            toolName: "tool.c", toolCallId: "tc-3", arguments: [:], timeout: 5
        )

        let results = await [r1, r2, r3]

        // All should complete successfully (no cross-contamination)
        for result in results {
            XCTAssertFalse(result.isError)
            XCTAssertEqual(result.content, "concurrent ok")
        }
        XCTAssertEqual(mockToolService.executeCallCount, 3)
    }
}
