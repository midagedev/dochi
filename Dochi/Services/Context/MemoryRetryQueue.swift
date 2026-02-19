import Foundation
import os

// MARK: - MemoryRetryQueue

/// 메모리 저장 실패 시 비동기 재시도 큐.
/// 지수 백오프로 재시도하며, 최대 횟수 초과 시 폐기한다.
@MainActor
@Observable
final class MemoryRetryQueue {

    private(set) var entries: [RetryEntry] = []
    private(set) var isProcessing = false
    private var processingTask: Task<Void, Never>?

    private let contextService: ContextServiceProtocol

    static let maxQueueSize = 50
    static let checkIntervalSeconds: TimeInterval = 10

    init(contextService: ContextServiceProtocol) {
        self.contextService = contextService
    }

    nonisolated deinit {
        // Note: processingTask is automatically cancelled when MemoryRetryQueue is deallocated
    }

    // MARK: - Enqueue

    func enqueue(
        content: String,
        targetLayer: MemoryTargetLayer,
        workspaceId: String,
        agentName: String,
        userId: String?,
        error: String
    ) {
        guard entries.count < Self.maxQueueSize else {
            Log.storage.warning("재시도 큐 가득 참, 항목 폐기: \(content.prefix(50))")
            return
        }

        let entry = RetryEntry(
            content: content,
            targetLayer: targetLayer,
            workspaceId: workspaceId,
            agentName: agentName,
            userId: userId,
            errorMessage: error
        )
        entries.append(entry)
        let queueCount = entries.count
        Log.storage.info("재시도 큐 추가 (\(targetLayer.rawValue)): \(content.prefix(50))... (큐: \(queueCount))")

        ensureProcessing()
    }

    // MARK: - Processing

    func ensureProcessing() {
        guard processingTask == nil else { return }
        processingTask = Task { @MainActor in
            await self.processLoop()
            self.processingTask = nil
        }
    }

    private func processLoop() async {
        isProcessing = true
        defer { isProcessing = false }

        while !entries.isEmpty && !Task.isCancelled {
            let now = Date()
            var processed: [UUID] = []

            for entry in entries {
                guard !Task.isCancelled else { return }

                guard now >= entry.nextRetryAt else { continue }

                if entry.isExhausted {
                    Log.storage.warning("재시도 횟수 초과, 폐기: \(entry.content.prefix(50))")
                    processed.append(entry.id)
                    continue
                }

                let success = attemptSave(entry: entry)
                if success {
                    Log.storage.info("재시도 성공: \(entry.content.prefix(50))")
                    processed.append(entry.id)
                } else {
                    if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                        entries[idx] = RetryEntry(
                            id: entry.id,
                            content: entry.content,
                            targetLayer: entry.targetLayer,
                            workspaceId: entry.workspaceId,
                            agentName: entry.agentName,
                            userId: entry.userId,
                            attemptCount: entry.attemptCount + 1,
                            lastAttemptAt: Date(),
                            createdAt: entry.createdAt,
                            errorMessage: entry.errorMessage
                        )
                    }
                }
            }

            entries.removeAll { processed.contains($0.id) }
            guard !entries.isEmpty else { break }
            try? await Task.sleep(for: .seconds(Self.checkIntervalSeconds))
        }
    }

    private func attemptSave(entry: RetryEntry) -> Bool {
        guard let wsUUID = UUID(uuidString: entry.workspaceId) else { return false }

        let content = "- \(entry.content)"

        switch entry.targetLayer {
        case .personal:
            guard let userId = entry.userId, !userId.isEmpty else { return true }
            contextService.appendUserMemory(userId: userId, content: content)
        case .workspace:
            contextService.appendWorkspaceMemory(workspaceId: wsUUID, content: content)
        case .agent:
            contextService.appendAgentMemory(workspaceId: wsUUID, agentName: entry.agentName, content: content)
        case .drop:
            break
        }

        return true
    }

    // MARK: - Query

    var pendingCount: Int { entries.count }

    func clear() {
        entries.removeAll()
        processingTask?.cancel()
        processingTask = nil
    }
}
