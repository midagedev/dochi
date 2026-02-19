import Foundation
import os

// MARK: - DeployGateCheckType

/// 배포 게이트 체크 항목 타입.
enum DeployGateCheckType: String, Sendable, Codable, CaseIterable {
    case unitTests
    case integrationTests
    case sloGate
    case regressionEvaluation
    case securityChecklist
}

// MARK: - DeployGateCheckResult

/// 개별 배포 게이트 체크 결과.
struct DeployGateCheckResult: Sendable, Codable, Identifiable {
    let id: UUID
    let check: DeployGateCheckType
    let passed: Bool
    let detail: String

    init(
        id: UUID = UUID(),
        check: DeployGateCheckType,
        passed: Bool,
        detail: String
    ) {
        self.id = id
        self.check = check
        self.passed = passed
        self.detail = detail
    }
}

// MARK: - DeployGateReport

/// 배포 게이트 전체 리포트.
struct DeployGateReport: Sendable, Codable {
    let timestamp: Date
    let results: [DeployGateCheckResult]
    let deployable: Bool

    var passCount: Int { results.filter(\.passed).count }
    var totalCount: Int { results.count }
    var failedChecks: [DeployGateCheckResult] { results.filter { !$0.passed } }
}

// MARK: - DeployGate

/// 배포 게이트 — 모든 체크 항목 통과 여부를 평가하여 배포 가능 여부 판정.
/// 체크 항목별 개별 평가를 제공하며 SLO 판정은 SLOEvaluator에 위임한다.
@MainActor
final class DeployGate {

    /// 모든 배포 게이트 체크를 실행하고 결과를 반환한다.
    func runAllChecks(
        metrics: RuntimeMetricsProtocol,
        sloEvaluator: SLOEvaluatorProtocol,
        unitTestsPassed: Bool,
        integrationTestsPassed: Bool,
        regressionReport: RegressionReport,
        securityChecksPassed: Bool
    ) -> DeployGateReport {
        var results: [DeployGateCheckResult] = []

        // 1. Unit tests
        results.append(DeployGateCheckResult(
            check: .unitTests,
            passed: unitTestsPassed,
            detail: unitTestsPassed ? "전체 단위 테스트 통과" : "단위 테스트 실패"
        ))

        // 2. Integration tests
        results.append(DeployGateCheckResult(
            check: .integrationTests,
            passed: integrationTestsPassed,
            detail: integrationTestsPassed ? "전체 통합 테스트 통과" : "통합 테스트 실패"
        ))

        // 3. SLO gate
        let sloResult = sloEvaluator.evaluate(snapshot: metrics.snapshot())
        let failedSLOs = sloResult.failedItems.map(\.name)
        results.append(DeployGateCheckResult(
            check: .sloGate,
            passed: sloResult.passed,
            detail: sloResult.passed
                ? "모든 SLO 충족"
                : "SLO 위반: \(failedSLOs.joined(separator: ", "))"
        ))

        // 4. Regression evaluation
        let regressionPassed = regressionReport.overallPassRate >= 1.0
        let failedIds = regressionReport.results.filter { !$0.passed }.map(\.scenarioName)
        results.append(DeployGateCheckResult(
            check: .regressionEvaluation,
            passed: regressionPassed,
            detail: regressionPassed
                ? "전체 회귀 시나리오 통과 (\(regressionReport.results.count)개)"
                : "회귀 실패: \(failedIds.joined(separator: ", "))"
        ))

        // 5. Security checklist
        results.append(DeployGateCheckResult(
            check: .securityChecklist,
            passed: securityChecksPassed,
            detail: securityChecksPassed ? "보안 점검 통과" : "보안 점검 실패"
        ))

        let deployable = results.allSatisfy(\.passed)

        let report = DeployGateReport(
            timestamp: Date(),
            results: results,
            deployable: deployable
        )

        if deployable {
            Log.runtime.info("Deploy gate: 모든 체크 통과, 배포 가능")
        } else {
            let failedNames = results.filter { !$0.passed }.map(\.check.rawValue)
            Log.runtime.warning("Deploy gate 차단: \(failedNames.joined(separator: ", "))")
        }

        return report
    }

    /// 사람이 읽을 수 있는 리포트 문자열을 생성한다.
    func formatReport(_ report: DeployGateReport) -> String {
        var lines: [String] = []
        lines.append("=== 배포 게이트 리포트 ===")
        lines.append("")

        for result in report.results {
            let icon = result.passed ? "PASS" : "FAIL"
            lines.append("[\(icon)] \(result.check.rawValue): \(result.detail)")
        }

        lines.append("")
        lines.append("결과: \(report.passCount)/\(report.totalCount) 통과")
        lines.append(report.deployable ? "상태: 배포 가능" : "상태: 배포 차단")

        return lines.joined(separator: "\n")
    }
}
