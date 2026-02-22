import XCTest
@testable import Dochi

final class GitRepositoryInsightScorerTests: XCTestCase {

    func testScoreFavorsRecentAndActiveRepository() {
        let active = GitRepositoryActivityMetrics(
            daysSinceLastCommit: 1,
            recentCommitCount30d: 18,
            changedFileCount: 5,
            untrackedFileCount: 2,
            aheadCount: 1
        )
        let stale = GitRepositoryActivityMetrics(
            daysSinceLastCommit: 120,
            recentCommitCount30d: 0,
            changedFileCount: 0,
            untrackedFileCount: 0,
            aheadCount: 0
        )

        XCTAssertGreaterThan(GitRepositoryInsightScorer.score(active), GitRepositoryInsightScorer.score(stale))
    }

    func testScoreRewardsRecentCommits() {
        let slow = GitRepositoryActivityMetrics(
            daysSinceLastCommit: 5,
            recentCommitCount30d: 2,
            changedFileCount: 0,
            untrackedFileCount: 0,
            aheadCount: 0
        )
        let fast = GitRepositoryActivityMetrics(
            daysSinceLastCommit: 5,
            recentCommitCount30d: 12,
            changedFileCount: 0,
            untrackedFileCount: 0,
            aheadCount: 0
        )

        XCTAssertGreaterThan(GitRepositoryInsightScorer.score(fast), GitRepositoryInsightScorer.score(slow))
    }

    func testScoreIncludesDirtyStateSignal() {
        let clean = GitRepositoryActivityMetrics(
            daysSinceLastCommit: 3,
            recentCommitCount30d: 4,
            changedFileCount: 0,
            untrackedFileCount: 0,
            aheadCount: 0
        )
        let dirty = GitRepositoryActivityMetrics(
            daysSinceLastCommit: 3,
            recentCommitCount30d: 4,
            changedFileCount: 7,
            untrackedFileCount: 3,
            aheadCount: 0
        )

        XCTAssertGreaterThan(GitRepositoryInsightScorer.score(dirty), GitRepositoryInsightScorer.score(clean))
    }

    func testDiscoverIncludesLatestCommitHeadlineContext() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-insight-headline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let repoPath = tempRoot.appendingPathComponent("headline-repo", isDirectory: true).path
        let initializedPath = try ExternalToolSessionManager.initializeGitRepository(
            atPath: repoPath,
            defaultBranch: "main",
            createReadme: false,
            createGitignore: false
        )

        try runGit(args: ["config", "user.email", "dochi-tests@example.com"], at: initializedPath)
        try runGit(args: ["config", "user.name", "Dochi Tests"], at: initializedPath)

        let noteURL = URL(fileURLWithPath: initializedPath).appendingPathComponent("note.txt")
        try "hello".data(using: .utf8)?.write(to: noteURL)
        try runGit(args: ["add", "note.txt"], at: initializedPath)
        try runGit(args: ["commit", "-m", "feat: expose latest commit context in explorer"], at: initializedPath)

        let insights = GitRepositoryInsightScanner.discover(
            searchPaths: [initializedPath],
            limit: 10
        )
        let insight = try XCTUnwrap(insights.first(where: { $0.path == initializedPath }))
        XCTAssertEqual(insight.lastCommitSubject, "feat: expose latest commit context in explorer")
        XCTAssertNotNil(insight.lastCommitShortHash)
        XCTAssertFalse(insight.lastCommitShortHash?.isEmpty ?? true)
    }

    private func runGit(args: [String], at path: String) throws {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", path] + args
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            XCTFail("git command failed: git -C \(path) \(args.joined(separator: " "))\n\(output)")
        }
    }
}
