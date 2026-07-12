import XCTest
@testable import Dochi

@MainActor
final class DochiNativeAgentAssemblyTests: XCTestCase {
    func testCompatibleRootAndVersionedBasesProduceExpectedEndpoint() throws {
        XCTAssertEqual(
            try DochiCompatibleEndpoint.chatCompletionsEndpoint(from: "https://example.com"),
            URL(string: "https://example.com/v1/chat/completions")
        )
        XCTAssertEqual(
            try DochiCompatibleEndpoint.chatCompletionsEndpoint(from: "https://example.com/v1"),
            URL(string: "https://example.com/v1/chat/completions")
        )
    }

    func testExistingChatCompletionsEndpointIsNotDuplicated() throws {
        let endpoint = "https://example.com/custom/chat/completions"
        XCTAssertEqual(
            try DochiCompatibleEndpoint.chatCompletionsEndpoint(from: endpoint),
            URL(string: endpoint)
        )
    }

    func testCompatibleEndpointAllowsExternalHTTPSAndLoopbackHTTP() {
        let accepted = [
            "https://api.example.com/v1",
            "http://localhost:11434/v1",
            "http://model.localhost:11434/v1",
            "http://127.0.0.2:11434/v1",
            "http://127.255.255.255:11434/v1",
            "http://[::1]:11434/v1",
        ]
        for value in accepted {
            XCTAssertNoThrow(
                try DochiCompatibleEndpoint.chatCompletionsEndpoint(from: value),
                "Expected to accept \(value)"
            )
        }
    }

    func testCompatibleEndpointRejectsCredentialsQueryFragmentAndInsecureRemoteHTTP() {
        let rejected = [
            "http://api.example.com/v1",
            "http://128.0.0.1:11434/v1",
            "http://127.0.0.256:11434/v1",
            "https://user@example.com/v1",
            "https://user:password@example.com/v1",
            "https://example.com/v1?token=secret",
            "https://example.com/v1#fragment",
        ]
        for value in rejected {
            XCTAssertThrowsError(
                try DochiCompatibleEndpoint.chatCompletionsEndpoint(from: value),
                "Expected to reject \(value)"
            )
        }
    }

    func testMemoryApprovalSessionPrefersProvenanceConversation() {
        XCTAssertEqual(
            DochiNativeAgentAssembly.approvalSessionID(
                provenanceSessionID: "conversation-id",
                scopedSessionID: "scope-id"
            ),
            "conversation-id"
        )
        XCTAssertEqual(
            DochiNativeAgentAssembly.approvalSessionID(
                provenanceSessionID: "  ",
                scopedSessionID: "scope-id"
            ),
            "scope-id"
        )
        XCTAssertEqual(
            DochiNativeAgentAssembly.approvalSessionID(
                provenanceSessionID: nil,
                scopedSessionID: nil
            ),
            "memory"
        )
    }
}
