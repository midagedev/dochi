import Foundation
import os

// MARK: - MemoryCandidateExtractor

/// 대화 종료 시 및 PostToolUse 이벤트에서 메모리 후보를 추출한다.
@MainActor
final class MemoryCandidateExtractor {

    static let minMessageCount = 3
    static let maxCandidates = 15
    static let minToolResultLength = 20

    // MARK: - Extract from Conversation

    /// 대화에서 메모리 후보를 추출한다.
    func extractFromConversation(
        messages: [Message],
        sessionId: String,
        workspaceId: String,
        agentId: String?,
        userId: String?
    ) -> [MemoryCandidate] {
        let relevant = messages.filter { $0.role == .user || $0.role == .assistant }
        guard relevant.count >= Self.minMessageCount else {
            Log.storage.debug("메모리 추출 생략: 메시지 부족 (\(relevant.count)/\(Self.minMessageCount))")
            return []
        }

        var candidates: [MemoryCandidate] = []

        for message in relevant where message.role == .user {
            let lines = extractFactLines(message.content)
            for line in lines {
                candidates.append(MemoryCandidate(
                    content: line,
                    source: .conversation,
                    sessionId: sessionId,
                    workspaceId: workspaceId,
                    agentId: agentId,
                    userId: userId
                ))
            }
        }

        for message in relevant where message.role == .assistant {
            let lines = extractUserFactsFromAssistant(message.content)
            for line in lines {
                candidates.append(MemoryCandidate(
                    content: line,
                    source: .conversation,
                    sessionId: sessionId,
                    workspaceId: workspaceId,
                    agentId: agentId,
                    userId: userId
                ))
            }
        }

        let result = Array(candidates.prefix(Self.maxCandidates))
        Log.storage.debug("대화에서 메모리 후보 \(result.count)건 추출")
        return result
    }

    // MARK: - Extract from Tool Result

    /// PostToolUse 훅에서 도구 결과를 메모리 후보로 변환한다.
    func extractFromToolResult(
        toolName: String,
        result: String,
        sessionId: String,
        workspaceId: String,
        agentId: String?,
        userId: String?
    ) -> [MemoryCandidate] {
        guard result.count >= Self.minToolResultLength else { return [] }

        let memoryTools: Set<String> = [
            "save_memory", "update_memory", "delete_memory",
        ]

        if memoryTools.contains(toolName) {
            return [MemoryCandidate(
                content: result,
                source: .toolResult,
                sessionId: sessionId,
                workspaceId: workspaceId,
                agentId: agentId,
                userId: userId
            )]
        }

        let lines = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 10 }
            .prefix(5)

        return lines.map { line in
            MemoryCandidate(
                content: "\(toolName): \(line)",
                source: .toolResult,
                sessionId: sessionId,
                workspaceId: workspaceId,
                agentId: agentId,
                userId: userId
            )
        }
    }

    // MARK: - Private Extraction

    /// 텍스트에서 사실/선호/결정 라인을 추출 (규칙 기반)
    func extractFactLines(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var facts: [String] = []
        for line in lines {
            if containsPersonalPattern(line) || containsWorkspacePattern(line) {
                facts.append(line)
            }
        }

        return Array(facts.prefix(Self.maxCandidates))
    }

    /// 어시스턴트 메시지에서 사용자 관련 사실 추출
    private func extractUserFactsFromAssistant(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var facts: [String] = []
        for line in lines {
            if containsUserReferencePattern(line) {
                let cleaned = cleanAssistantFact(line)
                if !cleaned.isEmpty {
                    facts.append(cleaned)
                }
            }
        }

        return Array(facts.prefix(5))
    }

    // MARK: - Pattern Detection

    private func containsPersonalPattern(_ text: String) -> Bool {
        let patterns = [
            "나는 ", "내가 ", "제가 ", "저는 ", "내 ", "제 ",
            "좋아하", "싫어하", "선호하", "알레르기",
            "생일", "취미", "직업", "이름은",
        ]
        let lower = text.lowercased()
        return patterns.contains { lower.contains($0) }
    }

    private func containsWorkspacePattern(_ text: String) -> Bool {
        let patterns = [
            "프로젝트", "팀 ", "회의", "배포", "릴리스",
            "마감", "일정", "결정했", "합의",
            "아키텍처", "API ", "서버", "데이터베이스",
        ]
        let lower = text.lowercased()
        return patterns.contains { lower.contains($0) }
    }

    private func containsUserReferencePattern(_ text: String) -> Bool {
        let patterns = [
            "사용자는", "님은", "님이", "사용자가",
            "기억하겠습니다", "말씀하신", "선호하시는",
        ]
        return patterns.contains { text.contains($0) }
    }

    private func cleanAssistantFact(_ line: String) -> String {
        var cleaned = line
        let removePatterns = [
            "알겠습니다. ", "네, ", "기억하겠습니다. ",
            "말씀하신 대로 ", "확인했습니다. ",
        ]
        for pattern in removePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
