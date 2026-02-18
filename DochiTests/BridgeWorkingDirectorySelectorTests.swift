import XCTest
@testable import Dochi

final class BridgeWorkingDirectorySelectorTests: XCTestCase {

    func testDecideReturnsRecommendedRootForNewProfile() {
        let decision = BridgeWorkingDirectorySelector.decide(
            existingProfile: nil,
            requestedWorkingDirectory: nil,
            forceWorkingDirectory: false,
            recommendedRoots: [sampleInsight(path: "/Users/me/repo/top", score: 70)]
        )

        XCTAssertEqual(decision.workingDirectory, "/Users/me/repo/top")
        XCTAssertEqual(decision.selectionReason, .recommendedGitRoot)
    }

    func testDecideFallsBackToHomeWhenNoRecommendation() {
        let decision = BridgeWorkingDirectorySelector.decide(
            existingProfile: nil,
            requestedWorkingDirectory: nil,
            forceWorkingDirectory: false,
            recommendedRoots: []
        )

        XCTAssertEqual(decision.workingDirectory, "~")
        XCTAssertEqual(decision.selectionReason, .fallbackHomeDirectory)
    }

    func testDecidePreservesExistingProfileWithoutForce() {
        let existing = ExternalToolProfile(name: "Bridge", command: "codex", workingDirectory: "~/repo/existing")

        let decision = BridgeWorkingDirectorySelector.decide(
            existingProfile: existing,
            requestedWorkingDirectory: "/tmp/new",
            forceWorkingDirectory: false,
            recommendedRoots: []
        )

        XCTAssertEqual(decision.workingDirectory, "~/repo/existing")
        XCTAssertEqual(decision.selectionReason, .existingProfilePreserved)
    }

    func testDecideOverridesExistingProfileWithForce() {
        let existing = ExternalToolProfile(name: "Bridge", command: "codex", workingDirectory: "~/repo/existing")

        let decision = BridgeWorkingDirectorySelector.decide(
            existingProfile: existing,
            requestedWorkingDirectory: "/tmp/new",
            forceWorkingDirectory: true,
            recommendedRoots: []
        )

        XCTAssertEqual(decision.workingDirectory, "/tmp/new")
        XCTAssertEqual(decision.selectionReason, .existingProfileOverridden)
    }

    func testDecideForActiveSessionIgnoresForcedOverride() {
        let decision = BridgeWorkingDirectorySelector.decideForActiveSession(
            profileWorkingDirectory: "~/repo/existing",
            requestedWorkingDirectory: "/tmp/new",
            forceWorkingDirectory: true
        )

        XCTAssertEqual(decision.workingDirectory, "~/repo/existing")
        XCTAssertEqual(decision.selectionReason, .existingSessionReusedForceIgnored)
    }

    private func sampleInsight(path: String, score: Int) -> GitRepositoryInsight {
        GitRepositoryInsight(
            workDomain: "company",
            workDomainConfidence: 0.8,
            workDomainReason: "test",
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            branch: "main",
            originURL: "git@github.com:acme/sample.git",
            remoteHost: "github.com",
            remoteOwner: "acme",
            remoteRepository: "sample",
            lastCommitEpoch: 1_700_000_000,
            lastCommitISO8601: "2023-11-14T22:13:20.000Z",
            lastCommitRelative: "1d ago",
            upstreamLastCommitEpoch: 1_700_000_000,
            upstreamLastCommitISO8601: "2023-11-14T22:13:20.000Z",
            upstreamLastCommitRelative: "1d ago",
            daysSinceLastCommit: 1,
            recentCommitCount30d: 10,
            changedFileCount: 2,
            untrackedFileCount: 1,
            aheadCount: 0,
            behindCount: 0,
            score: score
        )
    }
}
