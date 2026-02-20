import XCTest
@testable import Dochi

@MainActor
final class ContextCompactionServiceTests: XCTestCase {
    private var service: ContextCompactionService!

    override func setUp() {
        super.setUp()
        service = ContextCompactionService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testEstimatorCountsMessageAndTextTokens() {
        let textTokens = service.estimateTokens(for: String(repeating: "가", count: 200))
        XCTAssertEqual(textTokens, 100)

        let messages = [
            NativeLLMMessage(role: .user, text: String(repeating: "u", count: 120)),
            NativeLLMMessage(role: .assistant, text: String(repeating: "a", count: 80)),
        ]
        XCTAssertEqual(service.estimateTokens(for: messages), 100)
    }

    func testLayerPriorityCompactsPersonalBeforeWorkspace() {
        let result = service.compact(
            request: ContextCompactionRequest(
                workspaceMemory: String(repeating: "W", count: 6_000),
                agentMemory: String(repeating: "A", count: 6_000),
                personalMemory: String(repeating: "P", count: 6_000),
                messages: [NativeLLMMessage(role: .user, text: "hi")],
                tokenBudget: 1_200,
                fixedPromptTokens: 200,
                autoCompactEnabled: true,
                conversationSummary: nil
            )
        )

        XCTAssertTrue(result.metrics.truncatedWorkspaceMemory)
        XCTAssertTrue(result.metrics.truncatedAgentMemory)
        XCTAssertTrue(result.metrics.truncatedPersonalMemory)
        XCTAssertGreaterThan(result.layers.workspaceMemory.count, result.layers.agentMemory.count)
        XCTAssertGreaterThan(result.layers.agentMemory.count, result.layers.personalMemory.count)
    }

    func testCompactionAddsSummarySnapshotWhenDroppingOldMessages() {
        let oversizedMessages = (0..<10).map { index in
            NativeLLMMessage(
                role: index % 2 == 0 ? .user : .assistant,
                text: "message-\(index) " + String(repeating: "x", count: 900)
            )
        }

        let result = service.compact(
            request: ContextCompactionRequest(
                workspaceMemory: "",
                agentMemory: "",
                personalMemory: "",
                messages: oversizedMessages,
                tokenBudget: 1_400,
                fixedPromptTokens: 300,
                autoCompactEnabled: true,
                conversationSummary: nil
            )
        )

        XCTAssertGreaterThan(result.metrics.droppedMessageCount, 0)
        XCTAssertTrue(result.metrics.usedSummaryFallback)
        XCTAssertNotNil(result.summarySnapshot)
        XCTAssertEqual(result.messages.first?.role, .assistant)
        let firstText: String = {
            guard let first = result.messages.first else { return "" }
            return first.contents.map {
                if case .text(let text) = $0 { return text }
                return ""
            }.joined()
        }()
        XCTAssertTrue(firstText.contains("요약 스냅샷"))
    }

    func testFailSafeKeepsRequestWithinBudgetEvenWhenAutoCompactIsDisabled() {
        let hugeLastMessage = NativeLLMMessage(
            role: .user,
            text: String(repeating: "L", count: 12_000)
        )
        let messages = [
            NativeLLMMessage(role: .assistant, text: String(repeating: "A", count: 6_000)),
            hugeLastMessage,
        ]

        let result = service.compact(
            request: ContextCompactionRequest(
                workspaceMemory: String(repeating: "W", count: 2_000),
                agentMemory: "",
                personalMemory: "",
                messages: messages,
                tokenBudget: 1_000,
                fixedPromptTokens: 500,
                autoCompactEnabled: false,
                conversationSummary: "이전 대화는 길어서 축약되었습니다."
            )
        )

        XCTAssertFalse(result.messages.isEmpty)
        XCTAssertEqual(result.messages.last?.role, .user)
        XCTAssertLessThanOrEqual(result.metrics.estimatedInputTokensAfter, result.metrics.tokenBudget)
        XCTAssertTrue(result.metrics.didCompact)
    }
}
