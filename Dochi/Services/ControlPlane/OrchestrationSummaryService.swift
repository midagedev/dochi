import Foundation

struct OrchestrationSummaryService: OrchestrationSummaryServiceProtocol, Sendable {
    let policy: OrchestrationSummaryPolicy

    init(policy: OrchestrationSummaryPolicy = .default) {
        self.policy = policy
    }

    func summarize(outputLines: [String]) -> OrchestrationOutputSummary {
        let normalizedLines = outputLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedLines.isEmpty else {
            let summary = "최근 출력이 없어 작업 결과를 판별할 수 없습니다."
            return OrchestrationOutputSummary(
                resultKind: .unknown,
                summary: summary,
                highlights: [],
                contextReflection: OrchestrationContextReflection(
                    conversationSummary: "[external-cli:unknown] \(summary)",
                    memoryCandidate: ""
                )
            )
        }

        let recent = Array(normalizedLines.suffix(max(1, policy.maxRecentLineCount)))
        let failureKeywords = lowercasedKeywords(policy.failureKeywords)
        let successKeywords = lowercasedKeywords(policy.successKeywords)
        let highlightKeywords = lowercasedKeywords(policy.highlightKeywords)

        let loweredLines = recent.map { $0.lowercased() }
        let hasFailure = loweredLines.contains(where: { line in
            failureKeywords.contains(where: { line.contains($0) })
        })
        let hasSuccess = loweredLines.contains(where: { line in
            successKeywords.contains(where: { line.contains($0) })
        })

        let resultKind: OrchestrationResultKind
        if hasFailure {
            resultKind = .failed
        } else if hasSuccess {
            resultKind = .succeeded
        } else {
            resultKind = .running
        }

        let highlights = extractHighlights(
            from: recent,
            failureKeywords: failureKeywords,
            successKeywords: successKeywords,
            highlightKeywords: highlightKeywords,
            maxHighlights: max(1, policy.maxHighlights)
        )

        let headline: String
        switch resultKind {
        case .failed:
            headline = "실패 신호가 감지되었습니다."
        case .succeeded:
            headline = "성공 신호가 확인되었습니다."
        case .running, .unknown:
            headline = "작업이 진행 중이거나 최종 상태가 불명확합니다."
        }

        let detail = highlights.joined(separator: " | ")
        let summary = detail.isEmpty ? headline : "\(headline) 핵심 출력: \(detail)"
        let contextReflection = OrchestrationContextReflection(
            conversationSummary: "[external-cli:\(resultKind.rawValue)] \(summary)",
            memoryCandidate: highlights.joined(separator: " | ")
        )

        return OrchestrationOutputSummary(
            resultKind: resultKind,
            summary: summary,
            highlights: highlights,
            contextReflection: contextReflection
        )
    }

    func makeStatusContract(outputLines: [String]) -> OrchestrationStatusContractPayload {
        let summary = summarize(outputLines: outputLines)
        return OrchestrationStatusContractPayload(
            resultKind: summary.resultKind.rawValue,
            summary: summary.summary,
            highlights: summary.highlights
        )
    }

    func makeSummarizeContract(outputLines: [String]) -> OrchestrationSummarizeContractPayload {
        let summary = summarize(outputLines: outputLines)
        return OrchestrationSummarizeContractPayload(
            resultKind: summary.resultKind.rawValue,
            summary: summary.summary,
            highlights: summary.highlights,
            contextReflection: summary.contextReflection
        )
    }

    private func extractHighlights(
        from lines: [String],
        failureKeywords: [String],
        successKeywords: [String],
        highlightKeywords: [String],
        maxHighlights: Int
    ) -> [String] {
        var highlights: [String] = []
        for line in lines.reversed() {
            if highlights.count >= maxHighlights { break }
            let loweredLine = line.lowercased()
            let shouldInclude =
                failureKeywords.contains(where: { loweredLine.contains($0) }) ||
                successKeywords.contains(where: { loweredLine.contains($0) }) ||
                highlightKeywords.contains(where: { loweredLine.contains($0) })
            if shouldInclude {
                highlights.append(line)
            }
        }

        if highlights.isEmpty, let lastLine = lines.last {
            return [lastLine]
        }

        return highlights.reversed()
    }

    private func lowercasedKeywords(_ keywords: [String]) -> [String] {
        keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}
