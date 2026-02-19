import Foundation
import os

// MARK: - LayerClassifier

/// 규칙 기반 메모리 후보 분류기.
/// 후보를 personal / workspace / agent / drop 으로 분류한다.
@MainActor
final class LayerClassifier {

    // MARK: - Classification Rules

    private static let personalKeywords: Set<String> = [
        "선호", "좋아하", "싫어하", "알레르기", "생일", "취미",
        "나는", "제가", "내가", "저는", "내 ", "제 ",
        "prefer", "like", "dislike", "birthday", "hobby",
        "my ", "i am", "i'm", "알려줘", "기억해",
        "습관", "성격", "이름은", "나이는", "직업은",
    ]

    private static let workspaceKeywords: Set<String> = [
        "프로젝트", "팀", "회의", "결정", "일정", "마감",
        "project", "team", "meeting", "decision", "deadline",
        "배포", "릴리스", "버전", "스프린트", "칸반",
        "release", "deploy", "version", "sprint", "kanban",
        "repository", "repo", "branch", "merge", "코드리뷰",
        "아키텍처", "설계", "API", "서버", "데이터베이스",
    ]

    private static let agentKeywords: Set<String> = [
        "학습", "패턴", "자주", "항상", "보통", "매번",
        "learn", "pattern", "usually", "always", "often",
        "이전에", "지난번", "다음에는", "앞으로",
        "스타일", "방식", "형식", "포맷", "톤",
        "style", "format", "tone", "approach",
        "피드백", "개선", "교정", "수정",
    ]

    private static let dropKeywords: Set<String> = [
        "안녕", "고마워", "감사", "ㅋㅋ", "ㅎㅎ",
        "hello", "thanks", "thank you", "bye", "ok",
        "네", "아니요", "응", "좋아", "알겠",
    ]

    // MARK: - Classify

    /// 단일 후보를 분류한다.
    func classify(_ candidate: MemoryCandidate) -> MemoryClassification {
        let content = candidate.content.lowercased()
        let words = Set(content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })

        // 1. 드롭 체크: 짧은 단순 인사/응답
        if content.count < 10 && matchCount(words: words, keywords: Self.dropKeywords) > 0 {
            return MemoryClassification(
                candidateId: candidate.id,
                targetLayer: .drop,
                confidence: 0.9,
                reason: "짧은 인사/응답으로 드롭"
            )
        }

        // 2. 도구 결과에서 온 후보
        if candidate.source == .toolResult {
            let wsScore = matchCount(words: words, keywords: Self.workspaceKeywords)
                + matchCount(content: content, keywords: Self.workspaceKeywords)
            let agentScore = matchCount(words: words, keywords: Self.agentKeywords)
                + matchCount(content: content, keywords: Self.agentKeywords)
            let personalScore = matchCount(words: words, keywords: Self.personalKeywords)
                + matchCount(content: content, keywords: Self.personalKeywords)

            if personalScore > wsScore && personalScore > agentScore {
                return MemoryClassification(
                    candidateId: candidate.id,
                    targetLayer: .personal,
                    confidence: normalizedConfidence(personalScore),
                    reason: "도구 결과, 개인 키워드 매칭 (\(personalScore)건)"
                )
            } else if wsScore >= agentScore {
                return MemoryClassification(
                    candidateId: candidate.id,
                    targetLayer: .workspace,
                    confidence: normalizedConfidence(wsScore),
                    reason: "도구 결과, 워크스페이스 키워드 매칭 (\(wsScore)건)"
                )
            } else {
                return MemoryClassification(
                    candidateId: candidate.id,
                    targetLayer: .agent,
                    confidence: normalizedConfidence(agentScore),
                    reason: "도구 결과, 에이전트 키워드 매칭 (\(agentScore)건)"
                )
            }
        }

        // 3. 대화에서 온 후보: 키워드 기반 점수 산정
        let personalScore = matchCount(words: words, keywords: Self.personalKeywords)
            + matchCount(content: content, keywords: Self.personalKeywords)
        let workspaceScore = matchCount(words: words, keywords: Self.workspaceKeywords)
            + matchCount(content: content, keywords: Self.workspaceKeywords)
        let agentScore = matchCount(words: words, keywords: Self.agentKeywords)
            + matchCount(content: content, keywords: Self.agentKeywords)
        let dropScore = matchCount(words: words, keywords: Self.dropKeywords)

        let maxScore = max(personalScore, workspaceScore, agentScore)

        // 키워드 매칭 없으면 personal 기본
        if maxScore == 0 {
            return MemoryClassification(
                candidateId: candidate.id,
                targetLayer: .personal,
                confidence: 0.3,
                reason: "키워드 매칭 없음, 기본 personal"
            )
        }

        // 드롭 점수가 가장 높으면 드롭
        if dropScore > maxScore {
            return MemoryClassification(
                candidateId: candidate.id,
                targetLayer: .drop,
                confidence: normalizedConfidence(dropScore),
                reason: "드롭 키워드 우세 (\(dropScore)건)"
            )
        }

        if personalScore >= workspaceScore && personalScore >= agentScore {
            return MemoryClassification(
                candidateId: candidate.id,
                targetLayer: .personal,
                confidence: normalizedConfidence(personalScore),
                reason: "개인 키워드 매칭 (\(personalScore)건)"
            )
        } else if workspaceScore >= agentScore {
            return MemoryClassification(
                candidateId: candidate.id,
                targetLayer: .workspace,
                confidence: normalizedConfidence(workspaceScore),
                reason: "워크스페이스 키워드 매칭 (\(workspaceScore)건)"
            )
        } else {
            return MemoryClassification(
                candidateId: candidate.id,
                targetLayer: .agent,
                confidence: normalizedConfidence(agentScore),
                reason: "에이전트 키워드 매칭 (\(agentScore)건)"
            )
        }
    }

    /// 여러 후보를 일괄 분류한다.
    func classifyAll(_ candidates: [MemoryCandidate]) -> [MemoryClassification] {
        candidates.map { classify($0) }
    }

    // MARK: - Helpers

    private func matchCount(words: Set<String>, keywords: Set<String>) -> Int {
        words.intersection(keywords).count
    }

    private func matchCount(content: String, keywords: Set<String>) -> Int {
        keywords.filter { content.contains($0) }.count
    }

    private func normalizedConfidence(_ score: Int) -> Double {
        min(0.5 + Double(score) * 0.1, 1.0)
    }
}
