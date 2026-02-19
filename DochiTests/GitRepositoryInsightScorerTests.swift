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

    func testInitializeGitRepositoryCreatesExpectedFiles() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-repo-init-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let repoPath = tempRoot.appendingPathComponent("sample-project", isDirectory: true).path
        let initializedPath = try ExternalToolSessionManager.initializeGitRepository(
            atPath: repoPath,
            defaultBranch: "main",
            createReadme: true,
            createGitignore: true
        )

        XCTAssertEqual(initializedPath, URL(fileURLWithPath: repoPath).standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(initializedPath)/.git"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(initializedPath)/README.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(initializedPath)/.gitignore"))
    }

    func testResolveGitTopLevelFromNestedPath() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-repo-resolve-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let repoPath = tempRoot.appendingPathComponent("workspace", isDirectory: true).path
        let initializedPath = try ExternalToolSessionManager.initializeGitRepository(
            atPath: repoPath,
            defaultBranch: "main",
            createReadme: false,
            createGitignore: false
        )

        let nested = URL(fileURLWithPath: initializedPath)
            .appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let resolved = ExternalToolSessionManager.resolveGitTopLevel(path: nested.path)
        XCTAssertEqual(resolved, initializedPath)
    }

    func testCloneGitRepositoryFromLocalPath() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-repo-clone-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourcePath = tempRoot.appendingPathComponent("source", isDirectory: true).path
        let destinationPath = tempRoot.appendingPathComponent("destination", isDirectory: true).path

        let initializedSource = try ExternalToolSessionManager.initializeGitRepository(
            atPath: sourcePath,
            defaultBranch: "main",
            createReadme: true,
            createGitignore: false
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(initializedSource)/.git"))

        let clonedPath = try ExternalToolSessionManager.cloneGitRepository(
            remoteURL: initializedSource,
            destinationPath: destinationPath,
            branch: nil
        )

        XCTAssertEqual(clonedPath, URL(fileURLWithPath: destinationPath).standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(clonedPath)/.git"))
        XCTAssertEqual(ExternalToolSessionManager.resolveGitTopLevel(path: clonedPath), clonedPath)
    }
}
