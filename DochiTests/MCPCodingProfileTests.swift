import XCTest
@testable import Dochi

final class MCPCodingProfileTests: XCTestCase {
    func testCodingDefaultProfilesIncludeFilesystemGitAndShell() {
        let profiles = MCPServerConfig.codingDefaultProfiles(
            workspaceRoot: "/tmp/dochi-workspace",
            gitRepositoryPath: "/tmp/dochi-workspace"
        )

        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(Set(profiles.map(\.name)), Set(["coding-filesystem", "coding-git", "coding-shell"]))
    }

    func testCodingDefaultProfilesEnableGitWhenRepositoryIsProvided() {
        let profiles = MCPServerConfig.codingDefaultProfiles(
            workspaceRoot: "/tmp/dochi-workspace",
            gitRepositoryPath: "/tmp/dochi-workspace/repo"
        )

        guard let gitProfile = profiles.first(where: { $0.name == "coding-git" }) else {
            return XCTFail("Expected coding-git profile")
        }
        XCTAssertTrue(gitProfile.isEnabled)
        XCTAssertEqual(gitProfile.command, "uvx")
        XCTAssertTrue(gitProfile.arguments.contains("/tmp/dochi-workspace/repo"))
    }

    func testCodingDefaultProfilesDisableGitWhenRepositoryIsMissing() {
        let profiles = MCPServerConfig.codingDefaultProfiles(
            workspaceRoot: "/tmp/dochi-workspace",
            gitRepositoryPath: nil
        )

        guard let gitProfile = profiles.first(where: { $0.name == "coding-git" }) else {
            return XCTFail("Expected coding-git profile")
        }
        XCTAssertFalse(gitProfile.isEnabled)
    }
}
