import XCTest
@testable import Dochi

@MainActor
final class CodingAgentToolTests: XCTestCase {
    func testCopyTaskContext() async throws {
        let host = BuiltInToolService()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // create a couple of files
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("README.md").path, contents: Data(), attributes: nil)
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("Package.swift").path, contents: Data(), attributes: nil)

        let res = try await host.callTool(name: "coding.copy_task_context", arguments: [
            "task": "Implement quick test",
            "project_path": tmp.path,
            "include_git": false
        ])
        XCTAssertFalse(res.isError)
        XCTAssertTrue(res.content.contains("Copied task context"))
    }
}

