import XCTest
@testable import Dochi

final class HookPipelineTests: XCTestCase {

    // MARK: - HookRuleset

    func testDefaultRulesetVersion() {
        let ruleset = HookRuleset.default
        XCTAssertEqual(ruleset.version, "1.0")
        XCTAssertFalse(ruleset.forbiddenPatterns.isEmpty)
        XCTAssertFalse(ruleset.piiPatterns.isEmpty)
    }

    func testRulesetEncodeDecode() throws {
        let ruleset = HookRuleset.default
        let data = try JSONEncoder().encode(ruleset)
        let decoded = try JSONDecoder().decode(HookRuleset.self, from: data)

        XCTAssertEqual(decoded.version, "1.0")
        XCTAssertEqual(decoded.forbiddenPatterns.count, ruleset.forbiddenPatterns.count)
        XCTAssertEqual(decoded.piiPatterns.count, ruleset.piiPatterns.count)
    }

    func testForbiddenPatternDefaults() {
        let patterns = ForbiddenPattern.defaults
        XCTAssertTrue(patterns.contains(where: { $0.pattern == "rm -rf /" }))
        XCTAssertTrue(patterns.contains(where: { $0.pattern == "sudo " }))
        XCTAssertTrue(patterns.contains(where: { $0.pattern == "mkfs" }))
    }

    func testPIIPatternDefaults() {
        let patterns = PIIPattern.defaults
        XCTAssertTrue(patterns.contains(where: { $0.name == "email" }))
        XCTAssertTrue(patterns.contains(where: { $0.name == "phone_kr" }))
        XCTAssertTrue(patterns.contains(where: { $0.name == "api_key" }))
    }

    // MARK: - ForbiddenPatternHook

    @MainActor
    func testForbiddenPatternBlocksDestructiveCommand() {
        let hook = ForbiddenPatternHook(patterns: ForbiddenPattern.defaults)
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "shell.execute",
            arguments: ["command": .string("rm -rf /")],
            riskLevel: "restricted"
        )

        let decision = hook.evaluate(context: context)
        if case .block(let reason) = decision {
            XCTAssertTrue(reason.contains("삭제"))
        } else {
            XCTFail("Expected .block decision")
        }
    }

    @MainActor
    func testForbiddenPatternBlocksSudo() {
        let hook = ForbiddenPatternHook(patterns: ForbiddenPattern.defaults)
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "shell.execute",
            arguments: ["command": .string("sudo apt-get install something")],
            riskLevel: "restricted"
        )

        let decision = hook.evaluate(context: context)
        if case .block = decision {
            // Expected
        } else {
            XCTFail("Expected .block decision for sudo command")
        }
    }

    @MainActor
    func testForbiddenPatternAllowsSafeCommand() {
        let hook = ForbiddenPatternHook(patterns: ForbiddenPattern.defaults)
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "shell.execute",
            arguments: ["command": .string("ls -la /tmp")],
            riskLevel: "safe"
        )

        let decision = hook.evaluate(context: context)
        if case .allow = decision {
            // Expected
        } else {
            XCTFail("Expected .allow decision for safe command")
        }
    }

    @MainActor
    func testForbiddenPatternSkipsNonMatchingTools() {
        let hook = ForbiddenPatternHook(patterns: ForbiddenPattern.defaults)
        // The forbidden patterns target shell.execute/terminal.run, not calendar
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "calendar.create",
            arguments: ["command": .string("sudo create event")],
            riskLevel: "sensitive"
        )

        let decision = hook.evaluate(context: context)
        if case .allow = decision {
            // Expected — "sudo" pattern only applies to shell tools
        } else {
            XCTFail("Expected .allow decision for non-shell tool")
        }
    }

    @MainActor
    func testForbiddenPatternCaseInsensitive() {
        let hook = ForbiddenPatternHook(patterns: ForbiddenPattern.defaults)
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "shell.execute",
            arguments: ["command": .string("SUDO apt-get install foo")],
            riskLevel: "restricted"
        )

        let decision = hook.evaluate(context: context)
        if case .block = decision {
            // Expected
        } else {
            XCTFail("Expected .block decision for case-insensitive sudo match")
        }
    }

    // MARK: - PIIMaskingHook

    @MainActor
    func testPIIMaskingEmailRedaction() {
        let hook = PIIMaskingHook(patterns: PIIPattern.defaults)
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "memory.save",
            arguments: ["content": .string("연락처: test@example.com")],
            riskLevel: "safe"
        )

        let decision = hook.evaluate(context: context)
        if case .mask(let masked) = decision {
            if case .string(let value) = masked["content"] {
                XCTAssertTrue(value.contains("[EMAIL]"))
                XCTAssertFalse(value.contains("test@example.com"))
            } else {
                XCTFail("Expected string value in masked arguments")
            }
        } else {
            XCTFail("Expected .mask decision for email PII")
        }
    }

    @MainActor
    func testPIIMaskingPhoneRedaction() {
        let hook = PIIMaskingHook(patterns: PIIPattern.defaults)
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "memory.save",
            arguments: ["content": .string("전화: 010-1234-5678")],
            riskLevel: "safe"
        )

        let decision = hook.evaluate(context: context)
        if case .mask(let masked) = decision {
            if case .string(let value) = masked["content"] {
                XCTAssertTrue(value.contains("[PHONE]"))
                XCTAssertFalse(value.contains("010-1234-5678"))
            } else {
                XCTFail("Expected string value in masked arguments")
            }
        } else {
            XCTFail("Expected .mask decision for phone PII")
        }
    }

    @MainActor
    func testPIIMaskingAPIKeyRedaction() {
        let hook = PIIMaskingHook(patterns: PIIPattern.defaults)
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "settings.set",
            arguments: ["value": .string("sk-abcdef1234567890abcdef1234567890")],
            riskLevel: "sensitive"
        )

        let decision = hook.evaluate(context: context)
        if case .mask(let masked) = decision {
            if case .string(let value) = masked["value"] {
                XCTAssertTrue(value.contains("[API_KEY]"))
            } else {
                XCTFail("Expected string value in masked arguments")
            }
        } else {
            XCTFail("Expected .mask decision for API key PII")
        }
    }

    @MainActor
    func testPIIMaskingNoPIINoMask() {
        let hook = PIIMaskingHook(patterns: PIIPattern.defaults)
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "calendar.today",
            arguments: ["count": .int(5)],
            riskLevel: "safe"
        )

        let decision = hook.evaluate(context: context)
        if case .allow = decision {
            // Expected — no string arguments contain PII
        } else {
            XCTFail("Expected .allow decision when no PII present")
        }
    }

    // MARK: - HookPipeline Integration

    @MainActor
    func testPipelineBlocksBeforeExecution() {
        let pipeline = HookPipeline()
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "shell.execute",
            arguments: ["command": .string("rm -rf /")],
            riskLevel: "restricted"
        )

        let result = pipeline.runPreHooks(context: context)
        if case .block = result.decision {
            XCTAssertEqual(result.hookName, "ForbiddenPattern")
        } else {
            XCTFail("Expected pipeline to block destructive command")
        }
    }

    @MainActor
    func testPipelineAllowsSafeCommands() {
        let pipeline = HookPipeline()
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "calendar.today",
            arguments: ["count": .int(5)],
            riskLevel: "safe"
        )

        let result = pipeline.runPreHooks(context: context)
        if case .allow = result.decision {
            XCTAssertNil(result.hookName)
        } else {
            XCTFail("Expected pipeline to allow safe command")
        }
    }

    @MainActor
    func testPipelineMasksPII() {
        let pipeline = HookPipeline()
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "memory.save",
            arguments: ["content": .string("Email: user@domain.com")],
            riskLevel: "safe"
        )

        let result = pipeline.runPreHooks(context: context)
        if case .mask(let masked) = result.decision {
            XCTAssertEqual(result.hookName, "PIIMasking")
            if case .string(let value) = masked["content"] {
                XCTAssertTrue(value.contains("[EMAIL]"))
            }
        } else {
            XCTFail("Expected pipeline to mask PII")
        }
    }

    @MainActor
    func testPipelineBlockTakesPrecedenceOverMask() {
        // ForbiddenPattern runs before PIIMasking
        let pipeline = HookPipeline()
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "shell.execute",
            arguments: ["command": .string("sudo send user@domain.com")],
            riskLevel: "restricted"
        )

        let result = pipeline.runPreHooks(context: context)
        if case .block = result.decision {
            XCTAssertEqual(result.hookName, "ForbiddenPattern")
        } else {
            XCTFail("Expected block to take precedence over mask")
        }
    }

    // MARK: - PostToolUse Hooks

    @MainActor
    func testMetricsRecordingHook() {
        let hook = MetricsRecordingHook()
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "calendar.today",
            arguments: [:],
            riskLevel: "safe"
        )
        let result = ToolResult(toolCallId: "tc-1", content: "2 meetings")

        let _ = hook.process(context: context, result: result, latencyMs: 42)

        XCTAssertEqual(hook.toolCallCounts["calendar.today"], 1)
        XCTAssertEqual(hook.toolLatencies["calendar.today"]?.first, 42)

        // Record another
        let _ = hook.process(context: context, result: result, latencyMs: 55)
        XCTAssertEqual(hook.toolCallCounts["calendar.today"], 2)
        XCTAssertEqual(hook.toolLatencies["calendar.today"]?.count, 2)
    }

    @MainActor
    func testMemoryCandidateHookExtractsFromRelevantTools() {
        let hook = MemoryCandidateHook()
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "calendar.today",
            arguments: [:],
            riskLevel: "safe"
        )
        let result = ToolResult(toolCallId: "tc-1", content: "Today: 10am Team meeting, 2pm Design review, 4pm Planning")

        let output = hook.process(context: context, result: result, latencyMs: 30)
        XCTAssertNotNil(output)
        XCTAssertFalse(output!.memoryCandidates.isEmpty)
        XCTAssertNotNil(output!.resultSummary)
    }

    @MainActor
    func testMemoryCandidateHookSkipsIrrelevantTools() {
        let hook = MemoryCandidateHook()
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "shell.execute",
            arguments: [:],
            riskLevel: "restricted"
        )
        let result = ToolResult(toolCallId: "tc-1", content: "Some shell output that is long enough to consider")

        let output = hook.process(context: context, result: result, latencyMs: 100)
        XCTAssertNil(output)
    }

    @MainActor
    func testMemoryCandidateHookSkipsErrors() {
        let hook = MemoryCandidateHook()
        let context = ToolHookContext(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: nil,
            toolName: "calendar.today",
            arguments: [:],
            riskLevel: "safe"
        )
        let result = ToolResult(toolCallId: "tc-1", content: "Error fetching calendar", isError: true)

        let output = hook.process(context: context, result: result, latencyMs: 30)
        XCTAssertNil(output)
    }

    // MARK: - Session Lifecycle Hooks

    @MainActor
    func testAuditFlushHookSessionClose() {
        let hook = AuditFlushHook()
        let auditLog = [
            ToolAuditEvent(toolCallId: "tc-1", sessionId: "s-1", agentId: nil, toolName: "calendar.today", argumentsHash: "abc", riskLevel: "safe", decision: .allowed, hookName: nil, latencyMs: 10, resultCode: nil, timestamp: Date()),
            ToolAuditEvent(toolCallId: "tc-2", sessionId: "s-1", agentId: nil, toolName: "shell.exec", argumentsHash: "def", riskLevel: "sensitive", decision: .approved, hookName: nil, latencyMs: 50, resultCode: nil, timestamp: Date()),
            ToolAuditEvent(toolCallId: "tc-3", sessionId: "s-2", agentId: nil, toolName: "test", argumentsHash: "", riskLevel: "safe", decision: .allowed, hookName: nil, latencyMs: 5, resultCode: nil, timestamp: Date()),
        ]

        // Should not crash and should log summary
        hook.onSessionClose(sessionId: "s-1", auditLog: auditLog)
    }

    @MainActor
    func testAuditFlushHookStop() {
        let hook = AuditFlushHook()
        let auditLog = [
            ToolAuditEvent(toolCallId: "tc-1", sessionId: "s-1", agentId: nil, toolName: "test", argumentsHash: "", riskLevel: "safe", decision: .allowed, hookName: nil, latencyMs: 10, resultCode: nil, timestamp: Date()),
        ]

        hook.onStop(auditLog: auditLog)
    }

    // MARK: - Arguments Hash

    @MainActor
    func testArgumentsHashConsistency() {
        let args1: [String: AnyCodableValue] = ["key": .string("value"), "count": .int(5)]
        let args2: [String: AnyCodableValue] = ["count": .int(5), "key": .string("value")]

        // Order shouldn't matter — keys are sorted
        let hash1 = HookPipeline.argumentsHash(args1)
        let hash2 = HookPipeline.argumentsHash(args2)
        XCTAssertEqual(hash1, hash2)
        XCTAssertFalse(hash1.isEmpty)
    }

    @MainActor
    func testArgumentsHashEmpty() {
        let hash = HookPipeline.argumentsHash([:])
        XCTAssertEqual(hash, "")
    }

    @MainActor
    func testArgumentsHashDifferentArgs() {
        let hash1 = HookPipeline.argumentsHash(["key": .string("value1")])
        let hash2 = HookPipeline.argumentsHash(["key": .string("value2")])
        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - Audit Schema Enhancement

    func testToolAuditEventHasArgumentsHash() {
        let event = ToolAuditEvent(
            toolCallId: "tc-1",
            sessionId: "s-1",
            agentId: "agent-1",
            toolName: "shell.execute",
            argumentsHash: "a1b2c3d4",
            riskLevel: "restricted",
            decision: .hookBlocked,
            hookName: "ForbiddenPattern",
            latencyMs: 5,
            resultCode: BridgeErrorCode.toolPermissionDenied.rawValue,
            timestamp: Date()
        )

        XCTAssertEqual(event.argumentsHash, "a1b2c3d4")
        XCTAssertEqual(event.hookName, "ForbiddenPattern")
        XCTAssertEqual(event.decision, .hookBlocked)
    }

    func testToolAuditDecisionHookBlocked() {
        XCTAssertEqual(ToolAuditDecision.hookBlocked.rawValue, "hookBlocked")
    }

    // MARK: - Hook Integration with ToolDispatchHandler

    @MainActor
    func testToolDispatchHandlerBlocksForbiddenCommand() async throws {
        let mockToolService = MockBuiltInToolService()
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
                "toolName": .string("shell.execute"),
                "arguments": .object(["command": .string("rm -rf /")]),
                "riskLevel": .string("restricted"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        // Tool should NOT have been executed (blocked by hook before approval check)
        XCTAssertEqual(mockToolService.executeCallCount, 0)

        // Audit log should record hookBlocked
        XCTAssertEqual(handler.auditLog.count, 1)
        XCTAssertEqual(handler.auditLog.first?.decision, .hookBlocked)
        XCTAssertEqual(handler.auditLog.first?.hookName, "ForbiddenPattern")
        XCTAssertFalse(handler.auditLog.first?.argumentsHash.isEmpty ?? true)
    }

    @MainActor
    func testToolDispatchHandlerRecordsArgumentsHash() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "OK")

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
                "arguments": .object(["count": .int(5)]),
                "riskLevel": .string("safe"),
            ])
        )

        handler.handleDispatch(event: event)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(handler.auditLog.count, 1)
        XCTAssertFalse(handler.auditLog.first?.argumentsHash.isEmpty ?? true)
    }

    @MainActor
    func testToolDispatchRunsPostHooks() async throws {
        let mockToolService = MockBuiltInToolService()
        mockToolService.stubbedResult = ToolResult(toolCallId: "tc-1", content: "Today: Team meeting at 10am, Design review at 2pm")

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

        // Should have executed and recorded metrics via post hook
        XCTAssertEqual(mockToolService.executeCallCount, 1)

        // Check metrics hook recorded the call
        if let metricsHook = handler.hookPipeline.postHooks.first(where: { $0.name == "MetricsRecording" }) as? MetricsRecordingHook {
            XCTAssertEqual(metricsHook.toolCallCounts["calendar.today"], 1)
        } else {
            XCTFail("MetricsRecordingHook not found in pipeline")
        }
    }

    @MainActor
    func testClearSessionApprovalsRunsLifecycleHooks() {
        let mockToolService = MockBuiltInToolService()
        let handler = ToolDispatchHandler(toolService: mockToolService)

        // Add some audit events
        // Use the internal mechanism by dispatching and recording
        // For this test, just verify that clearSessionApprovals doesn't crash
        handler.clearSessionApprovals(sessionId: "s-1")
        // Lifecycle hooks should have been called (AuditFlushHook)
    }

    @MainActor
    func testRunStopHooks() {
        let mockToolService = MockBuiltInToolService()
        let handler = ToolDispatchHandler(toolService: mockToolService)

        // Should not crash
        handler.runStopHooks()
    }
}
