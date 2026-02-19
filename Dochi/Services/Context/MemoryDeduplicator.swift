import Foundation
import os

// MARK: - MemoryDeduplicator

/// 분류된 메모리 후보와 기존 메모리를 비교하여 중복/충돌을 검사한다.
@MainActor
final class MemoryDeduplicator {

    static let duplicateThreshold: Double = 0.7
    static let conflictLowerBound: Double = 0.3
    static let conflictUpperBound: Double = 0.7
    static let conflictMinSharedKeywords = 2

    // MARK: - Check

    /// 분류된 후보 목록에 대해 기존 메모리와 중복/충돌 검사를 수행한다.
    func check(
        candidates: [MemoryCandidate],
        classifications: [MemoryClassification],
        existingMemory: [MemoryTargetLayer: String]
    ) -> [DeduplicationResult] {
        zip(candidates, classifications).map { candidate, classification in
            checkSingle(
                candidate: candidate,
                classification: classification,
                existingMemory: existingMemory
            )
        }
    }

    /// 단일 후보에 대해 중복/충돌 검사
    func checkSingle(
        candidate: MemoryCandidate,
        classification: MemoryClassification,
        existingMemory: [MemoryTargetLayer: String]
    ) -> DeduplicationResult {
        guard classification.targetLayer != .drop else {
            return DeduplicationResult(
                classification: classification,
                originalContent: candidate.content
            )
        }

        let memory = existingMemory[classification.targetLayer] ?? ""
        let lines = memory.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let content = candidate.content

        for line in lines {
            let normalizedLine = line
                .replacingOccurrences(of: "- ", with: "")
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
            let normalizedContent = content.lowercased().trimmingCharacters(in: .whitespaces)

            // 완전 일치
            if normalizedContent == normalizedLine {
                return DeduplicationResult(
                    classification: classification,
                    originalContent: candidate.content,
                    isDuplicate: true,
                    similarity: 1.0
                )
            }

            // Jaccard 유사도
            let similarity = jaccardSimilarity(normalizedContent, normalizedLine)
            if similarity > Self.duplicateThreshold {
                return DeduplicationResult(
                    classification: classification,
                    originalContent: candidate.content,
                    isDuplicate: true,
                    similarity: similarity
                )
            }

            // 충돌 검사
            if similarity > Self.conflictLowerBound && similarity <= Self.conflictUpperBound {
                let contentWords = Set(normalizedContent.components(separatedBy: .whitespaces))
                let lineWords = Set(normalizedLine.components(separatedBy: .whitespaces))
                let shared = contentWords.intersection(lineWords)

                if shared.count >= Self.conflictMinSharedKeywords
                    && contentWords.symmetricDifference(lineWords).count >= 2 {
                    return DeduplicationResult(
                        classification: classification,
                        originalContent: candidate.content,
                        isConflict: true,
                        conflictingContent: line,
                        similarity: similarity
                    )
                }
            }
        }

        return DeduplicationResult(
            classification: classification,
            originalContent: candidate.content
        )
    }

    // MARK: - Jaccard Similarity

    func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        let wordsB = Set(b.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 0.0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union)
    }
}
