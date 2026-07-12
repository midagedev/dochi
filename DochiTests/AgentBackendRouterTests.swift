import XCTest
@testable import Dochi

@MainActor
final class AgentBackendRouterTests: XCTestCase {
    func testReconfigureAppliesOnlyToSelectedBackend() {
        let native = MockHermesBridge()
        let hermes = MockHermesBridge()
        let router = AgentBackendRouter(
            selectedKind: .native,
            native: native,
            hermes: hermes
        )

        router.reconfigure(host: "native-ignored", port: 1)

        XCTAssertEqual(native.reconfigureCallCount, 1)
        XCTAssertEqual(hermes.reconfigureCallCount, 0)

        router.select(.hermesRemote)
        router.reconfigure(host: "hermes.example", port: 9_001)

        XCTAssertEqual(native.disconnectCallCount, 1)
        XCTAssertEqual(hermes.connectCallCount, 2)
        XCTAssertEqual(hermes.reconfigureCallCount, 1)
    }

    func testInactiveBackendCannotOverwriteRouterConnectionState() {
        let native = MockHermesBridge()
        let hermes = MockHermesBridge()
        let router = AgentBackendRouter(
            selectedKind: .native,
            native: native,
            hermes: hermes
        )

        router.select(.hermesRemote)
        hermes.emitConnectionState(.connected(name: "Hermes"))
        native.emitConnectionState(.failed("stale native callback"))

        XCTAssertEqual(router.connectionState, .connected(name: "Hermes"))
    }

    func testConversationHistoryIsForwardedToSelectedBackend() {
        let native = MockHermesBridge()
        let hermes = MockHermesBridge()
        let router = AgentBackendRouter(
            selectedKind: .native,
            native: native,
            hermes: hermes
        )
        let history = [
            DochiAgentHistoryMessage(role: .user, text: "이전 질문"),
            DochiAgentHistoryMessage(role: .assistant, text: "이전 답변"),
        ]

        router.replaceConversationHistory(
            history,
            conversationId: "conversation",
            user: "user"
        )

        XCTAssertEqual(native.preparedHistories["conversation"], history)
        XCTAssertNil(hermes.preparedHistories["conversation"])
    }
}
