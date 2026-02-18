import XCTest
@testable import Dochi

@MainActor
final class ProjectContextToolTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiProjectContextTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testGitStatusUsesSessionContextRepoPathByDefault() async throws {
        let repo = try makeGitRepo(named: "repo-a", branch: "repo-a-branch")
        let sessionContext = SessionContext(workspaceId: UUID(), currentRepoPath: repo.path)
        let tool = GitStatusTool(sessionContext: sessionContext)

        let result = await tool.execute(arguments: [:])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("repo-a-branch"), "Expected branch from sessionContext repo path")
    }

    func testGitStatusPrioritizesExplicitRepoPathOverSessionContext() async throws {
        let repoA = try makeGitRepo(named: "repo-a", branch: "repo-a-branch")
        let repoB = try makeGitRepo(named: "repo-b", branch: "repo-b-branch")

        let sessionContext = SessionContext(workspaceId: UUID(), currentRepoPath: repoA.path)
        let tool = GitStatusTool(sessionContext: sessionContext)

        let result = await tool.execute(arguments: ["repo_path": repoB.path])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("repo-b-branch"), "Explicit repo_path should override sessionContext repo path")
    }

    func testCodingReviewUsesSessionContextRepoPathWhenWorkDirMissing() async {
        let missingPath = tempDir.appendingPathComponent("missing-repo").path
        let sessionContext = SessionContext(workspaceId: UUID(), currentRepoPath: missingPath)
        let tool = CodingReviewTool(sessionContext: sessionContext)

        let result = await tool.execute(arguments: [:])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("디렉토리를 찾을 수 없습니다"))
        XCTAssertTrue(result.content.contains("missing-repo"))
    }

    func testCodingReviewFailsWhenNoWorkDirAndNoProjectContext() async {
        let tool = CodingReviewTool(sessionContext: SessionContext(workspaceId: UUID()))

        let result = await tool.execute(arguments: [:])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("work_dir 파라미터가 필요합니다"))
    }

    // MARK: - Helpers

    private func makeGitRepo(named name: String, branch: String) throws -> URL {
        let repoURL = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try runGit(["init"], at: repoURL)
        try runGit(["checkout", "-b", branch], at: repoURL)

        // Create a tracked file so status/log commands behave consistently.
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "# \(name)".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: repoURL)
        try runGit(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "init"], at: repoURL)

        return repoURL
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "ProjectContextToolTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git command failed: \(arguments.joined(separator: " "))\n\(stderr)"]
            )
        }
    }
}
