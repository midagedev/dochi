import XCTest
@testable import Dochi

final class TelegramBridgeCommandParserTests: XCTestCase {
    func testRouteReturnsNotCommandForPlainText() {
        let route = TelegramBridgeCommandParser.route("안녕 도치")
        XCTAssertEqual(route, .notCommand)
    }

    func testParsesBridgeSendCommand() {
        let route = TelegramBridgeCommandParser.route("/bridge send 1111-2222 git status --short")

        guard case .command(.bridgeSend(let sessionId, let command)) = route else {
            return XCTFail("expected bridgeSend command")
        }
        XCTAssertEqual(sessionId, "1111-2222")
        XCTAssertEqual(command, "git status --short")
    }

    func testParsesBridgeOpenWithFlags() {
        let route = TelegramBridgeCommandParser.route(
            "/bridge open --agent codex --profile dev-main --cwd /tmp/repo --force-cwd"
        )

        guard case .command(.bridgeOpen(let agent, let profileName, let workingDirectory, let forceWorkingDirectory)) = route else {
            return XCTFail("expected bridgeOpen command")
        }
        XCTAssertEqual(agent, "codex")
        XCTAssertEqual(profileName, "dev-main")
        XCTAssertEqual(workingDirectory, "/tmp/repo")
        XCTAssertTrue(forceWorkingDirectory)
    }

    func testParsesOrchRequestWithRepoAndTTL() {
        let route = TelegramBridgeCommandParser.route("/orch request npm run test --repo /tmp/repo --ttl 180")

        guard case .command(.orchRequest(let command, let repositoryRoot, let ttlSeconds)) = route else {
            return XCTFail("expected orchRequest command")
        }
        XCTAssertEqual(command, "npm run test")
        XCTAssertEqual(repositoryRoot, "/tmp/repo")
        XCTAssertEqual(ttlSeconds, 180)
    }

    func testParsesOrchExecuteWithApproval() {
        let route = TelegramBridgeCommandParser.route(
            "/orch execute git status --repo /tmp/repo --approval-id abc-123 --confirmed"
        )

        guard case .command(.orchExecute(let command, let repositoryRoot, let confirmed, let approvalId)) = route else {
            return XCTFail("expected orchExecute command")
        }
        XCTAssertEqual(command, "git status")
        XCTAssertEqual(repositoryRoot, "/tmp/repo")
        XCTAssertEqual(approvalId, "abc-123")
        XCTAssertTrue(confirmed)
    }

    func testReturnsUsageErrorForInvalidBridgeCommand() {
        let route = TelegramBridgeCommandParser.route("/bridge unknown")

        guard case .usageError(let usage) = route else {
            return XCTFail("expected usageError")
        }
        XCTAssertTrue(usage.contains("/bridge open"))
    }
}
