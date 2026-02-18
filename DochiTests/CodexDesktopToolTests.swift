import XCTest
@testable import Dochi

@MainActor
final class CodexDesktopToolTests: XCTestCase {

    func testActivateToolMetadata() {
        let tool = CodexDesktopActivateTool()
        XCTAssertEqual(tool.name, "codex.desktop_activate")
        XCTAssertEqual(tool.category, .sensitive)
        XCTAssertFalse(tool.isBaseline)
    }

    func testActivateUsesDefaultAppName() async {
        var capturedArgs: [String] = []
        let tool = CodexDesktopActivateTool { _, args in
            capturedArgs = args
            return .success("OK")
        }

        let result = await tool.execute(arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertEqual(capturedArgs, ["Codex"])
        XCTAssertTrue(result.content.contains("Codex"))
    }

    func testActivateMapsNotFoundError() async {
        let tool = CodexDesktopActivateTool { _, _ in
            .failure(AppleScriptError(message: "Can’t get application \"Codex\"."))
        }

        let result = await tool.execute(arguments: ["app_name": "Codex"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("앱을 찾을 수 없습니다"))
    }

    func testSendPromptToolMetadata() {
        let tool = CodexDesktopSendPromptTool()
        XCTAssertEqual(tool.name, "codex.desktop_send_prompt")
        XCTAssertEqual(tool.category, .restricted)
        XCTAssertFalse(tool.isBaseline)
    }

    func testSendPromptRequiresPrompt() async {
        var callCount = 0
        let tool = CodexDesktopSendPromptTool { _, _ in
            callCount += 1
            return .success("OK")
        }

        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("prompt"))
        XCTAssertEqual(callCount, 0)
    }

    func testSendPromptPassesDefaultArguments() async {
        var capturedSource = ""
        var capturedArgs: [String] = []
        let tool = CodexDesktopSendPromptTool { source, args in
            capturedSource = source
            capturedArgs = args
            return .success("OK")
        }

        let result = await tool.execute(arguments: ["prompt": "테스트 메시지"])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(capturedSource.contains("keystroke \"v\""))
        XCTAssertEqual(capturedArgs.count, 5)
        XCTAssertEqual(capturedArgs[0], "Codex")
        XCTAssertEqual(capturedArgs[1], "테스트 메시지")
        XCTAssertEqual(capturedArgs[2], "true")
        XCTAssertEqual(capturedArgs[3], "false")
        XCTAssertEqual(capturedArgs[4], "350")
        XCTAssertTrue(result.content.contains("전송"))
    }

    func testSendPromptPassesCustomArguments() async {
        var capturedArgs: [String] = []
        let tool = CodexDesktopSendPromptTool { _, args in
            capturedArgs = args
            return .success("OK")
        }

        let _ = await tool.execute(arguments: [
            "prompt": "custom",
            "app_name": "Codex Beta",
            "submit": false,
            "new_chat": true,
            "activation_delay_ms": 1200,
        ])

        XCTAssertEqual(capturedArgs[0], "Codex Beta")
        XCTAssertEqual(capturedArgs[1], "custom")
        XCTAssertEqual(capturedArgs[2], "false")
        XCTAssertEqual(capturedArgs[3], "true")
        XCTAssertEqual(capturedArgs[4], "1200")
    }

    func testSendPromptClampsDelayRange() async {
        var capturedArgs: [String] = []
        let tool = CodexDesktopSendPromptTool { _, args in
            capturedArgs = args
            return .success("OK")
        }

        let _ = await tool.execute(arguments: [
            "prompt": "clamp",
            "activation_delay_ms": 99_999,
        ])
        XCTAssertEqual(capturedArgs[4], "5000")

        let _ = await tool.execute(arguments: [
            "prompt": "clamp2",
            "activation_delay_ms": -5,
        ])
        XCTAssertEqual(capturedArgs[4], "0")
    }

    func testSendPromptMapsAccessibilityError() async {
        let tool = CodexDesktopSendPromptTool { _, _ in
            .failure(AppleScriptError(message: "ACCESSIBILITY_DISABLED"))
        }

        let result = await tool.execute(arguments: ["prompt": "hello"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("접근성"))
    }
}
