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

    @MainActor
    func testManagerRepositoryLifecyclePersistsArchivedStateAcrossReload() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-repo-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let appSupport = tempRoot.appendingPathComponent("app-support", isDirectory: true)
        let settings = AppSettings()
        settings.externalToolEnabled = false
        let manager = ExternalToolSessionManager(
            settings: settings,
            appSupportDirectory: appSupport
        )

        let initialized = try await manager.initializeRepository(
            path: tempRoot.appendingPathComponent("initialized", isDirectory: true).path,
            defaultBranch: "main",
            createReadme: false,
            createGitignore: false
        )

        let attachRoot = try ExternalToolSessionManager.initializeGitRepository(
            atPath: tempRoot.appendingPathComponent("attached", isDirectory: true).path,
            defaultBranch: "main",
            createReadme: false,
            createGitignore: false
        )
        let nested = URL(fileURLWithPath: attachRoot).appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let attached = try await manager.attachRepository(path: nested.path)

        let cloneSource = try ExternalToolSessionManager.initializeGitRepository(
            atPath: tempRoot.appendingPathComponent("clone-source", isDirectory: true).path,
            defaultBranch: "main",
            createReadme: true,
            createGitignore: false
        )
        let cloneDestination = tempRoot.appendingPathComponent("cloned", isDirectory: true).path
        let cloned = try await manager.cloneRepository(
            remoteURL: cloneSource,
            destinationPath: cloneDestination,
            branch: nil
        )

        XCTAssertEqual(manager.managedRepositories.filter { !$0.isArchived }.count, 3)

        try await manager.removeManagedRepository(id: cloned.id, deleteDirectory: false)
        try await manager.removeManagedRepository(id: attached.id, deleteDirectory: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cloneDestination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachRoot))

        let reloaded = ExternalToolSessionManager(
            settings: settings,
            appSupportDirectory: appSupport
        )
        XCTAssertEqual(reloaded.managedRepositories.count, 3)
        XCTAssertEqual(reloaded.managedRepositories.first(where: { $0.id == initialized.id })?.isArchived, false)
        XCTAssertEqual(reloaded.managedRepositories.first(where: { $0.id == cloned.id })?.isArchived, true)
        XCTAssertEqual(reloaded.managedRepositories.first(where: { $0.id == attached.id })?.isArchived, true)
    }

    @MainActor
    func testManagerAttachRepositoryRejectsInvalidPath() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-repo-attach-invalid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let appSupport = tempRoot.appendingPathComponent("app-support", isDirectory: true)
        let settings = AppSettings()
        settings.externalToolEnabled = false
        let manager = ExternalToolSessionManager(
            settings: settings,
            appSupportDirectory: appSupport
        )

        let invalidPath = tempRoot.appendingPathComponent("not-a-repo", isDirectory: true).path
        try FileManager.default.createDirectory(
            atPath: invalidPath,
            withIntermediateDirectories: true
        )

        do {
            _ = try await manager.attachRepository(path: invalidPath)
            XCTFail("Expected invalidRepositoryPath")
        } catch let error as ExternalToolError {
            guard case .invalidRepositoryPath(let failingPath) = error else {
                return XCTFail("Unexpected ExternalToolError: \(error)")
            }
            XCTAssertEqual(failingPath, invalidPath)
        }
    }

    @MainActor
    func testManagerCloneRepositoryRejectsExistingDestinationPath() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-repo-clone-existing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let appSupport = tempRoot.appendingPathComponent("app-support", isDirectory: true)
        let settings = AppSettings()
        settings.externalToolEnabled = false
        let manager = ExternalToolSessionManager(
            settings: settings,
            appSupportDirectory: appSupport
        )

        let source = try ExternalToolSessionManager.initializeGitRepository(
            atPath: tempRoot.appendingPathComponent("source", isDirectory: true).path,
            defaultBranch: "main",
            createReadme: false,
            createGitignore: false
        )
        let destination = tempRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            _ = try await manager.cloneRepository(
                remoteURL: source,
                destinationPath: destination.path,
                branch: nil
            )
            XCTFail("Expected repositoryOperationFailed for existing destination path")
        } catch let error as ExternalToolError {
            guard case .repositoryOperationFailed(let reason) = error else {
                return XCTFail("Unexpected ExternalToolError: \(error)")
            }
            XCTAssertTrue(
                reason.contains(destination.path) || reason.contains("이미 존재")
            )
        }
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

    func testMergeUnifiedCodingSessionsScoresAttachableProcessAsIdle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let runtime = ExternalToolSessionManager.RuntimeSessionSnapshot(
            provider: "codex",
            nativeSessionId: "pid-9001",
            runtimeSessionId: "9001",
            workingDirectory: "/tmp/repo-a",
            path: "process://9001",
            updatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            isActive: true,
            status: .unknown,
            lastOutputAt: nil,
            lastCommandAt: nil,
            hasErrorPattern: false,
            runtimeType: .process,
            controllabilityTier: .t1Attach,
            source: "process_runtime"
        )

        let merged = ExternalToolSessionManager.mergeUnifiedCodingSessions(
            runtimeSessions: [runtime],
            discoveredSessions: [],
            managedRepositoryRoots: ["/tmp/repo-a"],
            limit: 10,
            now: now,
            config: .standard
        )

        guard let session = merged.first else {
            return XCTFail("Expected merged session")
        }
        XCTAssertEqual(session.activityState, .idle)
        XCTAssertGreaterThanOrEqual(
            session.activityScore,
            CodingSessionActivityScoringConfig.standard.idleThreshold
        )
    }

    func testMergeUnifiedCodingSessionsKeepsUnknownProcessAsStale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let runtime = ExternalToolSessionManager.RuntimeSessionSnapshot(
            provider: "codex",
            nativeSessionId: "pid-9002",
            runtimeSessionId: "9002",
            workingDirectory: nil,
            path: "process://9002",
            updatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            isActive: true,
            status: .unknown,
            lastOutputAt: nil,
            lastCommandAt: nil,
            hasErrorPattern: false,
            runtimeType: .process,
            controllabilityTier: .t3Unknown,
            source: "process_runtime"
        )

        let merged = ExternalToolSessionManager.mergeUnifiedCodingSessions(
            runtimeSessions: [runtime],
            discoveredSessions: [],
            managedRepositoryRoots: [],
            limit: 10,
            now: now,
            config: .standard
        )

        guard let session = merged.first else {
            return XCTFail("Expected merged session")
        }
        XCTAssertEqual(session.activityState, .stale)
        XCTAssertEqual(session.activityScore, CodingSessionActivityScoringConfig.standard.runtimeAliveWeight)
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

    func testParseProcessRuntimeSnapshotsClassifiesProviderTierAndRuntimeType() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let output = """
        1234 ttys003 00:05 /opt/homebrew/bin/codex run
        2234 ?? 01:10:00 /usr/bin/python3 -m aider --model gpt-4.1
        3333 ttys004 00:01 /usr/bin/vim main.swift
        """

        let snapshots = ExternalToolSessionManager.parseProcessRuntimeSnapshots(
            psOutput: output,
            now: now,
            workingDirectories: [1234: "/tmp/repo-a"],
            limit: 10
        )

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertFalse(snapshots.contains(where: { $0.runtimeSessionId == "3333" }))

        let codex = snapshots.first(where: { $0.runtimeSessionId == "1234" })
        XCTAssertEqual(codex?.provider, "codex")
        XCTAssertEqual(codex?.runtimeType, .process)
        XCTAssertEqual(codex?.controllabilityTier, .t1Attach)
        XCTAssertEqual(codex?.workingDirectory, "/tmp/repo-a")
        XCTAssertEqual(codex?.path, "process://1234")
        XCTAssertEqual(codex?.nativeSessionId, "pid-1234")

        let aider = snapshots.first(where: { $0.runtimeSessionId == "2234" })
        XCTAssertEqual(aider?.provider, "aider")
        XCTAssertEqual(aider?.runtimeType, .process)
        XCTAssertEqual(aider?.controllabilityTier, .t3Unknown)
    }

    func testParseProcessElapsedSupportsPSFormats() {
        XCTAssertEqual(ExternalToolSessionManager.parseProcessElapsed("03:15"), 195)
        XCTAssertEqual(ExternalToolSessionManager.parseProcessElapsed("02:03:04"), 7_384)
        XCTAssertEqual(ExternalToolSessionManager.parseProcessElapsed("1-02:03:04"), 93_784)
        XCTAssertNil(ExternalToolSessionManager.parseProcessElapsed("not-a-time"))
    }

    func testProcessProviderHeuristicsRecognizeCommonLaunchPatterns() {
        XCTAssertEqual(
            ExternalToolSessionManager.processProvider(fromCommandLine: "/opt/homebrew/bin/codex run"),
            "codex"
        )
        XCTAssertEqual(
            ExternalToolSessionManager.processProvider(fromCommandLine: "python3 -m aider --model sonnet"),
            "aider"
        )
        XCTAssertEqual(
            ExternalToolSessionManager.processProvider(fromCommandLine: "/usr/local/bin/claude --continue"),
            "claude"
        )
        XCTAssertNil(
            ExternalToolSessionManager.processProvider(fromCommandLine: "/Applications/Codex.app/Contents/MacOS/Codex")
        )
        XCTAssertNil(
            ExternalToolSessionManager.processProvider(
                fromCommandLine: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper --type=gpu-process"
            )
        )
        XCTAssertNil(
            ExternalToolSessionManager.processProvider(fromCommandLine: "/usr/bin/vim main.swift")
        )
    }

    func testProcessControllabilityTierTreatsUnknownTTYAsT3() {
        XCTAssertEqual(ExternalToolSessionManager.processControllabilityTier(tty: "ttys002"), .t1Attach)
        XCTAssertEqual(ExternalToolSessionManager.processControllabilityTier(tty: "??"), .t3Unknown)
        XCTAssertEqual(ExternalToolSessionManager.processControllabilityTier(tty: "-"), .t3Unknown)
        XCTAssertEqual(ExternalToolSessionManager.processControllabilityTier(tty: "   "), .t3Unknown)
    }

    func testProcessWorkingDirectoryCandidatePIDSCapsAndSkipsInvalidIDs() {
        let now = Date()
        let snapshots: [ExternalToolSessionManager.RuntimeSessionSnapshot] = [
            .init(
                provider: "codex",
                nativeSessionId: "pid-101",
                runtimeSessionId: "101",
                workingDirectory: nil,
                path: "process://101",
                updatedAt: now,
                isActive: true,
                status: .unknown,
                lastOutputAt: nil,
                lastCommandAt: nil,
                hasErrorPattern: false,
                runtimeType: .process,
                controllabilityTier: .t1Attach,
                source: "process_runtime"
            ),
            .init(
                provider: "codex",
                nativeSessionId: "pid-101-dup",
                runtimeSessionId: "101",
                workingDirectory: nil,
                path: "process://101",
                updatedAt: now.addingTimeInterval(-1),
                isActive: true,
                status: .unknown,
                lastOutputAt: nil,
                lastCommandAt: nil,
                hasErrorPattern: false,
                runtimeType: .process,
                controllabilityTier: .t1Attach,
                source: "process_runtime"
            ),
            .init(
                provider: "claude",
                nativeSessionId: "pid-202",
                runtimeSessionId: "202",
                workingDirectory: nil,
                path: "process://202",
                updatedAt: now.addingTimeInterval(-2),
                isActive: true,
                status: .unknown,
                lastOutputAt: nil,
                lastCommandAt: nil,
                hasErrorPattern: false,
                runtimeType: .process,
                controllabilityTier: .t1Attach,
                source: "process_runtime"
            ),
            .init(
                provider: "aider",
                nativeSessionId: "pid-invalid",
                runtimeSessionId: "abc",
                workingDirectory: nil,
                path: "process://abc",
                updatedAt: now.addingTimeInterval(-3),
                isActive: true,
                status: .unknown,
                lastOutputAt: nil,
                lastCommandAt: nil,
                hasErrorPattern: false,
                runtimeType: .process,
                controllabilityTier: .t1Attach,
                source: "process_runtime"
            ),
        ]

        let selected = ExternalToolSessionManager.processWorkingDirectoryCandidatePIDs(
            from: snapshots,
            cap: 2
        )

        XCTAssertEqual(selected, [101, 202])
    }

    func testDiscoverLocalCodingSessionsParsesClaudeIndexTitleMetadata() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-claude-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let codexRoot = tempRoot.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = tempRoot.appendingPathComponent("claude", isDirectory: true)
        let projectDir = claudeRoot.appendingPathComponent("-Users-hckim-repo-dochi", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let indexURL = projectDir.appendingPathComponent("sessions-index.json")
        let entry: [String: Any] = [
            "sessionId": "claude-session-123",
            "projectPath": "/Users/hckim/repo/dochi",
            "fullPath": "/Users/hckim/.claude/projects/-Users-hckim-repo-dochi/claude-session-123.jsonl",
            "modified": "2026-02-21T01:02:03Z",
            "summary": "Repo dashboard 정리 및 세션 인덱스 개선",
            "firstPrompt": "세션 title과 summary를 인덱싱해줘",
        ]
        let payload: [String: Any] = ["entries": [entry]]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: indexURL, options: .atomic)

        let now = Date(timeIntervalSince1970: 1_771_636_000)
        let discovered = ExternalToolSessionManager.discoverLocalCodingSessions(
            codexSessionsRoot: codexRoot,
            claudeProjectsRoot: claudeRoot,
            limit: 20,
            now: now
        )

        let claude = try XCTUnwrap(discovered.first(where: { $0.provider == "claude" && $0.sessionId == "claude-session-123" }))
        XCTAssertEqual(claude.title, "Repo dashboard 정리 및 세션 인덱스 개선")
        XCTAssertEqual(claude.summary, "Repo dashboard 정리 및 세션 인덱스 개선")
        XCTAssertEqual(claude.titleSource, "claude_sessions_index")
        XCTAssertNotNil(claude.titleConfidence)
        if let confidence = claude.titleConfidence {
            XCTAssertEqual(confidence, 0.9, accuracy: 0.0001)
        }
    }

    func testDiscoverLocalCodingSessionsParsesCodexClientMetadata() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-codex-meta-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let codexRoot = tempRoot.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = tempRoot.appendingPathComponent("claude", isDirectory: true)
        let desktopFile = codexRoot
            .appendingPathComponent("2026/02/21", isDirectory: true)
            .appendingPathComponent("rollout-desktop.jsonl")
        let cliFile = codexRoot
            .appendingPathComponent("2026/02/21", isDirectory: true)
            .appendingPathComponent("rollout-cli.jsonl")
        try FileManager.default.createDirectory(
            at: desktopFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let desktopMeta = """
        {"timestamp":"2026-02-21T12:00:00Z","type":"session_meta","payload":{"id":"codex-desktop-1","cwd":"/Users/hckim/repo/dochi","originator":"Codex Desktop","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hello"}]}}
        """
        try desktopMeta.data(using: .utf8)?.write(to: desktopFile, options: .atomic)

        let cliMeta = """
        {"timestamp":"2026-02-21T12:10:00Z","type":"session_meta","payload":{"id":"codex-cli-1","cwd":"/Users/hckim/repo/dochi","originator":"Codex CLI","source":"cli"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hi"}]}}
        """
        try cliMeta.data(using: .utf8)?.write(to: cliFile, options: .atomic)

        let discovered = ExternalToolSessionManager.discoverLocalCodingSessions(
            codexSessionsRoot: codexRoot,
            claudeProjectsRoot: claudeRoot,
            limit: 20,
            now: Date(timeIntervalSince1970: 1_771_636_000)
        )

        let desktop = try XCTUnwrap(discovered.first(where: { $0.sessionId == "codex-desktop-1" }))
        XCTAssertEqual(desktop.provider, "codex")
        XCTAssertEqual(desktop.originator, "Codex Desktop")
        XCTAssertEqual(desktop.sessionSource, "vscode")
        XCTAssertEqual(desktop.clientKind, "desktop")

        let cli = try XCTUnwrap(discovered.first(where: { $0.sessionId == "codex-cli-1" }))
        XCTAssertEqual(cli.provider, "codex")
        XCTAssertEqual(cli.originator, "Codex CLI")
        XCTAssertEqual(cli.sessionSource, "cli")
        XCTAssertEqual(cli.clientKind, "cli")
    }

    func testEnrichRuntimeSessionMetadataMatchesByWorkingDirectory() {
        let now = Date(timeIntervalSince1970: 1_771_636_000)
        let runtime = ExternalToolSessionManager.RuntimeSessionSnapshot(
            provider: "claude",
            nativeSessionId: "pid-31415",
            runtimeSessionId: "31415",
            workingDirectory: "/Users/hckim/repo/dochi",
            path: "process://31415",
            updatedAt: now,
            isActive: true,
            status: .unknown,
            lastOutputAt: nil,
            lastCommandAt: nil,
            hasErrorPattern: false,
            runtimeType: .process,
            controllabilityTier: .t1Attach,
            source: "process_runtime"
        )
        let discovered = DiscoveredCodingSession(
            source: .claudeProjectFile,
            provider: "claude",
            sessionId: "claude-session-xyz",
            workingDirectory: "/Users/hckim/repo/dochi",
            path: "/tmp/claude-session-xyz.jsonl",
            updatedAt: now,
            isActive: true,
            title: "Dochi 브리지 세션 상태 정비",
            summary: "bridge.status payload 개선",
            titleSource: "claude_sessions_index",
            titleConfidence: 0.9,
            originator: "Codex Desktop",
            sessionSource: "vscode",
            clientKind: "desktop"
        )

        let enriched = ExternalToolSessionManager.enrichRuntimeSessionMetadata(
            runtimeSessions: [runtime],
            discoveredSessions: [discovered]
        )

        guard let item = enriched.first else {
            return XCTFail("Expected enriched runtime session")
        }
        XCTAssertEqual(item.title, "Dochi 브리지 세션 상태 정비")
        XCTAssertEqual(item.summary, "bridge.status payload 개선")
        XCTAssertEqual(item.titleSource, "claude_sessions_index_cwd_match")
        XCTAssertNotNil(item.titleConfidence)
        if let confidence = item.titleConfidence {
            XCTAssertEqual(confidence, 0.81, accuracy: 0.0001)
        }
        XCTAssertEqual(item.originator, "Codex Desktop")
        XCTAssertEqual(item.sessionSource, "vscode")
        XCTAssertEqual(item.clientKind, "desktop")
    }

    func testExtractLatestTerminalTitleParsesOscSequences() {
        let esc = "\u{001B}"
        let bel = "\u{0007}"
        let lines = [
            "prompt>",
            "\(esc)]2;Repo: dochi #414\(bel)",
            "running...",
            "\(esc)]0;Fix title indexing\(esc)\\",
        ]

        let parsed = ExternalToolSessionManager.extractLatestTerminalTitle(fromLines: lines)
        XCTAssertEqual(parsed, "Fix title indexing")
    }

    func testEnrichRuntimeSessionMetadataSkipsProviderOnlyMatch() {
        let runtime = ExternalToolSessionManager.RuntimeSessionSnapshot(
            provider: "claude",
            nativeSessionId: "pid-99999",
            runtimeSessionId: "99999",
            workingDirectory: nil,
            path: "process://99999",
            updatedAt: Date(),
            isActive: true,
            status: .unknown,
            lastOutputAt: nil,
            lastCommandAt: nil,
            hasErrorPattern: false,
            runtimeType: .process,
            controllabilityTier: .t1Attach,
            source: "process_runtime"
        )
        let discovered = DiscoveredCodingSession(
            source: .claudeProjectFile,
            provider: "claude",
            sessionId: "claude-unrelated",
            workingDirectory: "/Users/hckim/repo/other",
            path: "/tmp/claude-unrelated.jsonl",
            updatedAt: Date(),
            isActive: true,
            title: "다른 세션 제목",
            summary: "다른 세션 요약",
            titleSource: "claude_sessions_index",
            titleConfidence: 0.9
        )

        let enriched = ExternalToolSessionManager.enrichRuntimeSessionMetadata(
            runtimeSessions: [runtime],
            discoveredSessions: [discovered]
        )

        guard let item = enriched.first else {
            return XCTFail("Expected runtime session")
        }
        XCTAssertNil(item.title)
        XCTAssertNil(item.summary)
        XCTAssertNil(item.titleSource)
        XCTAssertNil(item.titleConfidence)
    }

    func testEnrichRuntimeSessionMetadataKeepsSessionIdReasonPriority() {
        let now = Date()
        let runtime = ExternalToolSessionManager.RuntimeSessionSnapshot(
            provider: "claude",
            nativeSessionId: "claude-session-priority",
            runtimeSessionId: "12345",
            workingDirectory: "/Users/hckim/repo/dochi",
            path: "process://12345",
            updatedAt: now,
            isActive: true,
            status: .unknown,
            lastOutputAt: nil,
            lastCommandAt: nil,
            hasErrorPattern: false,
            runtimeType: .process,
            controllabilityTier: .t1Attach,
            source: "process_runtime"
        )
        let discovered = DiscoveredCodingSession(
            source: .claudeProjectFile,
            provider: "claude",
            sessionId: "claude-session-priority",
            workingDirectory: "/Users/hckim/repo/dochi",
            path: "/tmp/claude-session-priority.jsonl",
            updatedAt: now,
            isActive: true,
            title: "session id 우선",
            summary: "same cwd but id should win",
            titleSource: "claude_sessions_index",
            titleConfidence: 0.9
        )

        let enriched = ExternalToolSessionManager.enrichRuntimeSessionMetadata(
            runtimeSessions: [runtime],
            discoveredSessions: [discovered]
        )

        guard let item = enriched.first else {
            return XCTFail("Expected runtime session")
        }
        XCTAssertEqual(item.title, "session id 우선")
        XCTAssertEqual(item.titleSource, "claude_sessions_index_session_id_match")
        XCTAssertNotNil(item.titleConfidence)
        if let confidence = item.titleConfidence {
            XCTAssertEqual(confidence, 0.9, accuracy: 0.0001)
        }
    }
}
