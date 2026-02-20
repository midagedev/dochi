import Foundation

enum OrchestrationResultKind: String, Sendable {
    case unknown
    case running
    case succeeded
    case failed
}

struct OrchestrationContextReflection: Sendable, Equatable {
    let conversationSummary: String
    let memoryCandidate: String
}

struct OrchestrationOutputSummary: Sendable, Equatable {
    let resultKind: OrchestrationResultKind
    let summary: String
    let highlights: [String]
    let contextReflection: OrchestrationContextReflection
}

struct OrchestrationStatusContractPayload: Sendable, Equatable {
    let resultKind: String
    let summary: String
    let highlights: [String]
}

struct OrchestrationSummarizeContractPayload: Sendable, Equatable {
    let resultKind: String
    let summary: String
    let highlights: [String]
    let contextReflection: OrchestrationContextReflection
}

struct OrchestrationSummaryPolicy: Sendable, Equatable {
    let failureKeywords: [String]
    let successKeywords: [String]
    let highlightKeywords: [String]
    let maxRecentLineCount: Int
    let maxHighlights: Int

    static let `default` = OrchestrationSummaryPolicy(
        failureKeywords: ["error", "failed", "exception", "traceback", "panic", "fatal", "test failed", "build failed"],
        successKeywords: ["success", "completed", "done", "passed", "all checks passed", "merged"],
        highlightKeywords: ["warning", "todo"],
        maxRecentLineCount: 80,
        maxHighlights: 3
    )
}

protocol OrchestrationSummaryServiceProtocol: Sendable {
    func summarize(outputLines: [String]) -> OrchestrationOutputSummary
    func makeStatusContract(outputLines: [String]) -> OrchestrationStatusContractPayload
    func makeSummarizeContract(outputLines: [String]) -> OrchestrationSummarizeContractPayload
}
