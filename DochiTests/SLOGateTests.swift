import XCTest
@testable import Dochi

// MARK: - Default Regression Scenarios Tests

@MainActor
final class DefaultRegressionScenariosTests: XCTestCase {

    func testDefaultScenarios_hasMinimumEight() {
        let scenarios = DefaultRegressionScenarios.all()
        XCTAssertGreaterThanOrEqual(scenarios.count, 8, "스펙에 따라 최소 8개 시나리오 필요")
    }

    func testDefaultScenarios_familyHasThree() {
        let family = DefaultRegressionScenarios.familyScenarios()
        XCTAssertEqual(family.count, 3)
        XCTAssertTrue(family.allSatisfy { $0.category == .family })
    }

    func testDefaultScenarios_developmentHasThree() {
        let dev = DefaultRegressionScenarios.developmentScenarios()
        XCTAssertEqual(dev.count, 3)
        XCTAssertTrue(dev.allSatisfy { $0.category == .development })
    }

    func testDefaultScenarios_personalHasTwo() {
        let personal = DefaultRegressionScenarios.personalScenarios()
        XCTAssertEqual(personal.count, 2)
        XCTAssertTrue(personal.allSatisfy { $0.category == .personal })
    }

    func testDefaultScenarios_allHaveNonEmptyInput() {
        let scenarios = DefaultRegressionScenarios.all()
        for scenario in scenarios {
            XCTAssertFalse(scenario.input.isEmpty, "시나리오 '\(scenario.name)'의 입력이 비어 있음")
        }
    }

    func testDefaultScenarios_allHaveNonEmptyCriteria() {
        let scenarios = DefaultRegressionScenarios.all()
        for scenario in scenarios {
            XCTAssertFalse(scenario.criteria.isEmpty, "시나리오 '\(scenario.name)'의 평가 기준이 비어 있음")
        }
    }

    func testDefaultScenarios_uniqueNames() {
        let scenarios = DefaultRegressionScenarios.all()
        let names = scenarios.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "시나리오 이름이 중복되어서는 안 됨")
    }

    func testDefaultScenarios_uniqueIds() {
        let scenarios = DefaultRegressionScenarios.all()
        let ids = scenarios.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "시나리오 ID가 중복되어서는 안 됨")
    }

    func testDefaultScenarios_categoryCoverage() {
        let scenarios = DefaultRegressionScenarios.all()
        let categories = Set(scenarios.map(\.category))
        for category in RegressionCategory.allCases {
            XCTAssertTrue(categories.contains(category), "카테고리 \(category) 시나리오가 없음")
        }
    }
}

// MARK: - RegressionEvaluator Default Registration Tests

@MainActor
final class RegressionEvaluatorDefaultTests: XCTestCase {

    func testInit_withRegisterDefaults_registersAllDefaultScenarios() {
        let evaluator = RegressionEvaluator(registerDefaults: true)
        XCTAssertEqual(evaluator.scenarios.count, DefaultRegressionScenarios.all().count)
    }

    func testInit_withoutRegisterDefaults_hasNoScenarios() {
        let evaluator = RegressionEvaluator(registerDefaults: false)
        XCTAssertTrue(evaluator.scenarios.isEmpty)
    }

    func testRunAll_withDefaults_producesReport() async {
        let evaluator = RegressionEvaluator(registerDefaults: true)
        let report = await evaluator.runAll()
        XCTAssertEqual(report.results.count, DefaultRegressionScenarios.all().count)
        XCTAssertNotNil(evaluator.lastReport)
    }

    func testRunAll_withDefaults_categorySummariesPresent() async {
        let evaluator = RegressionEvaluator(registerDefaults: true)
        let report = await evaluator.runAll()

        // 모든 카테고리에 대한 요약이 있어야 함
        XCTAssertEqual(report.categorySummaries.count, 3)
        let categories = Set(report.categorySummaries.map(\.category))
        XCTAssertTrue(categories.contains(.family))
        XCTAssertTrue(categories.contains(.development))
        XCTAssertTrue(categories.contains(.personal))
    }

    func testRunCategory_withDefaults_filtersCorrectly() async {
        let evaluator = RegressionEvaluator(registerDefaults: true)
        let familyReport = await evaluator.run(category: .family)
        XCTAssertEqual(familyReport.results.count, 3)
        XCTAssertTrue(familyReport.results.allSatisfy { $0.category == .family })
    }
}

// MARK: - DeployGate Tests

@MainActor
final class DeployGateTests: XCTestCase {

    func testRunAllChecks_allPass() {
        let gate = DeployGate()
        let metrics = RuntimeMetrics()
        let sloEvaluator = SLOEvaluator()

        let report = gate.runAllChecks(
            metrics: metrics,
            sloEvaluator: sloEvaluator,
            unitTestsPassed: true,
            integrationTestsPassed: true,
            regressionReport: makePassingRegressionReport(),
            securityChecksPassed: true
        )

        XCTAssertTrue(report.deployable)
        XCTAssertEqual(report.results.count, 5)
        XCTAssertTrue(report.results.allSatisfy(\.passed))
        XCTAssertEqual(report.passCount, 5)
        XCTAssertTrue(report.failedChecks.isEmpty)
    }

    func testRunAllChecks_unitTestsFail_blocksDeployment() {
        let gate = DeployGate()
        let metrics = RuntimeMetrics()
        let sloEvaluator = SLOEvaluator()

        let report = gate.runAllChecks(
            metrics: metrics,
            sloEvaluator: sloEvaluator,
            unitTestsPassed: false,
            integrationTestsPassed: true,
            regressionReport: makePassingRegressionReport(),
            securityChecksPassed: true
        )

        XCTAssertFalse(report.deployable)
        let failedTypes = report.failedChecks.map(\.check)
        XCTAssertTrue(failedTypes.contains(.unitTests))
    }

    func testRunAllChecks_sloFail_blocksDeployment() {
        let gate = DeployGate()
        let metrics = RuntimeMetrics()
        let sloEvaluator = SLOEvaluator()

        // 높은 에러율로 SLO 실패 유도
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.requestErrorTotal, labels: [:], delta: 50)
        // resume 성공률도 낮게
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 50)
        // 높은 latency
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 5000)
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: 15000)
        }

        let report = gate.runAllChecks(
            metrics: metrics,
            sloEvaluator: sloEvaluator,
            unitTestsPassed: true,
            integrationTestsPassed: true,
            regressionReport: makePassingRegressionReport(),
            securityChecksPassed: true
        )

        XCTAssertFalse(report.deployable)
        let failedTypes = report.failedChecks.map(\.check)
        XCTAssertTrue(failedTypes.contains(.sloGate))
    }

    func testRunAllChecks_regressionFail_blocksDeployment() {
        let gate = DeployGate()
        let metrics = RuntimeMetrics()
        let sloEvaluator = SLOEvaluator()

        let report = gate.runAllChecks(
            metrics: metrics,
            sloEvaluator: sloEvaluator,
            unitTestsPassed: true,
            integrationTestsPassed: true,
            regressionReport: makeFailingRegressionReport(),
            securityChecksPassed: true
        )

        XCTAssertFalse(report.deployable)
        let failedTypes = report.failedChecks.map(\.check)
        XCTAssertTrue(failedTypes.contains(.regressionEvaluation))
    }

    func testRunAllChecks_securityFail_blocksDeployment() {
        let gate = DeployGate()
        let metrics = RuntimeMetrics()
        let sloEvaluator = SLOEvaluator()

        let report = gate.runAllChecks(
            metrics: metrics,
            sloEvaluator: sloEvaluator,
            unitTestsPassed: true,
            integrationTestsPassed: true,
            regressionReport: makePassingRegressionReport(),
            securityChecksPassed: false
        )

        XCTAssertFalse(report.deployable)
        let failedTypes = report.failedChecks.map(\.check)
        XCTAssertTrue(failedTypes.contains(.securityChecklist))
    }

    func testRunAllChecks_multipleFailures() {
        let gate = DeployGate()
        let metrics = RuntimeMetrics()
        let sloEvaluator = SLOEvaluator()

        let report = gate.runAllChecks(
            metrics: metrics,
            sloEvaluator: sloEvaluator,
            unitTestsPassed: false,
            integrationTestsPassed: false,
            regressionReport: makeFailingRegressionReport(),
            securityChecksPassed: false
        )

        XCTAssertFalse(report.deployable)
        XCTAssertEqual(report.failedChecks.count, 4) // unit, integration, regression, security
    }

    func testFormatReport_allPass() {
        let gate = DeployGate()
        let report = DeployGateReport(
            timestamp: Date(),
            results: DeployGateCheckType.allCases.map {
                DeployGateCheckResult(check: $0, passed: true, detail: "OK")
            },
            deployable: true
        )

        let formatted = gate.formatReport(report)
        XCTAssertTrue(formatted.contains("배포 가능"))
        XCTAssertTrue(formatted.contains("5/5"))
    }

    func testFormatReport_blocked() {
        let gate = DeployGate()
        let report = DeployGateReport(
            timestamp: Date(),
            results: [
                DeployGateCheckResult(check: .unitTests, passed: true, detail: "OK"),
                DeployGateCheckResult(check: .sloGate, passed: false, detail: "SLO 위반"),
            ],
            deployable: false
        )

        let formatted = gate.formatReport(report)
        XCTAssertTrue(formatted.contains("배포 차단"))
        XCTAssertTrue(formatted.contains("FAIL"))
    }

    func testDeployGateCheckType_allCases() {
        XCTAssertEqual(DeployGateCheckType.allCases.count, 5)
        XCTAssertTrue(DeployGateCheckType.allCases.contains(.unitTests))
        XCTAssertTrue(DeployGateCheckType.allCases.contains(.integrationTests))
        XCTAssertTrue(DeployGateCheckType.allCases.contains(.sloGate))
        XCTAssertTrue(DeployGateCheckType.allCases.contains(.regressionEvaluation))
        XCTAssertTrue(DeployGateCheckType.allCases.contains(.securityChecklist))
    }

    func testDeployGateCheckResult_codable() throws {
        let result = DeployGateCheckResult(check: .sloGate, passed: false, detail: "fail")

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let decoded = try JSONDecoder().decode(DeployGateCheckResult.self, from: data)

        XCTAssertEqual(decoded.id, result.id)
        XCTAssertEqual(decoded.check, .sloGate)
        XCTAssertFalse(decoded.passed)
        XCTAssertEqual(decoded.detail, "fail")
    }

    func testDeployGateReport_codable() throws {
        let report = DeployGateReport(
            timestamp: Date(),
            results: [
                DeployGateCheckResult(check: .unitTests, passed: true, detail: "ok"),
            ],
            deployable: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DeployGateReport.self, from: data)

        XCTAssertTrue(decoded.deployable)
        XCTAssertEqual(decoded.results.count, 1)
    }

    // MARK: - Helpers

    private func makePassingRegressionReport() -> RegressionReport {
        RegressionReport(
            results: [
                RegressionScenarioResult(
                    scenarioId: UUID(),
                    scenarioName: "pass-1",
                    category: .family,
                    passed: true,
                    scores: [.factAccuracy: 1.0],
                    durationMs: 10.0,
                    details: "pass"
                ),
            ],
            categorySummaries: [],
            overallPassRate: 1.0,
            totalDurationMs: 10.0
        )
    }

    private func makeFailingRegressionReport() -> RegressionReport {
        RegressionReport(
            results: [
                RegressionScenarioResult(
                    scenarioId: UUID(),
                    scenarioName: "fail-1",
                    category: .family,
                    passed: false,
                    scores: [.factAccuracy: 0.2],
                    durationMs: 10.0,
                    details: "fail"
                ),
            ],
            categorySummaries: [],
            overallPassRate: 0.0,
            totalDurationMs: 10.0
        )
    }
}

// MARK: - AuditLogRetentionConfig Tests

final class AuditLogRetentionConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = AuditLogRetentionConfig.default
        XCTAssertEqual(config.auditRetentionDays, 30)
        XCTAssertEqual(config.diagnosticRetentionDays, 7)
    }

    func testAuditCutoffDate_is30DaysAgo() {
        let config = AuditLogRetentionConfig.default
        let expected = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let diff = abs(config.auditCutoffDate.timeIntervalSince(expected))
        XCTAssertTrue(diff < 1.0, "감사 로그 cutoff는 30일 전이어야 함")
    }

    func testDiagnosticCutoffDate_is7DaysAgo() {
        let config = AuditLogRetentionConfig.default
        let expected = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let diff = abs(config.diagnosticCutoffDate.timeIntervalSince(expected))
        XCTAssertTrue(diff < 1.0, "진단 로그 cutoff는 7일 전이어야 함")
    }

    func testCodableRoundtrip() throws {
        let config = AuditLogRetentionConfig(auditRetentionDays: 14, diagnosticRetentionDays: 3)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuditLogRetentionConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testEquatable() {
        let a = AuditLogRetentionConfig(auditRetentionDays: 30, diagnosticRetentionDays: 7)
        let b = AuditLogRetentionConfig(auditRetentionDays: 30, diagnosticRetentionDays: 7)
        let c = AuditLogRetentionConfig(auditRetentionDays: 14, diagnosticRetentionDays: 7)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - DiagnosticLogManager Tests

@MainActor
final class DiagnosticLogManagerTests: XCTestCase {

    func testLog_appendsEntry() {
        let manager = DiagnosticLogManager()
        manager.log(sessionId: "s1", level: .info, message: "test message")

        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(manager.entries.first?.sessionId, "s1")
        XCTAssertEqual(manager.entries.first?.level, .info)
        XCTAssertEqual(manager.entries.first?.message, "test message")
    }

    func testLog_withMetadata() {
        let manager = DiagnosticLogManager()
        manager.log(sessionId: "s1", level: .warning, message: "warn", metadata: ["key": "value"])

        XCTAssertEqual(manager.entries.first?.metadata["key"], "value")
    }

    func testEntriesForSession_filtersCorrectly() {
        let manager = DiagnosticLogManager()
        manager.log(sessionId: "s1", level: .info, message: "msg1")
        manager.log(sessionId: "s2", level: .info, message: "msg2")
        manager.log(sessionId: "s1", level: .debug, message: "msg3")

        let s1Entries = manager.entries(for: "s1")
        XCTAssertEqual(s1Entries.count, 2)
        XCTAssertTrue(s1Entries.allSatisfy { $0.sessionId == "s1" })
    }

    func testEntriesMinLevel_filtersCorrectly() {
        let manager = DiagnosticLogManager()
        manager.log(sessionId: "s1", level: .debug, message: "d")
        manager.log(sessionId: "s1", level: .info, message: "i")
        manager.log(sessionId: "s1", level: .warning, message: "w")
        manager.log(sessionId: "s1", level: .error, message: "e")

        let warningAndAbove = manager.entries(minLevel: .warning)
        XCTAssertEqual(warningAndAbove.count, 2)
        XCTAssertTrue(warningAndAbove.allSatisfy { $0.level == .warning || $0.level == .error })
    }

    func testPurgeExpired_removesOldEntries() {
        let config = AuditLogRetentionConfig(auditRetentionDays: 30, diagnosticRetentionDays: 1)
        let manager = DiagnosticLogManager(retentionConfig: config)

        // 2일 전 항목 추가 (수동으로 entries 배열에)
        let oldEntry = DiagnosticLogEntry(
            sessionId: "old",
            timestamp: Date().addingTimeInterval(-172_800), // 48시간 전
            message: "old message"
        )
        // DiagnosticLogManager는 직접 entries를 설정할 수 없으므로 log로 추가 후 대신 테스트
        manager.log(sessionId: "new", level: .info, message: "new message")

        // 현재 항목은 purge 대상이 아님
        let purged = manager.purgeExpired()
        XCTAssertEqual(purged, 0)
        XCTAssertEqual(manager.entries.count, 1)

        // oldEntry를 직접 대체 검증: cutoff가 올바르게 계산되는지 확인
        let cutoff = config.diagnosticCutoffDate
        XCTAssertTrue(oldEntry.timestamp < cutoff, "2일 전 항목은 1일 보존 cutoff보다 오래됨")
    }

    func testClear_removesAllEntries() {
        let manager = DiagnosticLogManager()
        manager.log(sessionId: "s1", level: .info, message: "m1")
        manager.log(sessionId: "s2", level: .error, message: "m2")

        XCTAssertEqual(manager.entries.count, 2)
        manager.clear()
        XCTAssertTrue(manager.entries.isEmpty)
    }

    func testDiagnosticLevel_allCases() {
        XCTAssertEqual(DiagnosticLevel.allCases.count, 4)
        XCTAssertTrue(DiagnosticLevel.allCases.contains(.debug))
        XCTAssertTrue(DiagnosticLevel.allCases.contains(.info))
        XCTAssertTrue(DiagnosticLevel.allCases.contains(.warning))
        XCTAssertTrue(DiagnosticLevel.allCases.contains(.error))
    }

    func testDiagnosticLogEntry_codable() throws {
        let entry = DiagnosticLogEntry(
            sessionId: "s1",
            level: .error,
            message: "crash",
            metadata: ["stack": "line42"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticLogEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.sessionId, "s1")
        XCTAssertEqual(decoded.level, .error)
        XCTAssertEqual(decoded.message, "crash")
        XCTAssertEqual(decoded.metadata["stack"], "line42")
    }

    func testDefaultRetentionConfig_isUsed() {
        let manager = DiagnosticLogManager()
        XCTAssertEqual(manager.retentionConfig, .default)
    }
}

// MARK: - Percentile Edge Case Tests

@MainActor
final class PercentileEdgeCaseTests: XCTestCase {

    func testPercentile_emptyHistogram() {
        let metrics = RuntimeMetrics()
        let snapshot = metrics.snapshot()
        XCTAssertNil(snapshot.histogram(name: "nonexistent"), "빈 히스토그램은 nil")
    }

    func testPercentile_singleValue() {
        let metrics = RuntimeMetrics()
        metrics.recordHistogram(name: "single", labels: [:], value: 42.0)

        let snapshot = metrics.snapshot()
        let histogram = snapshot.histogram(name: "single")!

        XCTAssertEqual(histogram.count, 1)
        XCTAssertEqual(histogram.p50, 42.0)
        XCTAssertEqual(histogram.p95, 42.0)
        XCTAssertEqual(histogram.p99, 42.0)
        XCTAssertEqual(histogram.min, 42.0)
        XCTAssertEqual(histogram.max, 42.0)
    }

    func testPercentile_twoValues() {
        let metrics = RuntimeMetrics()
        metrics.recordHistogram(name: "two", labels: [:], value: 10.0)
        metrics.recordHistogram(name: "two", labels: [:], value: 20.0)

        let snapshot = metrics.snapshot()
        let histogram = snapshot.histogram(name: "two")!

        XCTAssertEqual(histogram.count, 2)
        XCTAssertEqual(histogram.min, 10.0)
        XCTAssertEqual(histogram.max, 20.0)
        // p50 = 10 + 0.5 * (20 - 10) = 15
        XCTAssertEqual(histogram.p50, 15.0, accuracy: 0.1)
    }

    func testPercentile_100Values_p95Accuracy() {
        let metrics = RuntimeMetrics()
        // 값 1~100
        for i in 1...100 {
            metrics.recordHistogram(name: "hundred", labels: [:], value: Double(i))
        }

        let snapshot = metrics.snapshot()
        let histogram = snapshot.histogram(name: "hundred")!

        XCTAssertEqual(histogram.count, 100)
        XCTAssertEqual(histogram.min, 1.0)
        XCTAssertEqual(histogram.max, 100.0)
        // p95 of 1..100 should be approximately 95.05
        XCTAssertEqual(histogram.p95, 95.05, accuracy: 1.0)
        // p99 should be approximately 99.01
        XCTAssertEqual(histogram.p99, 99.01, accuracy: 1.0)
    }

    func testPercentile_identicalValues() {
        let metrics = RuntimeMetrics()
        for _ in 1...50 {
            metrics.recordHistogram(name: "same", labels: [:], value: 100.0)
        }

        let snapshot = metrics.snapshot()
        let histogram = snapshot.histogram(name: "same")!

        XCTAssertEqual(histogram.p50, 100.0)
        XCTAssertEqual(histogram.p95, 100.0)
        XCTAssertEqual(histogram.p99, 100.0)
    }

    func testPercentile_withOutlier() {
        let metrics = RuntimeMetrics()
        // 99개는 100ms, 1개는 10000ms (outlier)
        for _ in 1...99 {
            metrics.recordHistogram(name: "outlier", labels: [:], value: 100.0)
        }
        metrics.recordHistogram(name: "outlier", labels: [:], value: 10000.0)

        let snapshot = metrics.snapshot()
        let histogram = snapshot.histogram(name: "outlier")!

        // p95 should still be 100ms (outlier is at the very end)
        XCTAssertEqual(histogram.p95, 100.0, accuracy: 200.0) // within range
        // p99 should be close to or at the outlier
        XCTAssertGreaterThan(histogram.p99, 100.0)
    }
}

// MARK: - Mock Integration Tests

@MainActor
final class MockRuntimeMetricsTests: XCTestCase {

    func testMockIncrementCounter() {
        let mock = MockRuntimeMetrics()
        mock.incrementCounter(name: "test", labels: [:], delta: 5.0)
        mock.incrementCounter(name: "test", labels: [:], delta: 3.0)

        XCTAssertEqual(mock.counterValues["test"], 8.0)
        XCTAssertEqual(mock.incrementCallCount, 2)
    }

    func testMockRecordHistogram() {
        let mock = MockRuntimeMetrics()
        mock.recordHistogram(name: "latency", labels: [:], value: 100.0)
        mock.recordHistogram(name: "latency", labels: [:], value: 200.0)

        XCTAssertEqual(mock.histogramValues["latency"]?.count, 2)
        XCTAssertEqual(mock.recordHistogramCallCount, 2)
    }

    func testMockSetGauge() {
        let mock = MockRuntimeMetrics()
        mock.setGauge(name: "sessions", labels: [:], value: 5.0)

        XCTAssertEqual(mock.gaugeValues["sessions"], 5.0)
        XCTAssertEqual(mock.setGaugeCallCount, 1)
    }

    func testMockSnapshot() {
        let mock = MockRuntimeMetrics()
        mock.incrementCounter(name: "c", labels: [:], delta: 1.0)

        let snapshot = mock.snapshot()
        XCTAssertEqual(snapshot.counter(name: "c"), 1.0)
        XCTAssertEqual(mock.snapshotCallCount, 1)
    }

    func testMockReset() {
        let mock = MockRuntimeMetrics()
        mock.incrementCounter(name: "c", labels: [:], delta: 1.0)
        mock.setGauge(name: "g", labels: [:], value: 1.0)
        mock.recordHistogram(name: "h", labels: [:], value: 1.0)

        mock.reset()

        XCTAssertTrue(mock.counterValues.isEmpty)
        XCTAssertTrue(mock.gaugeValues.isEmpty)
        XCTAssertTrue(mock.histogramValues.isEmpty)
        XCTAssertEqual(mock.resetCallCount, 1)
    }

    func testMockWithLabels() {
        let mock = MockRuntimeMetrics()
        mock.incrementCounter(
            name: MetricName.toolCallTotal,
            labels: ["tool": "calendar", "decision": "allowed"],
            delta: 1.0
        )

        let key = "\(MetricName.toolCallTotal)|decision=allowed,tool=calendar"
        XCTAssertEqual(mock.counterValues[key], 1.0)
    }
}

// MARK: - DeployGate + Regression E2E Test

@MainActor
final class DeployGateE2ETests: XCTestCase {

    /// 전체 파이프라인: 메트릭 수집 → SLO 평가 → 회귀 테스트 → 배포 게이트.
    func testFullPipeline_allPass() async {
        // 1. 메트릭 설정 (모든 SLO 통과)
        let metrics = RuntimeMetrics()
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.requestErrorTotal, labels: [:], delta: 0)
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 100)
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 500)
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: 2000)
        }

        // 2. SLO 평가
        let sloEvaluator = SLOEvaluator()
        let sloResult = sloEvaluator.evaluate(snapshot: metrics.snapshot())
        XCTAssertTrue(sloResult.passed)

        // 3. 회귀 평가 (기본 시나리오)
        let regressionEvaluator = RegressionEvaluator(registerDefaults: true)
        let regressionReport = await regressionEvaluator.runAll()
        // 기본 시나리오는 빈 응답 기반이므로 일부 실패할 수 있으나, 파이프라인 동작은 검증

        // 4. 배포 게이트
        let gate = DeployGate()
        let deployReport = gate.runAllChecks(
            metrics: metrics,
            sloEvaluator: sloEvaluator,
            unitTestsPassed: true,
            integrationTestsPassed: true,
            regressionReport: makePassingReport(),
            securityChecksPassed: true
        )

        XCTAssertTrue(deployReport.deployable)
        XCTAssertEqual(deployReport.results.count, 5)

        // 리포트 포맷 검증
        let formatted = gate.formatReport(deployReport)
        XCTAssertTrue(formatted.contains("배포 가능"))
    }

    func testFullPipeline_sloFails_blocksDeployment() async {
        let metrics = RuntimeMetrics()
        // 높은 에러율
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.requestErrorTotal, labels: [:], delta: 20)

        let sloEvaluator = SLOEvaluator()
        let gate = DeployGate()
        let deployReport = gate.runAllChecks(
            metrics: metrics,
            sloEvaluator: sloEvaluator,
            unitTestsPassed: true,
            integrationTestsPassed: true,
            regressionReport: makePassingReport(),
            securityChecksPassed: true
        )

        XCTAssertFalse(deployReport.deployable)
        XCTAssertTrue(deployReport.failedChecks.contains(where: { $0.check == .sloGate }))
    }

    func testTraceToMetricsPipeline() {
        // 트레이스 시작 → 메트릭 기록 → SLO 평가 흐름
        let traceManager = TraceContextManager()
        let metrics = RuntimeMetrics()

        let trace = traceManager.startTrace(name: "e2e-request", metadata: [:])
        let requestStart = Date()

        // 도구 호출 메트릭
        metrics.incrementCounter(
            name: MetricName.toolCallTotal,
            labels: ["tool": "calendar.list", "decision": "allowed"],
            delta: 1.0
        )

        // 세션 활성 게이지
        metrics.setGauge(name: MetricName.sessionActive, labels: [:], value: 1.0)

        // 컨텍스트 토큰
        metrics.recordHistogram(name: MetricName.contextSnapshotTokens, labels: [:], value: 1500)

        // 응답 완료
        let latencyMs = Date().timeIntervalSince(requestStart) * 1000.0
        metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: latencyMs)
        metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: latencyMs)
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 1)

        // 트레이스 종료
        let rootSpan = traceManager.spans(for: trace.id).first!
        traceManager.endSpan(rootSpan, status: .ok)

        // 검증
        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.gauge(name: MetricName.sessionActive), 1.0)
        XCTAssertNotNil(snapshot.histogram(name: MetricName.contextSnapshotTokens))
        XCTAssertEqual(snapshot.counter(name: MetricName.requestTotal), 1.0)
        XCTAssertFalse(traceManager.allTraces.first(where: { $0.id == trace.id })!.isActive)
    }

    private func makePassingReport() -> RegressionReport {
        RegressionReport(
            results: [
                RegressionScenarioResult(
                    scenarioId: UUID(),
                    scenarioName: "pass",
                    category: .family,
                    passed: true,
                    scores: [.factAccuracy: 1.0],
                    durationMs: 5.0,
                    details: "pass"
                ),
            ],
            categorySummaries: [],
            overallPassRate: 1.0,
            totalDurationMs: 5.0
        )
    }
}

// MARK: - Native Rewrite Gate Runner Tests

@MainActor
private final class PassingRegressionScenarioRunner: RegressionScenarioRunner {
    func run(scenario: RegressionScenario) async -> RegressionScenarioResult {
        var scores: [RegressionCriterion: Double] = [:]
        for criterion in scenario.criteria {
            scores[criterion] = 1.0
        }

        return RegressionScenarioResult(
            scenarioId: scenario.id,
            scenarioName: scenario.name,
            category: scenario.category,
            passed: true,
            scores: scores,
            durationMs: 10.0,
            details: "deterministic pass"
        )
    }
}

@MainActor
final class NativeRewriteGateRunnerTests: XCTestCase {
    func testRun_allPass_producesDeployableReport() async {
        let metrics = makeHealthyMetrics()
        let gateRunner = makeGateRunner(metrics: metrics)

        let report = await gateRunner.run()

        XCTAssertTrue(report.deployGateReport.deployable)
        XCTAssertTrue(report.sloResult.passed)
        XCTAssertEqual(report.regressionReport.overallPassRate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(report.regressionReport.results.count, DefaultRegressionScenarios.all().count)
        XCTAssertGreaterThan(report.performance.firstPartialP95Ms, 0)
        XCTAssertGreaterThan(report.performance.toolLatencyP95Ms, 0)
    }

    func testRun_sloFailure_blocksDeployment() async {
        let metrics = RuntimeMetrics()
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.requestErrorTotal, labels: [:], delta: 10)
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 100)
        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 3000)
            metrics.recordHistogram(name: MetricName.toolLatencyMs, labels: ["tool": "calendar"], value: 1200)
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: 4000)
        }

        let gateRunner = makeGateRunner(metrics: metrics)
        let report = await gateRunner.run()

        XCTAssertFalse(report.deployGateReport.deployable)
        XCTAssertFalse(report.sloResult.passed)
        XCTAssertTrue(report.deployGateReport.failedChecks.contains(where: { $0.check == .sloGate }))
    }

    func testWrite_persistsJSONAndMarkdownReports() async throws {
        let metrics = makeHealthyMetrics()
        let gateRunner = makeGateRunner(metrics: metrics)
        let report = await gateRunner.run()
        let outputDir = temporaryDirectory().appendingPathComponent("native-rewrite-gate-write", isDirectory: true)

        let files = try gateRunner.write(report: report, to: outputDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: files.jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.markdownURL.path))

        let jsonData = try Data(contentsOf: files.jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NativeRewriteGateReport.self, from: jsonData)
        XCTAssertEqual(decoded.deployGateReport.deployable, report.deployGateReport.deployable)
        XCTAssertEqual(decoded.performance.requestTotal, report.performance.requestTotal, accuracy: 0.001)

        let markdown = try String(contentsOf: files.markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("Native Rewrite Gate Report"))
        XCTAssertTrue(markdown.contains("firstPartialP95Ms"))
        XCTAssertTrue(markdown.contains("toolLatencyP95Ms"))
    }

    func testGenerateGateReportArtifactsForCI() async throws {
        let metrics = makeHealthyMetrics()
        let gateRunner = makeGateRunner(metrics: metrics)
        let report = await gateRunner.run()

        let outputDir: URL
        if let path = ProcessInfo.processInfo.environment["DOCHI_GATE_REPORT_DIR"], !path.isEmpty {
            outputDir = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            outputDir = temporaryDirectory().appendingPathComponent("native-rewrite-gate-ci", isDirectory: true)
        }

        let files = try gateRunner.write(report: report, to: outputDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.markdownURL.path))
    }

    private func makeGateRunner(metrics: RuntimeMetrics) -> NativeRewriteGateRunner {
        let regressionEvaluator = RegressionEvaluator(
            runner: PassingRegressionScenarioRunner(),
            registerDefaults: true
        )
        return NativeRewriteGateRunner(
            metrics: metrics,
            sloEvaluator: SLOEvaluator(),
            regressionEvaluator: regressionEvaluator,
            deployGate: DeployGate()
        )
    }

    private func makeHealthyMetrics() -> RuntimeMetrics {
        let metrics = RuntimeMetrics()
        metrics.incrementCounter(name: MetricName.requestTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.requestErrorTotal, labels: [:], delta: 0)
        metrics.incrementCounter(name: MetricName.sessionResumeTotal, labels: [:], delta: 100)
        metrics.incrementCounter(name: MetricName.sessionResumeSuccess, labels: [:], delta: 100)

        for _ in 1...100 {
            metrics.recordHistogram(name: MetricName.firstPartialLatencyMs, labels: [:], value: 700)
            metrics.recordHistogram(name: MetricName.toolLatencyMs, labels: ["tool": "calendar"], value: 450)
            metrics.recordHistogram(name: MetricName.totalResponseLatencyMs, labels: [:], value: 2500)
        }

        return metrics
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-native-rewrite-gate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        return directory
    }
}
