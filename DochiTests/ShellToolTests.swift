import XCTest
@testable import Dochi

@MainActor
final class ShellToolTests: XCTestCase {

    private var contextService: MockContextService!
    private var sessionContext: SessionContext!
    private var settings: AppSettings!

    override func setUp() {
        super.setUp()
        contextService = MockContextService()
        sessionContext = SessionContext(workspaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        settings = AppSettings()
        settings.activeAgentName = "도치"
    }

    private func makeTool() -> ShellCommandTool {
        ShellCommandTool(
            contextService: contextService,
            sessionContext: sessionContext,
            settings: settings
        )
    }

    // MARK: - Properties

    func testToolName() {
        let tool = makeTool()
        XCTAssertEqual(tool.name, "shell.execute")
    }

    func testToolCategory() {
        let tool = makeTool()
        XCTAssertEqual(tool.category, .restricted)
    }

    func testToolIsNotBaseline() {
        let tool = makeTool()
        XCTAssertFalse(tool.isBaseline)
    }

    func testToolHasDescription() {
        let tool = makeTool()
        XCTAssertFalse(tool.description.isEmpty)
    }

    // MARK: - Input Schema

    func testInputSchemaRequiresCommand() {
        let tool = makeTool()
        let required = tool.inputSchema["required"] as? [String]
        XCTAssertEqual(required, ["command"])
    }

    func testInputSchemaHasTimeoutProperty() {
        let tool = makeTool()
        let properties = tool.inputSchema["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["timeout"])
    }

    func testInputSchemaHasWorkingDirectoryProperty() {
        let tool = makeTool()
        let properties = tool.inputSchema["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["working_directory"])
    }

    // MARK: - Parameter Validation

    func testMissingCommandReturnsError() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("command"))
    }

    func testEmptyCommandReturnsError() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": ""])
        XCTAssertTrue(result.isError)
    }

    func testInvalidWorkingDirectoryReturnsError() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: [
            "command": "echo test",
            "working_directory": "/nonexistent/dir",
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("작업 디렉토리"))
    }

    // MARK: - Blocked Commands (default config)

    func testBlocksRmRfRoot() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "rm -rf /"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("차단"))
    }

    func testBlocksSudo() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "sudo apt-get install something"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("차단"))
    }

    func testBlocksShutdown() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "shutdown -h now"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("차단"))
    }

    func testBlocksReboot() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "reboot"])
        XCTAssertTrue(result.isError)
    }

    func testBlocksMkfs() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "mkfs.ext4 /dev/sda1"])
        XCTAssertTrue(result.isError)
    }

    func testBlocksDd() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "dd if=/dev/zero of=/dev/sda"])
        XCTAssertTrue(result.isError)
    }

    func testBlocksForkBomb() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": ":(){:|:&};:"])
        XCTAssertTrue(result.isError)
    }

    func testBlocksCaseInsensitive() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "SUDO rm -rf /home"])
        XCTAssertTrue(result.isError)
    }

    // MARK: - Execution

    func testSimpleEcho() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "echo hello"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("hello"))
    }

    func testWorkingDirectory() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: [
            "command": "pwd",
            "working_directory": "/tmp",
        ])
        XCTAssertFalse(result.isError)
        // /tmp may resolve to /private/tmp on macOS
        XCTAssertTrue(result.content.contains("tmp"))
    }

    func testNonZeroExitCode() async {
        let tool = makeTool()
        tool.confirmationHandler = { _, _ in true }
        let result = await tool.execute(arguments: ["command": "exit 42"])
        XCTAssertFalse(result.isError) // Tool reports result, not error
        XCTAssertTrue(result.content.contains("exit code: 42"))
    }

    func testStderrCapture() async {
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "echo error_msg >&2"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("error_msg"))
        XCTAssertTrue(result.content.contains("stderr"))
    }

    // MARK: - ShellPermissionConfig Integration

    func testCustomBlockedCommandBlocks() async {
        // Set up custom agent config with custom shell permissions
        let wsId = sessionContext.workspaceId
        let customShell = ShellPermissionConfig(
            blockedCommands: ["npm publish"],
            confirmCommands: [],
            allowedCommands: []
        )
        let config = AgentConfig(name: "도치", shellPermissions: customShell)
        contextService.saveAgentConfig(workspaceId: wsId, config: config)

        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "npm publish"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("차단"))
    }

    func testCustomAllowedCommandSkipsConfirmation() async {
        let wsId = sessionContext.workspaceId
        let customShell = ShellPermissionConfig(
            blockedCommands: [],
            confirmCommands: [],
            allowedCommands: ["echo "]
        )
        let config = AgentConfig(name: "도치", shellPermissions: customShell)
        contextService.saveAgentConfig(workspaceId: wsId, config: config)

        let tool = makeTool()
        // Set a confirmation handler that would deny — but allowed commands should skip it
        tool.confirmationHandler = { _, _ in false }
        let result = await tool.execute(arguments: ["command": "echo hello"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("hello"))
    }

    func testCustomConfirmCommandWithDenial() async {
        let wsId = sessionContext.workspaceId
        let customShell = ShellPermissionConfig(
            blockedCommands: [],
            confirmCommands: ["deploy"],
            allowedCommands: []
        )
        let config = AgentConfig(name: "도치", shellPermissions: customShell)
        contextService.saveAgentConfig(workspaceId: wsId, config: config)

        let tool = makeTool()
        tool.confirmationHandler = { _, _ in false }
        let result = await tool.execute(arguments: ["command": "deploy production"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("거부"))
    }

    func testCustomConfirmCommandWithApproval() async {
        let wsId = sessionContext.workspaceId
        let customShell = ShellPermissionConfig(
            blockedCommands: [],
            confirmCommands: ["deploy"],
            allowedCommands: []
        )
        let config = AgentConfig(name: "도치", shellPermissions: customShell)
        contextService.saveAgentConfig(workspaceId: wsId, config: config)

        let tool = makeTool()
        tool.confirmationHandler = { _, _ in true }
        // "deploy" would normally fail because there's no actual deploy command, but it shouldn't be blocked
        let result = await tool.execute(arguments: ["command": "echo deploy simulation"])
        // Even though "deploy" is in confirm list, "echo deploy simulation" won't match because
        // it doesn't start with "deploy" — it starts with "echo". Let's test with proper match.
        let result2 = await tool.execute(arguments: ["command": "deploy staging"])
        // deploy command likely doesn't exist, but the point is it wasn't blocked — it tries to run
        XCTAssertFalse(result2.content.contains("차단"))
        XCTAssertFalse(result2.content.contains("거부"))
    }

    func testDefaultCategoryWithDenial() async {
        let wsId = sessionContext.workspaceId
        let customShell = ShellPermissionConfig(
            blockedCommands: [],
            confirmCommands: [],
            allowedCommands: []
        )
        let config = AgentConfig(name: "도치", shellPermissions: customShell)
        contextService.saveAgentConfig(workspaceId: wsId, config: config)

        let tool = makeTool()
        tool.confirmationHandler = { _, _ in false }
        let result = await tool.execute(arguments: ["command": "echo hello"])
        // With empty lists, command falls to defaultCategory which asks for confirmation
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("거부"))
    }

    func testNoAgentConfigUsesDefaults() async {
        // No agent config saved — should use ShellPermissionConfig.default
        let tool = makeTool()
        let result = await tool.execute(arguments: ["command": "sudo rm -rf /"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("차단"))
    }

    // MARK: - Nil Handler Safety

    func testConfirmCommandBlockedWhenNoHandler() async {
        let wsId = sessionContext.workspaceId
        let customShell = ShellPermissionConfig(
            blockedCommands: [],
            confirmCommands: ["deploy"],
            allowedCommands: []
        )
        let config = AgentConfig(name: "도치", shellPermissions: customShell)
        contextService.saveAgentConfig(workspaceId: wsId, config: config)

        let tool = makeTool()
        // confirmationHandler is nil — should block, not execute
        let result = await tool.execute(arguments: ["command": "deploy production"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("확인 핸들러"))
    }

    func testDefaultCategoryBlockedWhenNoHandler() async {
        let wsId = sessionContext.workspaceId
        let customShell = ShellPermissionConfig(
            blockedCommands: [],
            confirmCommands: [],
            allowedCommands: []
        )
        let config = AgentConfig(name: "도치", shellPermissions: customShell)
        contextService.saveAgentConfig(workspaceId: wsId, config: config)

        let tool = makeTool()
        // confirmationHandler is nil — should block, not execute
        let result = await tool.execute(arguments: ["command": "python3 script.py"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("확인 핸들러"))
    }

    // MARK: - Registry Integration

    func testShellToolNotInBaseline() {
        let registry = ToolRegistry()
        registry.register(makeTool())
        XCTAssertTrue(registry.baselineTools.isEmpty)
    }

    func testShellToolAvailableAfterEnable() {
        let registry = ToolRegistry()
        registry.register(makeTool())
        registry.enable(names: ["shell.execute"])
        let available = registry.availableTools(for: ["safe", "sensitive", "restricted"])
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available[0].name, "shell.execute")
    }
}
