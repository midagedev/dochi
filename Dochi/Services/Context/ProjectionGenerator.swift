import Foundation
import os

// MARK: - ProjectionGenerator

/// summary + hot facts 프로젝션을 생성한다.
/// 최근 N개 항목 + 키워드 빈도 기반 핫 팩트 선정.
/// fail-safe: 생성 실패 시 기존 프로젝션을 유지한다.
@MainActor
final class ProjectionGenerator {

    static let maxHotFacts = 10
    static let recentFactCount = 20
    static let minMemoryLength = 50

    private let contextService: ContextServiceProtocol

    init(contextService: ContextServiceProtocol) {
        self.contextService = contextService
    }

    // MARK: - Generate Projection

    /// 특정 layer의 메모리에 대해 프로젝션을 생성한다.
    func generate(
        layer: MemoryTargetLayer,
        workspaceId: UUID,
        agentName: String,
        userId: String?,
        existingProjection: MemoryProjection?
    ) -> MemoryProjection {
        do {
            let rawMemory = try loadMemory(layer: layer, workspaceId: workspaceId, agentName: agentName, userId: userId)

            guard rawMemory.count >= Self.minMemoryLength else {
                let facts = parseFactLines(rawMemory)
                return MemoryProjection(
                    layer: layer,
                    summary: "",
                    hotFacts: facts,
                    generatedAt: Date(),
                    sourceCharCount: rawMemory.count
                )
            }

            let facts = parseFactLines(rawMemory)
            let hotFacts = selectHotFacts(from: facts)
            let summary = generateSummary(facts: facts, totalCount: facts.count)

            return MemoryProjection(
                layer: layer,
                summary: summary,
                hotFacts: hotFacts,
                generatedAt: Date(),
                sourceCharCount: rawMemory.count
            )
        } catch {
            // Fail-safe: 생성 실패 시 기존 프로젝션 유지
            Log.storage.warning("프로젝션 생성 실패 (\(layer.rawValue)), 기존 유지: \(error.localizedDescription)")
            if let existing = existingProjection {
                return existing
            }
            return MemoryProjection(
                layer: layer,
                summary: "",
                hotFacts: [],
                generatedAt: Date(),
                sourceCharCount: 0
            )
        }
    }

    /// 모든 layer에 대해 프로젝션을 일괄 생성한다.
    func generateAll(
        workspaceId: UUID,
        agentName: String,
        userId: String?,
        existingProjections: [MemoryTargetLayer: MemoryProjection]
    ) -> [MemoryTargetLayer: MemoryProjection] {
        var result: [MemoryTargetLayer: MemoryProjection] = [:]

        result[.workspace] = generate(
            layer: .workspace,
            workspaceId: workspaceId,
            agentName: agentName,
            userId: nil,
            existingProjection: existingProjections[.workspace]
        )

        result[.agent] = generate(
            layer: .agent,
            workspaceId: workspaceId,
            agentName: agentName,
            userId: nil,
            existingProjection: existingProjections[.agent]
        )

        if let userId, !userId.isEmpty {
            result[.personal] = generate(
                layer: .personal,
                workspaceId: workspaceId,
                agentName: agentName,
                userId: userId,
                existingProjection: existingProjections[.personal]
            )
        }

        return result
    }

    // MARK: - Private

    private func loadMemory(
        layer: MemoryTargetLayer,
        workspaceId: UUID,
        agentName: String,
        userId: String?
    ) throws -> String {
        switch layer {
        case .personal:
            guard let userId, !userId.isEmpty else {
                throw ProjectionError.noUserId
            }
            return contextService.loadUserMemory(userId: userId) ?? ""
        case .workspace:
            return contextService.loadWorkspaceMemory(workspaceId: workspaceId) ?? ""
        case .agent:
            return contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName) ?? ""
        case .drop:
            return ""
        }
    }

    /// 메모리에서 팩트 라인 파싱
    func parseFactLines(_ memory: String) -> [String] {
        memory.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                if line.hasPrefix("- ") {
                    return String(line.dropFirst(2))
                }
                return line
            }
    }

    /// 핫 팩트 선정: 최근 항목 우선 + 키워드 빈도 기반
    func selectHotFacts(from facts: [String]) -> [String] {
        guard facts.count > Self.maxHotFacts else { return facts }

        let recentFacts = Array(facts.suffix(Self.recentFactCount))

        // 키워드 빈도 계산
        var wordFreq: [String: Int] = [:]
        for fact in facts {
            let words = fact.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 1 }
            for word in words {
                wordFreq[word, default: 0] += 1
            }
        }

        // 각 팩트의 중요도 점수
        let scored = recentFacts.map { fact -> (String, Double) in
            let words = fact.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 1 }
            let score = words.reduce(0.0) { sum, word in
                sum + Double(wordFreq[word] ?? 0)
            }
            return (fact, score)
        }

        let sorted = scored.sorted { $0.1 > $1.1 }
        return Array(sorted.prefix(Self.maxHotFacts).map(\.0))
    }

    /// 간단한 요약 생성
    func generateSummary(facts: [String], totalCount: Int) -> String {
        guard totalCount > Self.maxHotFacts else { return "" }

        var categories: [String: Int] = [:]
        for fact in facts {
            let category = categorize(fact)
            categories[category, default: 0] += 1
        }

        let topCategories = categories.sorted { $0.value > $1.value }
            .prefix(3)
            .map { "\($0.key) \($0.value)건" }
            .joined(separator: ", ")

        return "총 \(totalCount)건의 기억 (\(topCategories))"
    }

    private func categorize(_ fact: String) -> String {
        let lower = fact.lowercased()
        if lower.contains("선호") || lower.contains("좋아") || lower.contains("싫어") {
            return "선호도"
        }
        if lower.contains("프로젝트") || lower.contains("배포") || lower.contains("일정") {
            return "프로젝트"
        }
        if lower.contains("결정") || lower.contains("합의") || lower.contains("방침") {
            return "결정사항"
        }
        if lower.contains("패턴") || lower.contains("스타일") || lower.contains("방식") {
            return "패턴/스타일"
        }
        return "기타"
    }
}

// MARK: - ProjectionError

enum ProjectionError: LocalizedError {
    case noUserId
    case memoryLoadFailed

    var errorDescription: String? {
        switch self {
        case .noUserId: return "사용자 ID가 없습니다."
        case .memoryLoadFailed: return "메모리 로드에 실패했습니다."
        }
    }
}
