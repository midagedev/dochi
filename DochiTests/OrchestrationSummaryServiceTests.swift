import XCTest
@testable import Dochi

final class OrchestrationSummaryServiceTests: XCTestCase {

    func testSummarizeReturnsUnknownWhenOutputIsEmpty() {
        let service = OrchestrationSummaryService()

        let summary = service.summarize(outputLines: [])

        XCTAssertEqual(summary.resultKind, .unknown)
        XCTAssertEqual(summary.highlights, [])
        XCTAssertEqual(summary.summary, "최근 출력이 없어 작업 결과를 판별할 수 없습니다.")
        XCTAssertEqual(summary.contextReflection.conversationSummary, "[external-cli:unknown] 최근 출력이 없어 작업 결과를 판별할 수 없습니다.")
        XCTAssertEqual(summary.contextReflection.memoryCandidate, "")
    }

    func testSummarizePrefersFailureWhenBothSignalsExist() {
        let service = OrchestrationSummaryService()
        let output = [
            "build completed successfully",
            "error: failed to compile runtime bridge",
        ]

        let summary = service.summarize(outputLines: output)

        XCTAssertEqual(summary.resultKind, .failed)
        XCTAssertEqual(summary.highlights, output)
        XCTAssertTrue(summary.summary.contains("실패 신호가 감지되었습니다."))
    }

    func testSummarizeReturnsRunningWhenNoSuccessOrFailureKeyword() {
        let service = OrchestrationSummaryService()
        let output = [
            "processing step 1/4",
            "still working on indexing",
        ]

        let summary = service.summarize(outputLines: output)

        XCTAssertEqual(summary.resultKind, .running)
        XCTAssertEqual(summary.highlights, ["still working on indexing"])
        XCTAssertTrue(summary.summary.contains("진행 중이거나 최종 상태가 불명확합니다."))
    }

    func testSummarizeAllowsCustomPolicyKeywords() {
        let policy = OrchestrationSummaryPolicy(
            failureKeywords: ["catastrophic"],
            successKeywords: ["ship it"],
            highlightKeywords: ["checkpoint"],
            maxRecentLineCount: 20,
            maxHighlights: 2
        )
        let service = OrchestrationSummaryService(policy: policy)
        let output = [
            "step checkpoint reached",
            "Ship It now",
        ]

        let summary = service.summarize(outputLines: output)

        XCTAssertEqual(summary.resultKind, .succeeded)
        XCTAssertEqual(summary.highlights, output)
        XCTAssertTrue(summary.summary.contains("성공 신호가 확인되었습니다."))
    }

    func testStatusContractPayloadMatchesStatusSchema() {
        let service = OrchestrationSummaryService()
        let output = [
            "warning: flaky path",
            "all checks passed",
        ]

        let payload = service.makeStatusContract(outputLines: output)

        XCTAssertEqual(payload.resultKind, "succeeded")
        XCTAssertEqual(payload.highlights, output)
        XCTAssertTrue(payload.summary.contains("성공 신호가 확인되었습니다."))
    }

    func testSummarizeContractPayloadSnapshotForConversationAndMemoryReflection() {
        let service = OrchestrationSummaryService()
        let output = [
            "step: compile",
            "warning: flaky test",
            "build failed with exit code 1",
        ]

        let payload = service.makeSummarizeContract(outputLines: output)

        XCTAssertEqual(payload.resultKind, "failed")
        XCTAssertEqual(payload.summary, "실패 신호가 감지되었습니다. 핵심 출력: warning: flaky test | build failed with exit code 1")
        XCTAssertEqual(payload.highlights, ["warning: flaky test", "build failed with exit code 1"])
        XCTAssertEqual(payload.contextReflection.conversationSummary, "[external-cli:failed] 실패 신호가 감지되었습니다. 핵심 출력: warning: flaky test | build failed with exit code 1")
        XCTAssertEqual(payload.contextReflection.memoryCandidate, "warning: flaky test | build failed with exit code 1")
    }
}
