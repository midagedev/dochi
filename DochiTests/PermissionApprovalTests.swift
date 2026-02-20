import XCTest
@testable import Dochi

final class PermissionApprovalTests: XCTestCase {

    // MARK: - Approval Schema Types

    func testApprovalRequestParamsEncodeDecode() throws {
        let params = ApprovalRequestParams(
            approvalId: "ap-1",
            toolCallId: "tc-1",
            sessionId: "s-1",
            toolName: "shell.exec",
            riskLevel: "sensitive",
            reason: "쉘 명령 실행 승인이 필요합니다",
            argumentsSummary: "command=ls -la"
        )

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(ApprovalRequestParams.self, from: data)

        XCTAssertEqual(decoded.approvalId, "ap-1")
        XCTAssertEqual(decoded.toolCallId, "tc-1")
        XCTAssertEqual(decoded.sessionId, "s-1")
        XCTAssertEqual(decoded.toolName, "shell.exec")
        XCTAssertEqual(decoded.riskLevel, "sensitive")
        XCTAssertEqual(decoded.reason, "쉘 명령 실행 승인이 필요합니다")
        XCTAssertEqual(decoded.argumentsSummary, "command=ls -la")
    }

    func testApprovalResolveParamsEncodeDecode() throws {
        let params = ApprovalResolveParams(
            approvalId: "ap-1",
            toolCallId: "tc-1",
            sessionId: "s-1",
            approved: true,
            scope: .session,
            note: nil
        )

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(ApprovalResolveParams.self, from: data)

        XCTAssertEqual(decoded.approvalId, "ap-1")
        XCTAssertTrue(decoded.approved)
        XCTAssertEqual(decoded.scope, .session)
        XCTAssertNil(decoded.note)
    }

    func testApprovalResolveParamsWithNote() throws {
        let params = ApprovalResolveParams(
            approvalId: "ap-2",
            toolCallId: "tc-2",
            sessionId: "s-1",
            approved: false,
            scope: .once,
            note: "사용자가 위험하다고 판단"
        )

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(ApprovalResolveParams.self, from: data)

        XCTAssertFalse(decoded.approved)
        XCTAssertEqual(decoded.scope, .once)
        XCTAssertEqual(decoded.note, "사용자가 위험하다고 판단")
    }

    func testApprovalResolveAckEncodeDecode() throws {
        let ack = ApprovalResolveAck(received: true, approvalId: "ap-1")

        let data = try JSONEncoder().encode(ack)
        let decoded = try JSONDecoder().decode(ApprovalResolveAck.self, from: data)

        XCTAssertTrue(decoded.received)
        XCTAssertEqual(decoded.approvalId, "ap-1")
    }

    // MARK: - ApprovalScope

    func testApprovalScopeRawValues() {
        XCTAssertEqual(ApprovalScope.once.rawValue, "once")
        XCTAssertEqual(ApprovalScope.session.rawValue, "session")
    }

    func testApprovalScopeEncodeDecode() throws {
        let data = try JSONEncoder().encode(ApprovalScope.session)
        let decoded = try JSONDecoder().decode(ApprovalScope.self, from: data)
        XCTAssertEqual(decoded, .session)
    }

    // MARK: - ToolAuditEvent & Decision

    func testToolAuditDecisionRawValues() {
        XCTAssertEqual(ToolAuditDecision.allowed.rawValue, "allowed")
        XCTAssertEqual(ToolAuditDecision.approved.rawValue, "approved")
        XCTAssertEqual(ToolAuditDecision.denied.rawValue, "denied")
        XCTAssertEqual(ToolAuditDecision.timeout.rawValue, "timeout")
        XCTAssertEqual(ToolAuditDecision.policyBlocked.rawValue, "policyBlocked")
    }

    // MARK: - BridgeEventType

    func testApprovalRequiredEventType() throws {
        let json = """
        {
            "eventId": "e-1",
            "timestamp": "2024-01-01T00:00:00Z",
            "sessionId": "s-1",
            "eventType": "approval.required",
            "payload": {
                "approvalId": "ap-1",
                "toolCallId": "tc-1",
                "toolName": "shell.exec",
                "riskLevel": "sensitive",
                "reason": "Test",
                "argumentsSummary": "cmd=test"
            }
        }
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.eventType, .approvalRequired)
        XCTAssertEqual(event.sessionId, "s-1")
    }

    // MARK: - ToolDispatchHandler Approval Flow

    @MainActor
    func testSensitiveToolRequiresApproval() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "OK")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        // Set approval handler that approves everything
        handler.approvalHandler = { _ in
            return (approved: true, scope: .once)
        }

        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        // Tool should have been executed after approval
        XCTAssertEqual(mockToolService.executeCallCount, 1)
        XCTAssertEqual(mockToolService.lastExecutedName, "shell.exec")

        // Audit log should record the approval
        XCTAssertEqual(handler.auditLog.count, 1)
        XCTAssertEqual(handler.auditLog.first?.decision, .approved)
        XCTAssertEqual(handler.auditLog.first?.toolName, "shell.exec")
        XCTAssertEqual(handler.auditLog.first?.riskLevel, "sensitive")
    }

    @MainActor
    func testSensitiveToolDenied() async throws {
        let mockToolService = MockBuiltInToolService()
        let handler = ToolDispatchHandler(toolService: mockToolService)

        // Set approval handler that denies
        handler.approvalHandler = { _ in
            return (approved: false, scope: .once)
        }

        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        // Tool should NOT have been executed
        XCTAssertEqual(mockToolService.executeCallCount, 0)

        // Audit log should record the denial
        XCTAssertEqual(handler.auditLog.count, 1)
        XCTAssertEqual(handler.auditLog.first?.decision, .denied)
    }

    @MainActor
    func testSafeToolSkipsApproval() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "OK")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        // Set approval handler (should NOT be called for safe tools)
        var approvalCalled = false
        handler.approvalHandler = { _ in
            approvalCalled = true
            return (approved: true, scope: .once)
        }

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
                "arguments": .object([:]),
                "riskLevel": .string("safe"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(mockToolService.executeCallCount, 1)
        XCTAssertFalse(approvalCalled)

        // Audit log should show "allowed" (not "approved")
        XCTAssertEqual(handler.auditLog.count, 1)
        XCTAssertEqual(handler.auditLog.first?.decision, .allowed)
    }

    @MainActor
    func testRestrictedToolRequiresApproval() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "Executed")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        var receivedParams: ApprovalRequestParams?
        handler.approvalHandler = { params in
            receivedParams = params
            return (approved: true, scope: .session)
        }

        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("file.delete"),
                "arguments": .object(["path": .string("/tmp/test")]),
                "riskLevel": .string("restricted"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(mockToolService.executeCallCount, 1)
        XCTAssertNotNil(receivedParams)
        XCTAssertEqual(receivedParams?.toolName, "file.delete")
        XCTAssertEqual(receivedParams?.riskLevel, "restricted")
    }

    // MARK: - Session-Scoped Approvals

    @MainActor
    func testSessionScopedApprovalCachesDecision() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "OK")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        var approvalCallCount = 0
        handler.approvalHandler = { _ in
            approvalCallCount += 1
            return (approved: true, scope: .session)
        }

        // First call — approval handler called
        let event1 = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event1)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(approvalCallCount, 1)
        XCTAssertEqual(mockToolService.executeCallCount, 1)

        // Second call — should use session-scoped approval, NOT call handler
        let event2 = BridgeEvent(
            eventId: "e-2",
            timestamp: "2024-01-01T00:00:01Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-2"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event2)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(approvalCallCount, 1, "Should NOT call approval handler again — session-scoped")
        XCTAssertEqual(mockToolService.executeCallCount, 2)
    }

    @MainActor
    func testClearSessionApprovalsResetsCache() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "OK")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        var approvalCallCount = 0
        handler.approvalHandler = { _ in
            approvalCallCount += 1
            return (approved: true, scope: .session)
        }

        // First call — gets session approval
        let event1 = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(approvalCallCount, 1)

        // Clear session approvals
        handler.clearSessionApprovals(sessionId: "s-1")

        // Third call — should require approval again
        let event3 = BridgeEvent(
            eventId: "e-3",
            timestamp: "2024-01-01T00:00:02Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-3"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event3)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(approvalCallCount, 2, "Should require approval again after clearing session")
    }

    @MainActor
    func testNoApprovalHandlerDeniesTool() async throws {
        let mockToolService = MockBuiltInToolService()
        let handler = ToolDispatchHandler(toolService: mockToolService)

        // No approval handler set — should auto-deny sensitive tools
        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(mockToolService.executeCallCount, 0, "Tool should not execute without approval handler")
        XCTAssertEqual(handler.auditLog.count, 1)
        XCTAssertEqual(handler.auditLog.first?.decision, .denied)
    }

    // MARK: - Audit Log

    @MainActor
    func testAuditLogRecordsLatency() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "OK")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        let event = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: "agent-1",
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("calendar.today"),
                "arguments": .object([:]),
                "riskLevel": .string("safe"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(handler.auditLog.count, 1)
        let audit = handler.auditLog.first!
        XCTAssertEqual(audit.toolCallId, "tc-1")
        XCTAssertEqual(audit.sessionId, "s-1")
        XCTAssertEqual(audit.agentId, "agent-1")
        XCTAssertEqual(audit.toolName, "calendar.today")
        XCTAssertEqual(audit.riskLevel, "safe")
        XCTAssertGreaterThanOrEqual(audit.latencyMs, 0)
        XCTAssertNil(audit.resultCode)
    }

    @MainActor
    func testAuditLogRecordsErrorCode() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(
            toolCallId: "tc-1",
            content: "Failed",
            isError: true
        )

        let handler = ToolDispatchHandler(toolService: mockToolService)

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
                "arguments": .object([:]),
                "riskLevel": .string("safe"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(handler.auditLog.count, 1)
        XCTAssertEqual(handler.auditLog.first?.decision, .policyBlocked)
        XCTAssertEqual(handler.auditLog.first?.resultCode, BridgeErrorCode.toolExecutionFailed.rawValue)
    }

    // MARK: - Mock Bridge Approval Handler

    @MainActor
    func testMockBridgeSetApprovalHandler() {
        let bridge = MockRuntimeBridgeService()

        let approvalHandler: ToolApprovalHandler = { _ in
            return (approved: true, scope: .once)
        }

        bridge.setApprovalHandler(approvalHandler)

        XCTAssertEqual(bridge.setApprovalHandlerCallCount, 1)
        XCTAssertNotNil(bridge.lastApprovalHandler)
    }

    // MARK: - Session Scoped Approval Across Different Sessions

    @MainActor
    func testSessionScopedApprovalDoesNotLeakAcrossSessions() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "OK")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        var approvalCallCount = 0
        handler.approvalHandler = { _ in
            approvalCallCount += 1
            return (approved: true, scope: .session)
        }

        // Session s-1 approval
        let event1 = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(approvalCallCount, 1)

        // Same tool in different session s-2 — should require new approval
        let event2 = BridgeEvent(
            eventId: "e-2",
            timestamp: "2024-01-01T00:00:01Z",
            sessionId: "s-2",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-2"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event2)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(approvalCallCount, 2, "Different session should require separate approval")
    }

    // MARK: - Once Scope Does Not Cache

    @MainActor
    func testOnceScopeDoesNotCache() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "OK")

        let handler = ToolDispatchHandler(toolService: mockToolService)

        var approvalCallCount = 0
        handler.approvalHandler = { _ in
            approvalCallCount += 1
            return (approved: true, scope: .once)
        }

        // First call
        let event1 = BridgeEvent(
            eventId: "e-1",
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-1"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(approvalCallCount, 1)

        // Second call — should require approval again (scope=once)
        let event2 = BridgeEvent(
            eventId: "e-2",
            timestamp: "2024-01-01T00:00:01Z",
            sessionId: "s-1",
            workspaceId: nil,
            agentId: nil,
            eventType: .toolDispatch,
            payload: .object([
                "toolCallId": .string("tc-2"),
                "toolName": .string("shell.exec"),
                "arguments": .object([:]),
                "riskLevel": .string("sensitive"),
            ])
        )

        handler.handleDispatch(event: event2)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(approvalCallCount, 2, "Once-scoped approval should not be cached")
    }
}
