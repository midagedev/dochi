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

    func testRepositoryRootBindingUsesManagedRootsFirst() {
        let root = "/tmp/work/repo-a"
        let nested = "/tmp/work/repo-a/Sources/App"
        let resolved = ExternalToolSessionManager.repositoryRoot(
            for: nested,
            managedRepositoryRoots: [root]
        )
        XCTAssertEqual(resolved, root)
    }

    func testUnifiedSessionDedupUsesProviderNativeIdAndRepo() {
        let now = Date()
        let old = now.addingTimeInterval(-60)
        let first = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "codex",
            nativeSessionId: "sess-1",
            runtimeSessionId: nil,
            workingDirectory: "/tmp/repo",
            repositoryRoot: "/tmp/repo",
            path: "/tmp/a.jsonl",
            updatedAt: old,
            isActive: false
        )
        let newerDuplicate = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "codex",
            nativeSessionId: "sess-1",
            runtimeSessionId: nil,
            workingDirectory: "/tmp/repo",
            repositoryRoot: "/tmp/repo",
            path: "/tmp/b.jsonl",
            updatedAt: now,
            isActive: true
        )
        let differentRepo = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "codex",
            nativeSessionId: "sess-1",
            runtimeSessionId: nil,
            workingDirectory: "/tmp/repo2",
            repositoryRoot: "/tmp/repo2",
            path: "/tmp/c.jsonl",
            updatedAt: now,
            isActive: true
        )

        let deduped = ExternalToolSessionManager.deduplicateUnifiedCodingSessions(
            [first, newerDuplicate, differentRepo],
            limit: 10
        )

        XCTAssertEqual(deduped.count, 2)
        XCTAssertTrue(deduped.contains(where: { $0.path == "/tmp/b.jsonl" }))
        XCTAssertTrue(deduped.contains(where: { $0.path == "/tmp/c.jsonl" }))
    }

    func testActivityScoringCombinesFiveSignalsAndClassifiesActive() {
        let result = ExternalToolSessionManager.scoreUnifiedSessionActivity(
            input: ExternalToolSessionManager.UnifiedSessionActivityInput(
                runtimeAlive: true,
                recentOutputAge: 20,
                recentCommandAge: 30,
                fileMtimeAge: 40,
                hasErrorPattern: false
            ),
            config: .standard
        )

        XCTAssertEqual(result.state, .active)
        XCTAssertGreaterThanOrEqual(result.score, CodingSessionActivityScoringConfig.standard.activeThreshold)
        XCTAssertGreaterThan(result.signals.runtimeAliveScore, 0)
        XCTAssertGreaterThan(result.signals.recentOutputScore, 0)
        XCTAssertGreaterThan(result.signals.recentCommandScore, 0)
        XCTAssertGreaterThan(result.signals.fileFreshnessScore, 0)
        XCTAssertEqual(result.signals.errorPenaltyScore, 0)
    }

    func testActivityScoringAppliesErrorPenaltyAndCanDropState() {
        let baseInput = ExternalToolSessionManager.UnifiedSessionActivityInput(
            runtimeAlive: true,
            recentOutputAge: 45,
            recentCommandAge: 80,
            fileMtimeAge: 90,
            hasErrorPattern: false
        )
        let withoutError = ExternalToolSessionManager.scoreUnifiedSessionActivity(input: baseInput, config: .standard)
        let withError = ExternalToolSessionManager.scoreUnifiedSessionActivity(
            input: ExternalToolSessionManager.UnifiedSessionActivityInput(
                runtimeAlive: true,
                recentOutputAge: 45,
                recentCommandAge: 80,
                fileMtimeAge: 90,
                hasErrorPattern: true
            ),
            config: .standard
        )

        XCTAssertGreaterThan(withoutError.score, withError.score)
        XCTAssertGreaterThan(withError.signals.errorPenaltyScore, 0)
        XCTAssertTrue(withError.state == .idle || withError.state == .stale || withError.state == .dead)
    }

    func testActivityScoringClassifiesStaleAndDead() {
        let stale = ExternalToolSessionManager.scoreUnifiedSessionActivity(
            input: ExternalToolSessionManager.UnifiedSessionActivityInput(
                runtimeAlive: false,
                recentOutputAge: 3_600,
                recentCommandAge: nil,
                fileMtimeAge: 3_600,
                hasErrorPattern: false
            ),
            config: .standard
        )
        let dead = ExternalToolSessionManager.scoreUnifiedSessionActivity(
            input: ExternalToolSessionManager.UnifiedSessionActivityInput(
                runtimeAlive: false,
                recentOutputAge: 200_000,
                recentCommandAge: nil,
                fileMtimeAge: 200_000,
                hasErrorPattern: true
            ),
            config: .standard
        )

        XCTAssertEqual(stale.state, .stale)
        XCTAssertEqual(dead.state, .dead)
        XCTAssertLessThan(dead.score, stale.score)
    }

    func testUnifiedSessionOrderingIsDeterministicWhenTimestampsTie() {
        let tiedTime = Date(timeIntervalSince1970: 1_700_000_000)
        let later = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "zeta",
            nativeSessionId: "sess-9",
            runtimeSessionId: nil,
            workingDirectory: "/tmp/repo-z",
            repositoryRoot: "/tmp/repo-z",
            path: "/tmp/z.jsonl",
            updatedAt: tiedTime,
            isActive: true
        )
        let earlier = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "alpha",
            nativeSessionId: "sess-1",
            runtimeSessionId: nil,
            workingDirectory: "/tmp/repo-a",
            repositoryRoot: "/tmp/repo-a",
            path: "/tmp/a.jsonl",
            updatedAt: tiedTime,
            isActive: true
        )

        let deduped = ExternalToolSessionManager.deduplicateUnifiedCodingSessions(
            [later, earlier],
            limit: 10
        )

        XCTAssertEqual(deduped.map(\.provider), ["alpha", "zeta"])
        XCTAssertEqual(deduped.map(\.nativeSessionId), ["sess-1", "sess-9"])
    }
}
