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

    func testParseDevBridgeOpenWithOptions() throws {
        let invocation = try CLICommandParser.parse([
            "dev", "bridge", "open", "codex",
            "--profile", "Dochi Bridge Codex",
            "--cwd", "~/repo/dochi",
            "--force-working-directory",
        ])
        XCTAssertEqual(
            invocation.command,
            .dev(.bridgeOpen(
                agent: "codex",
                profileName: "Dochi Bridge Codex",
                workingDirectory: "~/repo/dochi",
                forceWorkingDirectory: true
            ))
        )
    }

    func testParseDevBridgeOpenWithoutOptionsDefaultsToCodex() throws {
        let invocation = try CLICommandParser.parse(["dev", "bridge", "open"])
        XCTAssertEqual(
            invocation.command,
            .dev(.bridgeOpen(agent: "codex", profileName: nil, workingDirectory: nil, forceWorkingDirectory: false))
        )
    }

    func testParseDevBridgeRootsWithOptions() throws {
        let invocation = try CLICommandParser.parse([
            "dev", "bridge", "roots",
            "--limit", "15",
            "--path", "~/repo",
            "--path", "~/work",
        ])
        XCTAssertEqual(
            invocation.command,
            .dev(.bridgeRoots(limit: 15, searchPaths: ["~/repo", "~/work"]))
        )
    }

    func testParseDevChatStream() throws {
        let invocation = try CLICommandParser.parse(["dev", "chat", "stream", "실시간", "테스트"])
        XCTAssertEqual(invocation.command, .dev(.chatStream(prompt: "실시간 테스트")))
    }

    func testParseDevLogTailWithOptions() throws {
        let invocation = try CLICommandParser.parse([
            "dev", "log", "tail",
            "--seconds", "20",
            "--category", "Tool",
            "--level", "info",
            "--contains", "cid:abc",
        ])
        XCTAssertEqual(
            invocation.command,
            .dev(.logTail(seconds: 20, category: "Tool", level: "info", contains: "cid:abc"))
        )
    }

    func testParseInvalidModeThrows() {
        XCTAssertThrowsError(try CLICommandParser.parse(["--mode", "invalid", "ask", "hi"])) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("지원하지 않는 모드"))
        }
    }

    func testParseStandaloneWithoutAllowFlagThrows() {
        XCTAssertThrowsError(try CLICommandParser.parse(["--mode", "standalone", "ask", "hi"], environment: [:])) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("--allow-standalone"))
        }
    }

    func testParseStandaloneWithAllowFlagPasses() throws {
        let invocation = try CLICommandParser.parse(["--mode", "standalone", "--allow-standalone", "ask", "hi"], environment: [:])
        XCTAssertEqual(invocation.runtimeMode, .standalone)
        XCTAssertEqual(invocation.command, .ask(query: "hi"))
    }

    func testParseStandaloneWithEnvironmentFlagPasses() throws {
        let invocation = try CLICommandParser.parse(
            ["--mode", "standalone", "ask", "hi"],
            environment: ["DOCHI_CLI_ALLOW_STANDALONE": "1"]
        )
        XCTAssertEqual(invocation.runtimeMode, .standalone)
        XCTAssertEqual(invocation.command, .ask(query: "hi"))
    }

    func testParseInvalidConfigUsageThrows() {
        XCTAssertThrowsError(try CLICommandParser.parse(["config", "set", "model"])) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("config set"))
        }
    }
}
