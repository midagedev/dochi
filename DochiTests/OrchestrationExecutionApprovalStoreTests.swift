import XCTest
@testable import Dochi

final class OrchestrationExecutionApprovalStoreTests: XCTestCase {
    func testApproveAndConsumeSucceedsOnce() async throws {
        let store = OrchestrationExecutionApprovalStore(defaultTTLSeconds: 120)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let challenge = await store.create(
            command: "make test",
            repositoryRoot: "/tmp/repo",
            ttlSeconds: 120,
            now: now
        )
        let approvalId = challenge.snapshot.approvalId
        let code = challenge.snapshot.challengeCode

        let approved = await store.approve(
            approvalId: approvalId,
            challengeCode: code,
            now: now.addingTimeInterval(1)
        )
        XCTAssertTrue(approved.isAllowed)

        let consumed = await store.consumeExecution(
            approvalId: approvalId,
            command: "make test",
            repositoryRoot: "/tmp/repo",
            now: now.addingTimeInterval(2)
        )
        XCTAssertTrue(consumed.isAllowed)
        XCTAssertEqual(consumed.snapshot?.status, .consumed)

        let reused = await store.consumeExecution(
            approvalId: approvalId,
            command: "make test",
            repositoryRoot: "/tmp/repo",
            now: now.addingTimeInterval(3)
        )
        XCTAssertFalse(reused.isAllowed)
        XCTAssertEqual(reused.failureCode, .approvalAlreadyConsumed)
    }

    func testApproveFailsOnWrongChallengeCode() async throws {
        let store = OrchestrationExecutionApprovalStore(defaultTTLSeconds: 120)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let challenge = await store.create(
            command: "git status",
            repositoryRoot: nil,
            ttlSeconds: 120,
            now: now
        )

        let approved = await store.approve(
            approvalId: challenge.snapshot.approvalId,
            challengeCode: "000000",
            now: now.addingTimeInterval(1)
        )
        XCTAssertFalse(approved.isAllowed)
        XCTAssertEqual(approved.failureCode, .approvalCodeMismatch)
    }

    func testApproveFailsAfterExpiry() async throws {
        let store = OrchestrationExecutionApprovalStore(defaultTTLSeconds: 30, minTTLSeconds: 1, maxTTLSeconds: 60)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let challenge = await store.create(
            command: "npm run build",
            repositoryRoot: "/tmp/repo",
            ttlSeconds: 1,
            now: now
        )
        let approvalId = challenge.snapshot.approvalId
        let code = challenge.snapshot.challengeCode

        let expired = await store.approve(
            approvalId: approvalId,
            challengeCode: code,
            now: now.addingTimeInterval(5)
        )
        XCTAssertFalse(expired.isAllowed)
        XCTAssertEqual(expired.failureCode, .approvalExpired)
    }

    func testConsumeFailsOnCommandOrRepositoryMismatch() async throws {
        let store = OrchestrationExecutionApprovalStore(defaultTTLSeconds: 120)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let challenge = await store.create(
            command: "swift test",
            repositoryRoot: "/tmp/repo-a",
            ttlSeconds: 120,
            now: now
        )
        _ = await store.approve(
            approvalId: challenge.snapshot.approvalId,
            challengeCode: challenge.snapshot.challengeCode,
            now: now.addingTimeInterval(1)
        )

        let mismatchedCommand = await store.consumeExecution(
            approvalId: challenge.snapshot.approvalId,
            command: "swift build",
            repositoryRoot: "/tmp/repo-a",
            now: now.addingTimeInterval(2)
        )
        XCTAssertFalse(mismatchedCommand.isAllowed)
        XCTAssertEqual(mismatchedCommand.failureCode, .approvalContextMismatch)

        let mismatchedRepo = await store.consumeExecution(
            approvalId: challenge.snapshot.approvalId,
            command: "swift test",
            repositoryRoot: "/tmp/repo-b",
            now: now.addingTimeInterval(3)
        )
        XCTAssertFalse(mismatchedRepo.isAllowed)
        XCTAssertEqual(mismatchedRepo.failureCode, .approvalContextMismatch)
    }
}
