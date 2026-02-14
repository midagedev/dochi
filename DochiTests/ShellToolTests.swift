import XCTest
@testable import Dochi

@MainActor
final class ShellToolTests: XCTestCase {

    // MARK: - Properties

    func testToolName() {
        let tool = ShellCommandTool()
        XCTAssertEqual(tool.name, "shell.execute")
    }

    func testToolCategory() {
        let tool = ShellCommandTool()
        XCTAssertEqual(tool.category, .restricted)
    }

    func testToolIsNotBaseline() {
        let tool = ShellCommandTool()
        XCTAssertFalse(tool.isBaseline)
    }

    func testToolHasDescription() {
        let tool = ShellCommandTool()
        XCTAssertFalse(tool.description.isEmpty)
    }

    // MARK: - Input Schema

    func testInputSchemaRequiresCommand() {
        let tool = ShellCommandTool()
        let required = tool.inputSchema["required"] as? [String]
        XCTAssertEqual(required, ["command"])
    }

    func testInputSchemaHasTimeoutProperty() {
        let tool = ShellCommandTool()
        let properties = tool.inputSchema["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["timeout"])
    }

    func testInputSchemaHasWorkingDirectoryProperty() {
        let tool = ShellCommandTool()
        let properties = tool.inputSchema["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["working_directory"])
    }

    // MARK: - Parameter Validation

    func testMissingCommandReturnsError() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("command"))
    }

    func testEmptyCommandReturnsError() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": ""])
        XCTAssertTrue(result.isError)
    }

    func testInvalidWorkingDirectoryReturnsError() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: [
            "command": "echo test",
            "working_directory": "/nonexistent/dir",
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("작업 디렉토리"))
    }

    // MARK: - Blocked Commands

    func testBlocksRmRfRoot() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "rm -rf /"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("차단"))
    }

    func testBlocksSudo() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "sudo apt-get install something"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("차단"))
    }

    func testBlocksShutdown() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "shutdown -h now"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("차단"))
    }

    func testBlocksReboot() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "reboot"])
        XCTAssertTrue(result.isError)
    }

    func testBlocksMkfs() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "mkfs.ext4 /dev/sda1"])
        XCTAssertTrue(result.isError)
    }

    func testBlocksDd() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "dd if=/dev/zero of=/dev/sda"])
        XCTAssertTrue(result.isError)
    }

    func testBlocksForkBomb() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": ":(){:|:&};:"])
        XCTAssertTrue(result.isError)
    }

    func testBlocksCaseInsensitive() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "SUDO rm -rf /home"])
        XCTAssertTrue(result.isError)
    }

    // MARK: - Execution

    func testSimpleEcho() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "echo hello"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("hello"))
    }

    func testWorkingDirectory() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: [
            "command": "pwd",
            "working_directory": "/tmp",
        ])
        XCTAssertFalse(result.isError)
        // /tmp may resolve to /private/tmp on macOS
        XCTAssertTrue(result.content.contains("tmp"))
    }

    func testNonZeroExitCode() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "exit 42"])
        XCTAssertFalse(result.isError) // Tool reports result, not error
        XCTAssertTrue(result.content.contains("exit code: 42"))
    }

    func testStderrCapture() async {
        let tool = ShellCommandTool()
        let result = await tool.execute(arguments: ["command": "echo error_msg >&2"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("error_msg"))
        XCTAssertTrue(result.content.contains("stderr"))
    }

    // MARK: - Blocked Patterns List

    func testBlockedPatternsNotEmpty() {
        XCTAssertFalse(ShellCommandTool.blockedPatterns.isEmpty)
    }

    // MARK: - Registry Integration

    func testShellToolNotInBaseline() {
        let registry = ToolRegistry()
        registry.register(ShellCommandTool())
        XCTAssertTrue(registry.baselineTools.isEmpty)
    }

    func testShellToolAvailableAfterEnable() {
        let registry = ToolRegistry()
        registry.register(ShellCommandTool())
        registry.enable(names: ["shell.execute"])
        let available = registry.availableTools(for: ["safe", "sensitive", "restricted"])
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available[0].name, "shell.execute")
    }
}
