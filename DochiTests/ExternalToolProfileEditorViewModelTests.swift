import XCTest
@testable import Dochi

@MainActor
final class ExternalToolProfileEditorViewModelTests: XCTestCase {

    func testRefreshRecommendedRootsLoadsInsights() async {
        let manager = MockExternalToolSessionManager()
        manager.mockGitRepositoryInsights = [
            sampleInsight(path: "/Users/me/repo/a", score: 60),
            sampleInsight(path: "/Users/me/repo/b", score: 42),
        ]
        let viewModel = ExternalToolProfileEditorViewModel(manager: manager)

        await viewModel.refreshRecommendedRoots(limit: 1)

        XCTAssertFalse(viewModel.isLoadingRecommendations)
        XCTAssertTrue(viewModel.hasLoadedRecommendations)
        XCTAssertEqual(viewModel.recommendedRoots.count, 1)
        XCTAssertEqual(viewModel.recommendedRoots.first?.path, "/Users/me/repo/a")
    }

    func testApplyRecommendedRootReturnsPath() {
        let manager = MockExternalToolSessionManager()
        let viewModel = ExternalToolProfileEditorViewModel(manager: manager)
        let root = sampleInsight(path: "/Users/me/repo/a", score: 60)

        let path = viewModel.applyRecommendedRoot(root)

        XCTAssertEqual(path, "/Users/me/repo/a")
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
