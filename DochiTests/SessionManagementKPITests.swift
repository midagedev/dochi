import XCTest
@testable import Dochi

final class SessionManagementKPITests: XCTestCase {

    func testBuildSessionManagementKPIReportCalculatesAllFiveMetrics() {
        let counters = SessionManagementKPICounters(
            repositoryAssignedCount: 9,
            repositoryTotalCount: 12,
            dedupCandidateCount: 20,
            dedupCorrectionCount: 5,
            selectionAttemptCount: 8,
            selectionFailureCount: 2,
            historySearchQueryCount: 10,
            historySearchHitCount: 7,
            activityFeedbackSampleCount: 6,
            activityFeedbackMatchedCount: 5,
            activityStateDistribution: ["active": 4, "idle": 3, "stale": 2, "dead": 1]
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let report = ExternalToolSessionManager.buildSessionManagementKPIReport(from: counters, now: now)

        XCTAssertEqual(report.generatedAt, now)
        XCTAssertEqual(report.repositoryAssignmentSuccessRate, 0.75, accuracy: 0.0001)
        XCTAssertEqual(report.dedupCorrectionRate, 0.25, accuracy: 0.0001)
        XCTAssertNotNil(report.activityClassificationAccuracy)
        XCTAssertEqual(report.activityClassificationAccuracy ?? 0, 5.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(report.sessionSelectionFailureRate, 0.25, accuracy: 0.0001)
        XCTAssertEqual(report.historySearchHitRate, 0.7, accuracy: 0.0001)
        XCTAssertEqual(report.counters.activityStateDistribution["active"], 4)
    }

    func testBuildSessionManagementKPIReportAllowsNilActivityAccuracyWithoutFeedback() {
        let counters = SessionManagementKPICounters(
            repositoryAssignedCount: 0,
            repositoryTotalCount: 0,
            dedupCandidateCount: 0,
            dedupCorrectionCount: 0,
            selectionAttemptCount: 0,
            selectionFailureCount: 0,
            historySearchQueryCount: 0,
            historySearchHitCount: 0,
            activityFeedbackSampleCount: 0,
            activityFeedbackMatchedCount: 0,
            activityStateDistribution: [:]
        )

        let report = ExternalToolSessionManager.buildSessionManagementKPIReport(from: counters)

        XCTAssertNil(report.activityClassificationAccuracy)
        XCTAssertEqual(report.repositoryAssignmentSuccessRate, 0)
        XCTAssertEqual(report.dedupCorrectionRate, 0)
        XCTAssertEqual(report.sessionSelectionFailureRate, 0)
        XCTAssertEqual(report.historySearchHitRate, 0)
    }

    func testIsSelectionFailureFollowsRunnableActions() {
        let success = OrchestrationSessionSelection(
            action: .reuseT0Active,
            reason: "ok",
            repositoryRoot: nil,
            selectedSession: nil
        )
        let failure = OrchestrationSessionSelection(
            action: .createT0,
            reason: "needs new session",
            repositoryRoot: "/tmp/repo",
            selectedSession: nil
        )

        XCTAssertFalse(ExternalToolSessionManager.isSelectionFailure(success))
        XCTAssertTrue(ExternalToolSessionManager.isSelectionFailure(failure))
    }
}
