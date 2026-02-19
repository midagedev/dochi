import XCTest
@testable import Dochi

final class SessionHistoryRAGTests: XCTestCase {

    func testNormalizeSessionHistoryLineCreatesStructuredEvent() {
        let raw = """
        {"type":"assistant_output","timestamp":"2026-02-19T08:00:00Z","content":"build failed: token=super-secret-token-123456"}
        """

        let event = ExternalToolSessionManager.normalizeSessionHistoryLine(
            provider: "codex",
            sessionId: "sess-1",
            sourcePath: "/tmp/sess-1.jsonl",
            workingDirectory: "/tmp/repo-a",
            repositoryRoot: "/tmp/repo-a",
            branch: "main",
            rawLine: raw,
            fallbackTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            lineNumber: 10
        )

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.provider, "codex")
        XCTAssertEqual(event?.sessionId, "sess-1")
        XCTAssertEqual(event?.repositoryRoot, "/tmp/repo-a")
        XCTAssertEqual(event?.eventType, "assistant_output")
        XCTAssertFalse(event?.content.contains("super-secret-token-123456") ?? true)
        XCTAssertTrue(event?.content.contains("[REDACTED]") ?? false)
    }

    func testSearchPrioritizesRepositoryWhenRequested() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let preferredRepo = "/tmp/repo-a"

        let preferred = SessionHistoryChunk(
            id: UUID(),
            provider: "codex",
            sessionId: "sess-a",
            repositoryRoot: preferredRepo,
            workingDirectory: preferredRepo,
            branch: "main",
            sourcePath: "/tmp/a.jsonl",
            startAt: now.addingTimeInterval(-120),
            endAt: now.addingTimeInterval(-60),
            tags: ["build"],
            content: "build failed in src/main.swift",
            embedding: [0, 0]
        )
        let other = SessionHistoryChunk(
            id: UUID(),
            provider: "codex",
            sessionId: "sess-b",
            repositoryRoot: "/tmp/repo-b",
            workingDirectory: "/tmp/repo-b",
            branch: "main",
            sourcePath: "/tmp/b.jsonl",
            startAt: now.addingTimeInterval(-120),
            endAt: now.addingTimeInterval(-60),
            tags: ["build"],
            content: "build failed in src/main.swift",
            embedding: [0, 0]
        )

        let results = ExternalToolSessionManager.searchSessionHistoryChunks(
            chunks: [other, preferred],
            query: SessionHistorySearchQuery(
                query: "build failed",
                repositoryRoot: preferredRepo,
                branch: nil,
                since: nil,
                until: nil,
                limit: 5
            ),
            now: now
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.repositoryRoot, preferredRepo)
    }

    func testMaskSensitiveContentRedactsKnownSecrets() {
        let input = """
        token=abcDEF1234567890
        sk-abcdefghijklmnopqrstuvwxyz123456
        ghp_abcdefghijklmnopqrstuvwxyz1234567890
        -----BEGIN PRIVATE KEY-----
        super secret payload
        -----END PRIVATE KEY-----
        """

        let masked = ExternalToolSessionManager.maskSensitiveContent(input)
        XCTAssertFalse(masked.contains("abcDEF1234567890"))
        XCTAssertFalse(masked.contains("abcdefghijklmnopqrstuvwxyz123456"))
        XCTAssertFalse(masked.contains("super secret payload"))
        XCTAssertTrue(masked.contains("[REDACTED]"))
        XCTAssertTrue(masked.contains("[REDACTED_OPENAI_KEY]"))
        XCTAssertTrue(masked.contains("[REDACTED_GITHUB_TOKEN]"))
        XCTAssertTrue(masked.contains("[REDACTED_PRIVATE_KEY]"))
    }

    func testMaskSensitiveContentRedactsAuthorizationBearer() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
        let masked = ExternalToolSessionManager.maskSensitiveContent(input)

        XCTAssertFalse(masked.localizedCaseInsensitiveContains("eyJhbGciOiJIUzI1Ni"))
        XCTAssertTrue(masked.contains("[REDACTED_BEARER_TOKEN]"))
    }

    func testSessionHistoryMaskingPolicyIncludesCoreRules() {
        let rules = ExternalToolSessionManager.sessionHistoryMaskingPolicyRules()
        let codes = Set(rules.map(\.code))

        XCTAssertTrue(codes.contains("openai_api_key"))
        XCTAssertTrue(codes.contains("github_token"))
        XCTAssertTrue(codes.contains("slack_token"))
        XCTAssertTrue(codes.contains("aws_access_key"))
        XCTAssertTrue(codes.contains("authorization_bearer"))
        XCTAssertTrue(codes.contains("generic_credential_kv"))
        XCTAssertTrue(codes.contains("private_key_block"))
    }

    func testBuildSessionHistoryChunksIndexesJsonlAndMasksContent() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-session-rag-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let repoRoot = temp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)

        let codexRoot = temp.appendingPathComponent(".codex/sessions/2026/02/19", isDirectory: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        let sessionFile = codexRoot.appendingPathComponent("sess-rag.jsonl")

        let raw = """
        {"type":"session_meta","payload":{"id":"sess-rag","cwd":"\(repoRoot.path)"}}
        {"type":"assistant_output","timestamp":"2026-02-19T09:00:00Z","content":"build failed token=shhh-super-secret-token"}
        {"type":"assistant_output","timestamp":"2026-02-19T09:01:00Z","content":"tests rerun and passed"}
        """
        try raw.data(using: .utf8)?.write(to: sessionFile, options: .atomic)

        let chunks = ExternalToolSessionManager.buildSessionHistoryChunks(
            codexSessionsRoot: temp.appendingPathComponent(".codex/sessions", isDirectory: true),
            claudeProjectsRoot: temp.appendingPathComponent(".claude/projects", isDirectory: true),
            managedRepositoryRoots: [repoRoot.path],
            limit: 20,
            now: Date()
        )

        XCTAssertFalse(chunks.isEmpty)
        let mergedContent = chunks.map(\.content).joined(separator: "\n")
        XCTAssertFalse(mergedContent.contains("shhh-super-secret-token"))
        XCTAssertTrue(mergedContent.contains("[REDACTED]"))
        XCTAssertTrue(chunks.contains(where: { $0.repositoryRoot == repoRoot.path }))
    }
}
