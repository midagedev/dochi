import Foundation
import os

// MARK: - MemoryPipelineService

/// 메모리 파이프라인: 추출 → 분류 → 중복검사 → 저장 → 프로젝션 생성
/// MemoryPipelineProtocol 구현체.
@MainActor
@Observable
final class MemoryPipelineService: MemoryPipelineProtocol {

    // MARK: - Components

    let extractor: MemoryCandidateExtractor
    let classifier: LayerClassifier
    let deduplicator: MemoryDeduplicator
    let projectionGenerator: ProjectionGenerator
    let retryQueue: MemoryRetryQueue
    private let contextService: ContextServiceProtocol

    // MARK: - State

    private(set) var currentProjections: [MemoryTargetLayer: MemoryProjection] = [:]
    private(set) var auditLog: [MemoryAuditEvent] = []
    private static let maxAuditEntries = 200

    // MARK: - Init

    init(contextService: ContextServiceProtocol) {
        self.contextService = contextService
        self.extractor = MemoryCandidateExtractor()
        self.classifier = LayerClassifier()
        self.deduplicator = MemoryDeduplicator()
        self.projectionGenerator = ProjectionGenerator(contextService: contextService)
        self.retryQueue = MemoryRetryQueue(contextService: contextService)
    }

    // MARK: - MemoryPipelineProtocol

    func submitCandidate(_ candidate: MemoryCandidate) async {
        let classification = classifyCandidate(candidate)

        if classification.targetLayer == .drop {
            recordAudit(candidateId: candidate.id, targetLayer: .drop,
                       action: .dropped, workspaceId: candidate.workspaceId,
                       agentId: candidate.agentId, userId: candidate.userId,
                       reason: classification.reason)
            return
        }

        do {
            try await processAndStore(candidate)
        } catch {
            Log.storage.warning("후보 처리 실패, 재시도 큐 추가: \(error.localizedDescription)")
        }
    }

    func classifyCandidate(_ candidate: MemoryCandidate) -> MemoryClassification {
        classifier.classify(candidate)
    }

    func processAndStore(_ candidate: MemoryCandidate) async throws {
        let classification = classifyCandidate(candidate)

        guard classification.targetLayer != .drop else {
            recordAudit(candidateId: candidate.id, targetLayer: .drop,
                       action: .dropped, workspaceId: candidate.workspaceId,
                       agentId: candidate.agentId, userId: candidate.userId,
                       reason: classification.reason)
            return
        }

        // 중복 검사
        let existing = loadCurrentMemoryForLayer(
            targetLayer: classification.targetLayer,
            workspaceId: candidate.workspaceId,
            agentId: candidate.agentId,
            userId: candidate.userId
        )
        let dedupResult = deduplicator.checkSingle(
            candidate: candidate,
            classification: classification,
            existingMemory: [classification.targetLayer: existing]
        )

        if dedupResult.isDuplicate {
            recordAudit(candidateId: candidate.id, targetLayer: classification.targetLayer,
                       action: .deduplicated, workspaceId: candidate.workspaceId,
                       agentId: candidate.agentId, userId: candidate.userId,
                       reason: "유사도 \(String(format: "%.2f", dedupResult.similarity))")
            return
        }

        // 저장
        let success = storeContent(
            content: candidate.content,
            targetLayer: classification.targetLayer,
            workspaceId: candidate.workspaceId,
            agentName: candidate.agentId ?? "",
            userId: candidate.userId
        )

        if success {
            recordAudit(candidateId: candidate.id, targetLayer: classification.targetLayer,
                       action: .stored, workspaceId: candidate.workspaceId,
                       agentId: candidate.agentId, userId: candidate.userId,
                       reason: classification.reason)
        } else {
            retryQueue.enqueue(
                content: candidate.content,
                targetLayer: classification.targetLayer,
                workspaceId: candidate.workspaceId,
                agentName: candidate.agentId ?? "",
                userId: candidate.userId,
                error: "저장 실패"
            )
            recordAudit(candidateId: candidate.id, targetLayer: classification.targetLayer,
                       action: .retryQueued, workspaceId: candidate.workspaceId,
                       agentId: candidate.agentId, userId: candidate.userId,
                       reason: "저장 실패, 재시도 큐 추가")
        }
    }

    func pendingCount() -> Int {
        retryQueue.pendingCount
    }

    // MARK: - Batch Processing

    /// 대화 종료 시 메모리 파이프라인을 일괄 실행한다.
    func processConversationEnd(
        messages: [Message],
        sessionId: String,
        sessionContext: SessionContext,
        settings: AppSettings
    ) async -> MemoryPipelineResult {
        Log.storage.info("메모리 파이프라인 시작: 대화 종료")

        let candidates = extractor.extractFromConversation(
            messages: messages,
            sessionId: sessionId,
            workspaceId: sessionContext.workspaceId.uuidString,
            agentId: settings.activeAgentName,
            userId: sessionContext.currentUserId
        )

        guard !candidates.isEmpty else {
            Log.storage.debug("추출된 후보 없음, 파이프라인 종료")
            return .empty
        }

        return await processCandidatesBatch(
            candidates: candidates,
            sessionContext: sessionContext,
            settings: settings
        )
    }

    /// PostToolUse 훅에서 도구 결과를 일괄 처리한다.
    func processToolResult(
        toolName: String,
        result: String,
        sessionId: String,
        sessionContext: SessionContext,
        settings: AppSettings
    ) async -> MemoryPipelineResult {
        Log.storage.info("메모리 파이프라인 시작: 도구 결과 (\(toolName))")

        let candidates = extractor.extractFromToolResult(
            toolName: toolName,
            result: result,
            sessionId: sessionId,
            workspaceId: sessionContext.workspaceId.uuidString,
            agentId: settings.activeAgentName,
            userId: sessionContext.currentUserId
        )

        guard !candidates.isEmpty else { return .empty }

        return await processCandidatesBatch(
            candidates: candidates,
            sessionContext: sessionContext,
            settings: settings
        )
    }

    // MARK: - Projection

    func regenerateProjections(
        workspaceId: UUID,
        agentName: String,
        userId: String?
    ) -> [MemoryTargetLayer: MemoryProjection] {
        let projections = projectionGenerator.generateAll(
            workspaceId: workspaceId,
            agentName: agentName,
            userId: userId,
            existingProjections: currentProjections
        )
        currentProjections = projections
        return projections
    }

    // MARK: - Private Batch Pipeline

    private func processCandidatesBatch(
        candidates: [MemoryCandidate],
        sessionContext: SessionContext,
        settings: AppSettings
    ) async -> MemoryPipelineResult {
        // 분류
        let classifications = classifier.classifyAll(candidates)
        let dropped = classifications.filter { $0.targetLayer == .drop }
        let active = zip(candidates, classifications).filter { $0.1.targetLayer != .drop }

        // 현재 메모리 로드
        let existingMemory = loadCurrentMemoryAll(sessionContext: sessionContext, settings: settings)

        // 중복/충돌 검사
        let activeCandidates = active.map(\.0)
        let activeClassifications = active.map(\.1)
        let deduped = deduplicator.check(
            candidates: activeCandidates,
            classifications: activeClassifications,
            existingMemory: existingMemory
        )
        let duplicates = deduped.filter(\.isDuplicate)
        let conflicts = deduped.filter(\.isConflict)
        let toStore = deduped.filter { !$0.isDuplicate && !$0.isConflict }

        // 저장
        var stored = 0
        var retryQueued = 0

        for result in toStore {
            let success = storeContent(
                content: result.originalContent,
                targetLayer: result.classification.targetLayer,
                workspaceId: sessionContext.workspaceId.uuidString,
                agentName: settings.activeAgentName,
                userId: sessionContext.currentUserId
            )
            if success {
                stored += 1
                recordAudit(candidateId: result.classification.candidateId,
                           targetLayer: result.classification.targetLayer,
                           action: .stored, workspaceId: sessionContext.workspaceId.uuidString,
                           agentId: settings.activeAgentName,
                           userId: sessionContext.currentUserId,
                           reason: result.classification.reason)
            } else {
                retryQueue.enqueue(
                    content: result.originalContent,
                    targetLayer: result.classification.targetLayer,
                    workspaceId: sessionContext.workspaceId.uuidString,
                    agentName: settings.activeAgentName,
                    userId: sessionContext.currentUserId,
                    error: "저장 실패"
                )
                retryQueued += 1
            }
        }

        // 프로젝션 재생성
        if stored > 0 {
            _ = regenerateProjections(
                workspaceId: sessionContext.workspaceId,
                agentName: settings.activeAgentName,
                userId: sessionContext.currentUserId
            )
        }

        // 감사 로그 (드롭/중복)
        for result in dropped {
            recordAudit(candidateId: result.candidateId, targetLayer: .drop,
                       action: .dropped, workspaceId: sessionContext.workspaceId.uuidString,
                       agentId: settings.activeAgentName, userId: sessionContext.currentUserId,
                       reason: result.reason)
        }
        for result in duplicates {
            recordAudit(candidateId: result.classification.candidateId,
                       targetLayer: result.classification.targetLayer,
                       action: .deduplicated, workspaceId: sessionContext.workspaceId.uuidString,
                       agentId: settings.activeAgentName, userId: sessionContext.currentUserId,
                       reason: "유사도 \(String(format: "%.2f", result.similarity))")
        }

        Log.storage.info("메모리 파이프라인 완료: \(stored)건 저장, \(duplicates.count)건 중복")

        return MemoryPipelineResult(
            candidatesExtracted: candidates.count,
            candidatesClassified: classifications.count,
            candidatesDropped: dropped.count,
            duplicatesSkipped: duplicates.count,
            conflictsDetected: conflicts.count,
            candidatesStored: stored,
            retryQueued: retryQueued
        )
    }

    // MARK: - Memory Operations

    private func loadCurrentMemoryAll(
        sessionContext: SessionContext,
        settings: AppSettings
    ) -> [MemoryTargetLayer: String] {
        var result: [MemoryTargetLayer: String] = [:]
        result[.workspace] = contextService.loadWorkspaceMemory(workspaceId: sessionContext.workspaceId) ?? ""
        result[.agent] = contextService.loadAgentMemory(
            workspaceId: sessionContext.workspaceId,
            agentName: settings.activeAgentName
        ) ?? ""
        if let userId = sessionContext.currentUserId {
            result[.personal] = contextService.loadUserMemory(userId: userId) ?? ""
        }
        return result
    }

    private func loadCurrentMemoryForLayer(
        targetLayer: MemoryTargetLayer,
        workspaceId: String,
        agentId: String?,
        userId: String?
    ) -> String {
        guard let wsUUID = UUID(uuidString: workspaceId) else { return "" }
        switch targetLayer {
        case .personal:
            guard let userId, !userId.isEmpty else { return "" }
            return contextService.loadUserMemory(userId: userId) ?? ""
        case .workspace:
            return contextService.loadWorkspaceMemory(workspaceId: wsUUID) ?? ""
        case .agent:
            return contextService.loadAgentMemory(workspaceId: wsUUID, agentName: agentId ?? "") ?? ""
        case .drop:
            return ""
        }
    }

    private func storeContent(
        content: String,
        targetLayer: MemoryTargetLayer,
        workspaceId: String,
        agentName: String,
        userId: String?
    ) -> Bool {
        guard let wsUUID = UUID(uuidString: workspaceId) else { return false }
        let line = "- \(content)"

        switch targetLayer {
        case .personal:
            guard let userId, !userId.isEmpty else {
                Log.storage.warning("개인 메모리 저장 실패: userId 없음")
                return false
            }
            contextService.appendUserMemory(userId: userId, content: line)
        case .workspace:
            contextService.appendWorkspaceMemory(workspaceId: wsUUID, content: line)
        case .agent:
            contextService.appendAgentMemory(workspaceId: wsUUID, agentName: agentName, content: line)
        case .drop:
            break
        }
        return true
    }

    // MARK: - Audit

    private func recordAudit(
        candidateId: String,
        targetLayer: MemoryTargetLayer,
        action: MemoryAuditAction,
        workspaceId: String,
        agentId: String?,
        userId: String?,
        reason: String
    ) {
        let event = MemoryAuditEvent(
            candidateId: candidateId,
            targetLayer: targetLayer,
            action: action,
            workspaceId: workspaceId,
            agentId: agentId,
            userId: userId,
            reason: reason
        )
        auditLog.append(event)

        if auditLog.count > Self.maxAuditEntries {
            auditLog.removeFirst(auditLog.count - Self.maxAuditEntries)
        }
    }
}

// MARK: - MemoryPipelineError

enum MemoryPipelineError: LocalizedError {
    case invalidWorkspaceId(String)
    case missingUserId
    case missingAgentId
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidWorkspaceId(let id): return "유효하지 않은 workspaceId: \(id)"
        case .missingUserId: return "개인 메모리 저장에 userId가 필요합니다."
        case .missingAgentId: return "에이전트 메모리 저장에 agentId가 필요합니다."
        case .storageFailed(let msg): return "메모리 저장 실패: \(msg)"
        }
    }
}
