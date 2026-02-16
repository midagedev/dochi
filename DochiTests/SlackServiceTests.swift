import XCTest

final class SlackServiceTests: XCTestCase {
    func testSlackIntegrationIsNotShippedYet() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let serviceSource = try String(
            contentsOf: root.appendingPathComponent("Dochi/Services/Slack/SlackService.swift"),
            encoding: .utf8
        )
        let protocolSource = try String(
            contentsOf: root.appendingPathComponent("Dochi/Services/Protocols/SlackServiceProtocol.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(serviceSource.contains("final class SlackService"))
        XCTAssertFalse(protocolSource.contains("protocol SlackServiceProtocol"))
        XCTAssertTrue(serviceSource.contains("prototype removed"))
    }
}
