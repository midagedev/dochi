import XCTest
@testable import Dochi

final class CLICommandSurfaceTests: XCTestCase {

    func testParseHelpWhenNoArgs() throws {
        let invocation = try CLICommandParser.parse([])
        XCTAssertEqual(invocation.command, .help)
        XCTAssertEqual(invocation.outputMode, .text)
        XCTAssertEqual(invocation.runtimeMode, .auto)
    }

    func testParseAskCommandWithJsonAndMode() throws {
        let invocation = try CLICommandParser.parse(["--json", "--mode", "app", "ask", "hello", "world"])
        XCTAssertEqual(invocation.outputMode, .json)
        XCTAssertEqual(invocation.runtimeMode, .app)
        XCTAssertEqual(invocation.command, .ask(query: "hello world"))
    }

    func testParseFreeTextAsAsk() throws {
        let invocation = try CLICommandParser.parse(["안녕", "도치"])
        XCTAssertEqual(invocation.command, .ask(query: "안녕 도치"))
    }

    func testParseConfigSet() throws {
        let invocation = try CLICommandParser.parse(["config", "set", "model", "gpt-4.1"])
        XCTAssertEqual(invocation.command, .config(.set(key: "model", value: "gpt-4.1")))
    }

    func testParseConversationListWithLimit() throws {
        let invocation = try CLICommandParser.parse(["conversation", "list", "--limit", "25"])
        XCTAssertEqual(invocation.command, .conversation(.list(limit: 25)))
    }

    func testParseDevBridgeSend() throws {
        let invocation = try CLICommandParser.parse(["dev", "bridge", "send", "abc-123", "run", "tests"])
        XCTAssertEqual(invocation.command, .dev(.bridgeSend(sessionId: "abc-123", command: "run tests")))
    }

    func testParseInvalidModeThrows() {
        XCTAssertThrowsError(try CLICommandParser.parse(["--mode", "invalid", "ask", "hi"])) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("지원하지 않는 모드"))
        }
    }

    func testParseInvalidConfigUsageThrows() {
        XCTAssertThrowsError(try CLICommandParser.parse(["config", "set", "model"])) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("config set"))
        }
    }
}
