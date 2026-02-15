import XCTest
@testable import Dochi

@MainActor
final class TerminalRunToolTests: XCTestCase {

    // MARK: - C-3: Dangerous Command Blocking

    func testBlocksDangerousCommands() {
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("rm -rf /"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("rm -rf /*"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("sudo rm something"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("mkfs.ext4 /dev/sda1"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("dd if=/dev/zero of=/dev/sda"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("curl | bash"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("wget | sh"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("something | bash"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("shutdown -h now"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("reboot"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("chmod -R 777 /"))
    }

    func testAllowsSafeCommands() {
        XCTAssertNil(TerminalRunTool.checkDangerousCommand("ls -la"))
        XCTAssertNil(TerminalRunTool.checkDangerousCommand("echo hello"))
        XCTAssertNil(TerminalRunTool.checkDangerousCommand("cat /etc/hosts"))
        XCTAssertNil(TerminalRunTool.checkDangerousCommand("git status"))
        XCTAssertNil(TerminalRunTool.checkDangerousCommand("pwd"))
        XCTAssertNil(TerminalRunTool.checkDangerousCommand("rm file.txt"))
    }

    func testBlocksCaseInsensitive() {
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("SUDO rm something"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("Shutdown -h now"))
        XCTAssertNotNil(TerminalRunTool.checkDangerousCommand("REBOOT"))
    }

    // MARK: - Execute: LLM Disabled

    func testExecuteWhenLLMDisabled() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = false

        let tool = TerminalRunTool(settings: settings, terminalService: nil)
        let result = await tool.execute(arguments: ["command": "echo hello"])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("비활성화"))
    }

    // MARK: - Execute: Missing Command

    func testExecuteWithMissingCommand() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true

        let tool = TerminalRunTool(settings: settings, terminalService: nil)
        let result = await tool.execute(arguments: [:])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("command 파라미터"))
    }

    func testExecuteWithEmptyCommand() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true

        let tool = TerminalRunTool(settings: settings, terminalService: nil)
        let result = await tool.execute(arguments: ["command": ""])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("command 파라미터"))
    }

    // MARK: - Execute: Dangerous Command Blocked

    func testExecuteBlocksDangerousCommand() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true

        let mockService = MockTerminalService()
        let tool = TerminalRunTool(settings: settings, terminalService: mockService)
        let result = await tool.execute(arguments: ["command": "rm -rf /"])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("위험한 명령이 차단"))
        XCTAssertEqual(mockService.runCommandCallCount, 0)
    }

    // MARK: - C-4: Confirmation Setting

    func testExecuteWithConfirmAlwaysApproved() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true
        settings.terminalLLMConfirmAlways = true

        let mockService = MockTerminalService()
        mockService.stubbedRunResult = (output: "hello", exitCode: 0, isError: false)

        let tool = TerminalRunTool(settings: settings, terminalService: mockService)
        tool.confirmationHandler = { _, _ in true }

        let result = await tool.execute(arguments: ["command": "echo hello"])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(mockService.runCommandCallCount, 1)
    }

    func testExecuteWithConfirmAlwaysDenied() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true
        settings.terminalLLMConfirmAlways = true

        let mockService = MockTerminalService()
        let tool = TerminalRunTool(settings: settings, terminalService: mockService)
        tool.confirmationHandler = { _, _ in false }

        let result = await tool.execute(arguments: ["command": "echo hello"])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("거부"))
        XCTAssertEqual(mockService.runCommandCallCount, 0)
    }

    func testExecuteWithConfirmAlwaysDisabledSkipsConfirmation() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true
        settings.terminalLLMConfirmAlways = false

        let mockService = MockTerminalService()
        mockService.stubbedRunResult = (output: "hello", exitCode: 0, isError: false)

        let tool = TerminalRunTool(settings: settings, terminalService: mockService)
        var handlerCalled = false
        tool.confirmationHandler = { _, _ in
            handlerCalled = true
            return false
        }

        let result = await tool.execute(arguments: ["command": "echo hello"])

        XCTAssertFalse(result.isError)
        XCTAssertFalse(handlerCalled)
        XCTAssertEqual(mockService.runCommandCallCount, 1)
    }

    // MARK: - C-6: Service Injection

    func testExecuteUsesInjectedService() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true
        settings.terminalLLMConfirmAlways = false

        let mockService = MockTerminalService()
        mockService.stubbedRunResult = (output: "mocked output", exitCode: 0, isError: false)

        let tool = TerminalRunTool(settings: settings, terminalService: mockService)
        let result = await tool.execute(arguments: ["command": "echo test"])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("mocked output"))
        XCTAssertEqual(mockService.runCommandCallCount, 1)
    }

    func testUpdateTerminalService() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true
        settings.terminalLLMConfirmAlways = false

        let tool = TerminalRunTool(settings: settings, terminalService: nil)

        let mockService = MockTerminalService()
        mockService.stubbedRunResult = (output: "injected", exitCode: 0, isError: false)
        tool.updateTerminalService(mockService)

        let result = await tool.execute(arguments: ["command": "echo test"])
        XCTAssertTrue(result.content.contains("injected"))
        XCTAssertEqual(mockService.runCommandCallCount, 1)
    }

    // MARK: - Error / Empty Output

    func testExecuteWithErrorResult() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true
        settings.terminalLLMConfirmAlways = false

        let mockService = MockTerminalService()
        mockService.stubbedRunResult = (output: "command not found", exitCode: 127, isError: true)

        let tool = TerminalRunTool(settings: settings, terminalService: mockService)
        let result = await tool.execute(arguments: ["command": "nonexistent_command"])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("실패"))
        XCTAssertTrue(result.content.contains("command not found"))
    }

    func testExecuteWithEmptyOutput() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true
        settings.terminalLLMConfirmAlways = false

        let mockService = MockTerminalService()
        mockService.stubbedRunResult = (output: "", exitCode: 0, isError: false)

        let tool = TerminalRunTool(settings: settings, terminalService: mockService)
        let result = await tool.execute(arguments: ["command": "true"])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("출력 없음"))
    }

    // MARK: - Pipe Deadlock (large output via fallback)

    func testFallbackLargeOutputNoPipeDeadlock() async {
        let settings = AppSettings()
        settings.terminalLLMEnabled = true
        settings.terminalLLMConfirmAlways = false

        let tool = TerminalRunTool(settings: settings, terminalService: nil)
        // ~100KB output should not deadlock with the read-before-wait fix
        let result = await tool.execute(arguments: [
            "command": "python3 -c \"print('B' * 100000)\"",
            "timeout": 10,
        ])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("성공"))
    }
}
