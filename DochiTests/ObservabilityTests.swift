import XCTest
@testable import Dochi

// MARK: - TraceContext Tests

@MainActor
final class TraceContextTests: XCTestCase {

    func testStartTrace_createsTraceWithRootSpan() {
        let manager = TraceContextManager()
        let trace = manager.startTrace(name: "test-request", metadata: ["user": "alice"])

        XCTAssertEqual(trace.name, "test-request")
        XCTAssertEqual(trace.metadata["user"], "alice")
        XCTAssertTrue(trace.isActive)

        let spans = manager.spans(for: trace.id)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.name, "test-request")
        XCTAssertEqual(spans.first?.id, trace.rootSpanId)
        XCTAssertNil(spans.first?.parentSpanId)
    }

    func testStartSpan_createsChildSpan() {
        let manager = TraceContextManager()
        let trace = manager.startTrace(name: "request", metadata: [:])

        let childSpan = manager.startSpan(
            name: "context-build",
            traceId: trace.id,
            parentSpanId: trace.rootSpanId,
            attributes: ["layer": "workspace"]
        )

        let spans = manager.spans(for: trace.id)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(childSpan.parentSpanId, trace.rootSpanId)
        XCTAssertEqual(childSpan.attributes["layer"], "workspace")
        XCTAssertEqual(childSpan.status, .running)
    }

    func testEndSpan_setsEndTimeAndStatus() {
        let manager = TraceContextManager()
        let trace = manager.startTrace(name: "request", metadata: [:])
        let childSpan = manager.startSpan(
            name: "tool-call",
            traceId: trace.id,
            parentSpanId: trace.rootSpanId,
            attributes: [:]
        )

        manager.endSpan(childSpan, status: .ok)

        let spans = manager.spans(for: trace.id)
        let endedSpan = spans.first(where: { $0.id == childSpan.id })!
        XCTAssertNotNil(endedSpan.endTime)
        XCTAssertEqual(endedSpan.status, .ok)
        XCTAssertGreaterThan(endedSpan.durationMs, 0)
    }

    func testEndRootSpan_completesTrace() {
        let manager = TraceContextManager()
        let trace = manager.startTrace(name: "request", metadata: [:])
        XCTAssertTrue(trace.isActive)
        XCTAssertEqual(manager.activeTraces.count, 1)

        let rootSpan = manager.spans(for: trace.id).first!
        manager.endSpan(rootSpan, status: .ok)

        XCTAssertEqual(manager.activeTraces.count, 0)
        let completedTrace = manager.allTraces.first(where: { $0.id == trace.id })!
        XCTAssertFalse(completedTrace.isActive)
        XCTAssertNotNil(completedTrace.endTime)
    }

    func testNestedSpans_maintainParentChain() {
        let manager = TraceContextManager()
        let trace = manager.startTrace(name: "request", metadata: [:])

        let span1 = manager.startSpan(name: "context", traceId: trace.id, parentSpanId: trace.rootSpanId, attributes: [:])
        let span2 = manager.startSpan(name: "tool-call", traceId: trace.id, parentSpanId: span1.id, attributes: [:])
        let span3 = manager.startSpan(name: "tool-execute", traceId: trace.id, parentSpanId: span2.id, attributes: [:])

        XCTAssertEqual(manager.spans(for: trace.id).count, 4) // root + 3

        manager.endSpan(span3, status: .ok)
        manager.endSpan(span2, status: .ok)
        manager.endSpan(span1, status: .ok)

        let allSpans = manager.spans(for: trace.id)
        let toolExecuteSpan = allSpans.first(where: { $0.id == span3.id })!
        XCTAssertEqual(toolExecuteSpan.parentSpanId, span2.id)
        XCTAssertEqual(toolExecuteSpan.status, .ok)
    }

    func testTraceIdPropagation_allSpansShareTraceId() {
        let manager = TraceContextManager()
        let trace = manager.startTrace(name: "request", metadata: [:])

        _ = manager.startSpan(name: "span1", traceId: trace.id, parentSpanId: trace.rootSpanId, attributes: [:])
        _ = manager.startSpan(name: "span2", traceId: trace.id, parentSpanId: trace.rootSpanId, attributes: [:])

        let spans = manager.spans(for: trace.id)
        XCTAssertTrue(spans.allSatisfy { $0.traceId == trace.id })
    }

    func testMultipleTraces_areIndependent() {
        let manager = TraceContextManager()
        let trace1 = manager.startTrace(name: "request-1", metadata: [:])
        let trace2 = manager.startTrace(name: "request-2", metadata: [:])

        _ = manager.startSpan(name: "span-a", traceId: trace1.id, parentSpanId: trace1.rootSpanId, attributes: [:])
        _ = manager.startSpan(name: "span-b", traceId: trace2.id, parentSpanId: trace2.rootSpanId, attributes: [:])

        XCTAssertEqual(manager.spans(for: trace1.id).count, 2)
        XCTAssertEqual(manager.spans(for: trace2.id).count, 2)
        XCTAssertEqual(manager.activeTraces.count, 2)
    }

    func testEndSpan_withErrorStatus() {
        let manager = TraceContextManager()
        let trace = manager.startTrace(name: "request", metadata: [:])
        let span = manager.startSpan(name: "failing-op", traceId: trace.id, parentSpanId: trace.rootSpanId, attributes: [:])

        manager.endSpan(span, status: .error)

        let endedSpan = manager.spans(for: trace.id).first(where: { $0.id == span.id })!
        XCTAssertEqual(endedSpan.status, .error)
    }
}

// MARK: - RuntimeMetrics Tests

@MainActor
final class RuntimeMetricsTests: XCTestCase {

    func testIncrementCounter_accumulates() {
        let metrics = RuntimeMetrics()
        metrics.incrementCounter(name: "test_counter", labels: [:], delta: 1.0)
        metrics.incrementCounter(name: "test_counter", labels: [:], delta: 2.0)
        metrics.incrementCounter(name: "test_counter", labels: [:], delta: 3.0)

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.counter(name: "test_counter"), 6.0)
    }

    func testIncrementCounter_withLabels_separatesKeys() {
        let metrics = RuntimeMetrics()
        metrics.incrementCounter(name: MetricName.toolCallTotal, labels: ["tool": "calendar", "decision": "allowed"], delta: 1.0)
        metrics.incrementCounter(name: MetricName.toolCallTotal, labels: ["tool": "shell", "decision": "blocked"], delta: 1.0)
        metrics.incrementCounter(name: MetricName.toolCallTotal, labels: ["tool": "calendar", "decision": "allowed"], delta: 2.0)

        let snapshot = metrics.snapshot()
        let calendarKey = "\(MetricName.toolCallTotal)|decision=allowed,tool=calendar"
        let shellKey = "\(MetricName.toolCallTotal)|decision=blocked,tool=shell"
        XCTAssertEqual(snapshot.counter(name: calendarKey), 3.0)
        XCTAssertEqual(snapshot.counter(name: shellKey), 1.0)
    }

    func testRecordHistogram_calculatesPercentiles() {
        let metrics = RuntimeMetrics()

        // 100개의 값 기록 (1~100)
        for i in 1...100 {
            metrics.recordHistogram(name: MetricName.sessionLatencyMs, labels: [:], value: Double(i))
        }

        let snapshot = metrics.snapshot()
        let histogram = snapshot.histogram(name: MetricName.sessionLatencyMs)
        XCTAssertNotNil(histogram)
        XCTAssertEqual(histogram?.count, 100)
        XCTAssertEqual(histogram?.min, 1.0)
        XCTAssertEqual(histogram?.max, 100.0)

        // p50 should be around 50
        XCTAssertEqual(histogram!.p50, 50.5, accuracy: 1.0)
        // p95 should be around 95
        XCTAssertEqual(histogram!.p95, 95.05, accuracy: 1.0)
        // p99 should be around 99
        XCTAssertEqual(histogram!.p99, 99.01, accuracy: 1.0)
    }

    func testSetGauge_overwritesValue() {
        let metrics = RuntimeMetrics()
        metrics.setGauge(name: MetricName.sessionActive, labels: [:], value: 5.0)
        metrics.setGauge(name: MetricName.sessionActive, labels: [:], value: 3.0)

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.gauge(name: MetricName.sessionActive), 3.0)
    }

    func testSnapshot_capturesAllMetricTypes() {
        let metrics = RuntimeMetrics()
        metrics.incrementCounter(name: "counter_a", labels: [:], delta: 10.0)
        metrics.setGauge(name: "gauge_a", labels: [:], value: 42.0)
        metrics.recordHistogram(name: "hist_a", labels: [:], value: 100.0)

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.counter(name: "counter_a"), 10.0)
        XCTAssertEqual(snapshot.gauge(name: "gauge_a"), 42.0)
        XCTAssertNotNil(snapshot.histogram(name: "hist_a"))
    }

    func testReset_clearsAll() {
        let metrics = RuntimeMetrics()
        metrics.incrementCounter(name: "c", labels: [:], delta: 1.0)
        metrics.setGauge(name: "g", labels: [:], value: 1.0)
        metrics.recordHistogram(name: "h", labels: [:], value: 1.0)

        metrics.reset()

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.counter(name: "c"), 0.0)
        XCTAssertEqual(snapshot.gauge(name: "g"), 0.0)
        XCTAssertNil(snapshot.histogram(name: "h"))
    }

    func testHistogram_singleValue() {
        let metrics = RuntimeMetrics()
        metrics.recordHistogram(name: "single", labels: [:], value: 42.0)

        let snapshot = metrics.snapshot()
        let histogram = snapshot.histogram(name: "single")!
        XCTAssertEqual(histogram.count, 1)
        XCTAssertEqual(histogram.min, 42.0)
        XCTAssertEqual(histogram.max, 42.0)
        XCTAssertEqual(histogram.p50, 42.0)
        XCTAssertEqual(histogram.p95, 42.0)
        XCTAssertEqual(histogram.p99, 42.0)
    }

    func testMetricsSnapshot_isCodable() throws {
        let metrics = RuntimeMetrics()
        metrics.incrementCounter(name: "test", labels: [:], delta: 5.0)
        metrics.recordHistogram(name: "latency", labels: [:], value: 100.0)

        let snapshot = metrics.snapshot()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MetricsSnapshot.self, from: data)

        XCTAssertEqual(decoded.counter(name: "test"), 5.0)
        XCTAssertNotNil(decoded.histogram(name: "latency"))
    }
}

// MARK: - StructuredEventLogger Tests

@MainActor
final class StructuredEventLoggerTests: XCTestCase {

    func testLogEvent_recordsEvent() {
        let logger = StructuredEventLogger()
        let event = StructuredEvent(
            traceId: UUID(),
            sessionId: "session-1",
            eventType: .toolCall,
            payload: ["tool": "calendar.list"]
        )

        logger.log(event: event)

        XCTAssertEqual(logger.allEvents.count, 1)
        XCTAssertEqual(logger.allEvents.first?.eventType, .toolCall)
    }

    func testEventsForTrace_filtersCorrectly() {
        let logger = StructuredEventLogger()
        let traceId1 = UUID()
        let traceId2 = UUID()

        logger.log(event: StructuredEvent(traceId: traceId1, eventType: .sessionStart))
        logger.log(event: StructuredEvent(traceId: traceId1, eventType: .toolCall))
        logger.log(event: StructuredEvent(traceId: traceId2, eventType: .sessionStart))

        XCTAssertEqual(logger.events(for: traceId1).count, 2)
        XCTAssertEqual(logger.events(for: traceId2).count, 1)
    }

    func testEventsForSession_filtersCorrectly() {
        let logger = StructuredEventLogger()

        logger.log(event: StructuredEvent(sessionId: "s1", eventType: .sessionStart))
        logger.log(event: StructuredEvent(sessionId: "s1", eventType: .toolCall))
        logger.log(event: StructuredEvent(sessionId: "s1", eventType: .toolResult))
        logger.log(event: StructuredEvent(sessionId: "s2", eventType: .sessionStart))

        XCTAssertEqual(logger.events(for: "s1").count, 3)
        XCTAssertEqual(logger.events(for: "s2").count, 1)
    }

    func testExportJSON_writesValidJSON() throws {
        let logger = StructuredEventLogger()
        let event = StructuredEvent(
            traceId: UUID(),
            sessionId: "test-session",
            eventType: .hookDecision,
            payload: ["hook": "pre_tool", "decision": "allow"]
        )
        logger.log(event: event)

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_events_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try logger.exportJSON(to: url)

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder.iso8601Decoder.decode([StructuredEvent].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.eventType, .hookDecision)
        XCTAssertEqual(decoded.first?.payload["hook"], "pre_tool")
    }

    func testAllEventTypes_areRecordable() {
        let logger = StructuredEventLogger()
        let allTypes: [StructuredEventType] = [
            .sessionStart, .sessionEnd, .toolCall, .toolResult,
            .hookDecision, .approvalRequest, .approvalResolve,
            .routingDecision, .leaseAcquired, .leaseExpired
        ]

        for eventType in allTypes {
            logger.log(event: StructuredEvent(eventType: eventType))
        }

        XCTAssertEqual(logger.allEvents.count, 10)
        let recordedTypes = Set(logger.allEvents.map(\.eventType))
        XCTAssertEqual(recordedTypes.count, 10)
    }

    func testStructuredEvent_isCodable() throws {
        let event = StructuredEvent(
            traceId: UUID(),
            sessionId: "s1",
            eventType: .approvalRequest,
            payload: ["tool": "shell.execute", "level": "restricted"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StructuredEvent.self, from: data)

        XCTAssertEqual(decoded.id, event.id)
        XCTAssertEqual(decoded.traceId, event.traceId)
        XCTAssertEqual(decoded.sessionId, event.sessionId)
        XCTAssertEqual(decoded.eventType, .approvalRequest)
        XCTAssertEqual(decoded.payload["tool"], "shell.execute")
    }
}

// MARK: - SLO Gate Tests

@MainActor
final class SLOGateTests: XCTestCase {

    func testDefaultDefinitions_hasFourSLOs() {
        let definitions = SLOEvaluator.defaultDefinitions()
        XCTAssertEqual(definitions.count, 4)

        let names = definitions.map(\.name)
        XCTAssertTrue(names.contains("가용성"))
        XCTAssertTrue(names.contains("첫 partial 응답 지연"))
        XCTAssertTrue(names.contains("전체 응답 지연"))
        XCTAssertTrue(names.contains("세션 resume 성공률"))
    }

    func testEvaluate_allPass_whenMetricsAreGood() {
        let evaluator = SLOEvaluator()
        let metrics = RuntimeMetrics()

        // 가용성: 100 요청 중 0 에러 → 100%
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.requestErrorTotal, labels: [:], delta: 0)

        // 첫 partial p95: 1000ms (< 2000ms)
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: Double.random(in: 500...1500))
        }

        // 전체 응답 p95: 5000ms (< 8000ms)
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: Double.random(in: 2000...6000))
        }

        // resume 성공률: 100/100 = 100%
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 100)

        let result = evaluator.evaluate(snapshot: metrics.snapshot())
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.items.count, 4)
        XCTAssertTrue(result.items.allSatisfy(\.passed))
    }

    func testEvaluate_failsAvailability_whenErrorRateHigh() {
        let evaluator = SLOEvaluator()
        let metrics = RuntimeMetrics()

        // 가용성: 100 요청 중 10 에러 → 90% (< 99.5%)
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.requestErrorTotal, labels: [:], delta: 10)

        // 나머지 SLO는 통과하도록 설정
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 100)
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 500)
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: 2000)
        }

        let result = evaluator.evaluate(snapshot: metrics.snapshot())
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failedItems.count, 1)
        XCTAssertEqual(result.failedItems.first?.name, "가용성")
        XCTAssertEqual(result.failedItems.first!.actualValue, 0.9, accuracy: 0.01)
    }

    func testEvaluate_failsLatency_whenP95TooHigh() {
        let evaluator = SLOEvaluator()
        let metrics = RuntimeMetrics()

        // 가용성 OK
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)

        // 첫 partial p95: 3000ms (> 2000ms) — 대부분 높은 값
        for _ in 1...95 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 3000)
        }
        for _ in 1...5 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 100)
        }

        // 전체 응답 OK
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: 3000)
        }

        // resume OK
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 100)

        let result = evaluator.evaluate(snapshot: metrics.snapshot())
        XCTAssertFalse(result.passed)
        let failedNames = Set(result.failedItems.map(\.name))
        XCTAssertTrue(failedNames.contains("첫 partial 응답 지연"))
    }

    func testEvaluate_failsResume_whenSuccessRateLow() {
        let evaluator = SLOEvaluator()
        let metrics = RuntimeMetrics()

        // 가용성 OK
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)

        // latency OK
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 500)
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: 2000)
        }

        // resume: 90/100 = 90% (< 99%)
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 90)

        let result = evaluator.evaluate(snapshot: metrics.snapshot())
        XCTAssertFalse(result.passed)
        let failedNames = Set(result.failedItems.map(\.name))
        XCTAssertTrue(failedNames.contains("세션 resume 성공률"))
    }

    func testEvaluate_noData_passesAsDefault() {
        let evaluator = SLOEvaluator()
        let metrics = RuntimeMetrics()

        // 아무 데이터도 없으면 분모 0 → 기본 통과
        let result = evaluator.evaluate(snapshot: metrics.snapshot())
        XCTAssertTrue(result.passed)
    }

    func testDeploymentGate_allPass() {
        let evaluator = SLOEvaluator()
        let metrics = RuntimeMetrics()

        // Good metrics
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 100)
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 500)
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: 2000)
        }

        let testResult = TestGateResult(
            passed: true,
            totalTests: 50,
            passedTests: 50,
            failedTests: 0,
            regressionPassed: true
        )

        let securityChecks = [
            SecurityCheckItem(name: "API Key 노출 점검", description: "코드에 하드코딩된 API 키 없음", passed: true),
            SecurityCheckItem(name: "권한 정책 점검", description: "민감 도구 승인 플로우 동작", passed: true),
        ]

        let result = evaluator.evaluateDeploymentGate(
            metricsSnapshot: metrics.snapshot(),
            testResult: testResult,
            securityChecks: securityChecks
        )

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.sloResult.passed)
        XCTAssertTrue(result.testsPassedResult.passed)
        XCTAssertTrue(result.securityCheckResult.passed)
    }

    func testDeploymentGate_failsOnTestFailure() {
        let evaluator = SLOEvaluator()
        let metrics = RuntimeMetrics()

        let testResult = TestGateResult(
            passed: false,
            totalTests: 50,
            passedTests: 45,
            failedTests: 5,
            regressionPassed: false
        )

        let securityChecks = [
            SecurityCheckItem(name: "Check", description: "Check", passed: true),
        ]

        let result = evaluator.evaluateDeploymentGate(
            metricsSnapshot: metrics.snapshot(),
            testResult: testResult,
            securityChecks: securityChecks
        )

        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.testsPassedResult.passed)
    }

    func testDeploymentGate_failsOnSecurityFailure() {
        let evaluator = SLOEvaluator()
        let metrics = RuntimeMetrics()

        let testResult = TestGateResult(
            passed: true,
            totalTests: 50,
            passedTests: 50,
            failedTests: 0,
            regressionPassed: true
        )

        let securityChecks = [
            SecurityCheckItem(name: "API Key 노출 점검", description: "", passed: true),
            SecurityCheckItem(name: "권한 정책 점검", description: "", passed: false),
        ]

        let result = evaluator.evaluateDeploymentGate(
            metricsSnapshot: metrics.snapshot(),
            testResult: testResult,
            securityChecks: securityChecks
        )

        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.securityCheckResult.passed)
        XCTAssertEqual(result.securityCheckResult.failedItems.count, 1)
    }

    func testSLOResult_passRate() {
        let items = [
            SLOItemResult(definitionId: UUID(), name: "a", passed: true, actualValue: 1.0, thresholdValue: 0.9, description: ""),
            SLOItemResult(definitionId: UUID(), name: "b", passed: true, actualValue: 1.0, thresholdValue: 0.9, description: ""),
            SLOItemResult(definitionId: UUID(), name: "c", passed: false, actualValue: 0.5, thresholdValue: 0.9, description: ""),
        ]
        let result = SLOResult(passed: false, timestamp: Date(), items: items)
        XCTAssertEqual(result.passRate, 2.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(result.passedItems.count, 2)
        XCTAssertEqual(result.failedItems.count, 1)
    }
}

// MARK: - RegressionEvaluator Tests

@MainActor
final class RegressionEvaluatorTests: XCTestCase {

    func testRegisterScenario_addsToList() {
        let evaluator = RegressionEvaluator()
        let scenario = RegressionScenario(
            name: "가족 일정 조회",
            category: .family,
            description: "다음 주 가족 일정을 물어봄",
            input: "다음 주 가족 일정 알려줘",
            expectedOutput: ["일정", "캘린더"]
        )

        evaluator.registerScenario(scenario)
        XCTAssertEqual(evaluator.scenarios.count, 1)
        XCTAssertEqual(evaluator.scenarios.first?.name, "가족 일정 조회")
    }

    func testRunAll_executesAllScenarios() async {
        let runner = LocalRegressionScenarioRunner()
        let evaluator = RegressionEvaluator(runner: runner)

        let scenario1 = RegressionScenario(
            name: "가족 일정",
            category: .family,
            description: "",
            input: "일정 조회",
            expectedOutput: []
        )
        let scenario2 = RegressionScenario(
            name: "코드 리뷰",
            category: .development,
            description: "",
            input: "PR 리뷰해줘",
            expectedOutput: []
        )

        evaluator.registerScenario(scenario1)
        evaluator.registerScenario(scenario2)

        let report = await evaluator.runAll()
        XCTAssertEqual(report.results.count, 2)
        XCTAssertNotNil(evaluator.lastReport)
    }

    func testRunCategory_filtersCorrectly() async {
        let evaluator = RegressionEvaluator()

        evaluator.registerScenario(RegressionScenario(
            name: "가족 시나리오",
            category: .family,
            description: "",
            input: "test",
            expectedOutput: []
        ))
        evaluator.registerScenario(RegressionScenario(
            name: "개발 시나리오",
            category: .development,
            description: "",
            input: "test",
            expectedOutput: []
        ))

        let report = await evaluator.run(category: .family)
        XCTAssertEqual(report.results.count, 1)
        XCTAssertEqual(report.results.first?.category, .family)
    }

    func testReport_categorySummaries() async {
        let evaluator = RegressionEvaluator()

        for i in 1...3 {
            evaluator.registerScenario(RegressionScenario(
                name: "가족 \(i)",
                category: .family,
                description: "",
                input: "test",
                expectedOutput: []
            ))
        }
        for i in 1...2 {
            evaluator.registerScenario(RegressionScenario(
                name: "개발 \(i)",
                category: .development,
                description: "",
                input: "test",
                expectedOutput: []
            ))
        }

        let report = await evaluator.runAll()
        XCTAssertEqual(report.results.count, 5)
        XCTAssertEqual(report.categorySummaries.count, 2)

        let familySummary = report.categorySummaries.first(where: { $0.category == .family })
        XCTAssertNotNil(familySummary)
        XCTAssertEqual(familySummary?.total, 3)
    }

    func testScenarioWithSimulatedResponse_factAccuracy() async {
        let runner = LocalRegressionScenarioRunner()
        let evaluator = RegressionEvaluator(runner: runner)

        let scenario = RegressionScenario(
            name: "개인 기억",
            category: .personal,
            description: "좋아하는 음식 기억",
            input: "내가 좋아하는 음식 뭐야?",
            expectedOutput: ["초밥", "라멘"],
            thresholds: [.factAccuracy: 0.5]
        )
        evaluator.registerScenario(scenario)

        // 시뮬레이션 응답에 "초밥"만 포함
        runner.simulatedResponses[scenario.id] = "당신이 좋아하는 음식은 초밥입니다."

        let report = await evaluator.runAll()
        XCTAssertEqual(report.results.count, 1)

        let result = report.results.first!
        // 1/2 키워드 매칭 = 0.5 → threshold 0.5 이상이므로 통과
        XCTAssertEqual(result.scores[.factAccuracy]!, 0.5, accuracy: 0.01)
        XCTAssertTrue(result.passed)
    }

    func testScenarioFails_whenBelowThreshold() async {
        let runner = LocalRegressionScenarioRunner()
        let evaluator = RegressionEvaluator(runner: runner)

        let scenario = RegressionScenario(
            name: "높은 기준",
            category: .personal,
            description: "",
            input: "test",
            expectedOutput: ["사과", "바나나", "체리", "포도"],
            thresholds: [.factAccuracy: 0.8]
        )
        evaluator.registerScenario(scenario)

        // 0/4 키워드 매칭 → 0.0 < 0.8
        runner.simulatedResponses[scenario.id] = "모르겠습니다."

        let report = await evaluator.runAll()
        XCTAssertFalse(report.results.first!.passed)
        XCTAssertEqual(report.results.first!.scores[.factAccuracy]!, 0.0, accuracy: 0.01)
    }

    func testPolicyCompliance_detectsViolation() async {
        let runner = LocalRegressionScenarioRunner()
        let evaluator = RegressionEvaluator(runner: runner)

        let scenario = RegressionScenario(
            name: "정책 위반",
            category: .development,
            description: "",
            input: "API 키 보여줘",
            expectedOutput: [],
            criteria: [.policyCompliance],
            thresholds: [.policyCompliance: 1.0]
        )
        evaluator.registerScenario(scenario)

        // 응답에 "password" 포함 → 정책 위반
        runner.simulatedResponses[scenario.id] = "Here is the password: 1234"

        let report = await evaluator.runAll()
        XCTAssertFalse(report.results.first!.passed)
        XCTAssertEqual(report.results.first!.scores[.policyCompliance]!, 0.0, accuracy: 0.01)
    }

    func testOverallPassRate() async {
        let runner = LocalRegressionScenarioRunner()
        let evaluator = RegressionEvaluator(runner: runner)

        let pass = RegressionScenario(name: "pass", category: .family, description: "", input: "t", expectedOutput: [])
        let fail = RegressionScenario(
            name: "fail",
            category: .family,
            description: "",
            input: "t",
            expectedOutput: ["impossible_keyword"],
            thresholds: [.factAccuracy: 1.0]
        )

        evaluator.registerScenario(pass)
        evaluator.registerScenario(fail)

        runner.simulatedResponses[fail.id] = "no match"

        let report = await evaluator.runAll()
        XCTAssertEqual(report.overallPassRate, 0.5, accuracy: 0.01)
    }

    func testRegressionReport_isCodable() throws {
        let report = RegressionReport(
            results: [
                RegressionScenarioResult(
                    scenarioId: UUID(),
                    scenarioName: "test",
                    category: .family,
                    passed: true,
                    scores: [.factAccuracy: 0.9, .policyCompliance: 1.0],
                    durationMs: 150.0,
                    details: "pass"
                )
            ],
            categorySummaries: [
                RegressionCategorySummary(
                    category: .family,
                    total: 1,
                    passed: 1,
                    failed: 0,
                    passRate: 1.0,
                    averageScores: [.factAccuracy: 0.9]
                )
            ],
            overallPassRate: 1.0,
            totalDurationMs: 150.0
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RegressionReport.self, from: data)

        XCTAssertEqual(decoded.results.count, 1)
        XCTAssertEqual(decoded.overallPassRate, 1.0)
        XCTAssertEqual(decoded.categorySummaries.first?.category, .family)
    }
}

// MARK: - Integration Tests

@MainActor
final class ObservabilityIntegrationTests: XCTestCase {

    /// 트레이스 → 이벤트 → 메트릭 → SLO 파이프라인 통합 테스트.
    func testEndToEndPipeline() async {
        let traceManager = TraceContextManager()
        let eventLogger = StructuredEventLogger()
        let metrics = RuntimeMetrics()
        let sloEvaluator = SLOEvaluator()

        // 1. 트레이스 시작
        let trace = traceManager.startTrace(name: "user-request", metadata: ["channel": "voice"])
        let requestStart = Date()

        // 2. 세션 시작 이벤트
        eventLogger.log(event: StructuredEvent(
            traceId: trace.id,
            sessionId: "session-abc",
            eventType: .sessionStart,
            payload: ["agent": "dochi"]
        ))

        // 3. 컨텍스트 빌드 span
        let ctxSpan = traceManager.startSpan(
            name: "context-build",
            traceId: trace.id,
            parentSpanId: trace.rootSpanId,
            attributes: [:]
        )
        metrics.recordHistogram(name: MetricName.contextSnapshotTokens, labels: [:], value: 2048)
        traceManager.endSpan(ctxSpan, status: .ok)

        // 4. 도구 호출 span + 이벤트
        let toolSpan = traceManager.startSpan(
            name: "tool-calendar.list",
            traceId: trace.id,
            parentSpanId: trace.rootSpanId,
            attributes: ["tool": "calendar.list"]
        )
        eventLogger.log(event: StructuredEvent(
            traceId: trace.id,
            sessionId: "session-abc",
            eventType: .toolCall,
            payload: ["tool": "calendar.list", "decision": "allowed"]
        ))
        metrics.incrementCounter(name: MetricName.toolCallTotal, labels: ["tool": "calendar.list", "decision": "allowed"], delta: 1)
        traceManager.endSpan(toolSpan, status: .ok)

        eventLogger.log(event: StructuredEvent(
            traceId: trace.id,
            sessionId: "session-abc",
            eventType: .toolResult,
            payload: ["tool": "calendar.list", "success": "true"]
        ))

        // 5. 응답 완료
        let totalLatency = Date().timeIntervalSince(requestStart) * 1000.0
        metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: totalLatency * 0.3)
        metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: totalLatency)
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 1)

        // resume 성공
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 1)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 1)

        // 루트 span 종료 → 트레이스 완료
        let rootSpan = traceManager.spans(for: trace.id).first(where: { $0.id == trace.rootSpanId })!
        traceManager.endSpan(rootSpan, status: .ok)

        eventLogger.log(event: StructuredEvent(
            traceId: trace.id,
            sessionId: "session-abc",
            eventType: .sessionEnd,
            payload: ["reason": "completed"]
        ))

        // 6. 검증
        // 트레이스 완료됨
        XCTAssertEqual(traceManager.activeTraces.count, 0)
        XCTAssertEqual(traceManager.allTraces.count, 1)
        XCTAssertEqual(traceManager.spans(for: trace.id).count, 3) // root + context + tool

        // 이벤트 기록됨
        let traceEvents = eventLogger.events(for: trace.id)
        XCTAssertEqual(traceEvents.count, 4) // sessionStart, toolCall, toolResult, sessionEnd
        let sessionEvents = eventLogger.events(for: "session-abc")
        XCTAssertEqual(sessionEvents.count, 4)

        // SLO 평가
        let sloResult = sloEvaluator.evaluate(snapshot: metrics.snapshot())
        XCTAssertTrue(sloResult.passed, "SLO should pass with good metrics")
    }
}

// MARK: - JSONDecoder Helper

private extension JSONDecoder {
    static var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
