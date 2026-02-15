import Foundation
import os

// MARK: - MemoryConsolidatorProtocol

@MainActor
protocol MemoryConsolidatorProtocol {
    var consolidationState: ConsolidationState { get }
    var lastResult: ConsolidationResult? { get }
    var changelog: [ChangelogEntry] { get }

    func consolidate(
        conversation: Conversation,
        sessionContext: SessionContext,
        settings: AppSettings
    ) async

    func resolveConflicts(
        conflicts: [MemoryConflict],
        resolutions: [UUID: MemoryConflictResolution]
    )

    func revert(changeId: UUID)
    func loadChangelog()
}

// MARK: - MemoryConsolidator

@MainActor
@Observable
final class MemoryConsolidator: MemoryConsolidatorProtocol {

    // MARK: - State

    private(set) var consolidationState: ConsolidationState = .idle
    private(set) var lastResult: ConsolidationResult?
    private(set) var changelog: [ChangelogEntry] = []

    // MARK: - Dependencies

    private let contextService: ContextServiceProtocol
    private let llmService: LLMServiceProtocol
    private let keychainService: KeychainServiceProtocol

    // MARK: - Storage

    private let changelogURL: URL
    private let archiveBaseURL: URL
    private static let maxChangelogEntries = 100

    // MARK: - Init

    init(
        contextService: ContextServiceProtocol,
        llmService: LLMServiceProtocol,
        keychainService: KeychainServiceProtocol,
        baseURL: URL? = nil
    ) {
        self.contextService = contextService
        self.llmService = llmService
        self.keychainService = keychainService

        let base = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        self.changelogURL = base.appendingPathComponent("memory_changelog.json")
        self.archiveBaseURL = base.appendingPathComponent("memory_archive")

        loadChangelog()
    }

    // MARK: - Consolidate

    func consolidate(
        conversation: Conversation,
        sessionContext: SessionContext,
        settings: AppSettings
    ) async {
        guard settings.memoryConsolidationEnabled else { return }

        let assistantMessages = conversation.messages.filter { $0.role == .assistant }
        guard assistantMessages.count >= settings.memoryConsolidationMinMessages else {
            Log.storage.debug("대화 메시지 부족, 정리 생략 (assistant: \(assistantMessages.count), min: \(settings.memoryConsolidationMinMessages))")
            return
        }

        consolidationState = .analyzing

        do {
            // 1. LLM으로 사실 추출
            let facts = try await extractFacts(
                from: conversation,
                settings: settings
            )

            guard !facts.isEmpty else {
                consolidationState = .completed(added: 0, updated: 0)
                scheduleAutoDismiss()
                return
            }

            // 2. 현재 메모리 로드
            let currentMemory = loadCurrentMemory(
                sessionContext: sessionContext,
                settings: settings
            )

            // 3. 중복/모순 감지
            var changes: [MemoryChange] = []
            var conflicts: [MemoryConflict] = []
            var duplicatesSkipped = 0

            for fact in facts {
                let memoryContent = currentMemory[fact.scope] ?? ""
                let lines = memoryContent.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                // 중복 감지 (문자열 유사도)
                if isDuplicate(fact: fact.content, existingLines: lines) {
                    duplicatesSkipped += 1
                    continue
                }

                // 모순 감지 (간단한 키워드 기반)
                if let conflictingLine = findConflict(fact: fact.content, existingLines: lines) {
                    conflicts.append(MemoryConflict(
                        scope: fact.scope,
                        existingFact: conflictingLine,
                        newFact: fact.content,
                        explanation: "기존 사실과 새로운 사실이 모순될 수 있습니다."
                    ))
                    continue
                }

                // 신규 추가
                changes.append(MemoryChange(
                    scope: fact.scope,
                    type: .added,
                    content: fact.content
                ))
            }

            // 4. 메모리 업데이트 (모순이 없는 항목만)
            applyChanges(changes, sessionContext: sessionContext, settings: settings)

            // 5. 크기 한도 확인 및 아카이브
            checkSizeLimits(sessionContext: sessionContext, settings: settings, changes: &changes)

            // 6. 결과 생성 및 changelog 기록
            let result = ConsolidationResult(
                conversationId: conversation.id,
                changes: changes,
                conflicts: conflicts,
                factsExtracted: facts.count,
                duplicatesSkipped: duplicatesSkipped
            )
            self.lastResult = result
            appendChangelog(result)

            if !conflicts.isEmpty {
                consolidationState = .conflict(count: conflicts.count)
            } else {
                consolidationState = .completed(added: result.addedCount, updated: result.updatedCount)
            }

            Log.storage.info("메모리 정리 완료: \(facts.count)건 추출, \(result.addedCount)건 추가, \(duplicatesSkipped)건 중복, \(conflicts.count)건 모순")

            scheduleAutoDismiss()

        } catch {
            consolidationState = .failed(message: error.localizedDescription)
            Log.storage.error("메모리 정리 실패: \(error.localizedDescription)")
            scheduleAutoDismiss()
        }
    }

    // MARK: - Conflict Resolution

    func resolveConflicts(
        conflicts: [MemoryConflict],
        resolutions: [UUID: MemoryConflictResolution]
    ) {
        guard let result = lastResult else { return }

        let sessionContext = SessionContext(workspaceId: UUID(), currentUserId: nil)
        // We use the stored result's conflicts
        for conflict in conflicts {
            guard let resolution = resolutions[conflict.id] else { continue }
            switch resolution {
            case .keepExisting:
                // No action needed
                break
            case .useNew:
                // Remove existing, add new — reflected in memory through ContextService
                // The actual update is done by the caller via ContextService
                break
            case .keepBoth:
                // Both remain — no removal needed
                break
            }
        }

        // Update state
        if case .conflict = consolidationState {
            consolidationState = .completed(added: result.addedCount, updated: result.updatedCount)
            scheduleAutoDismiss()
        }
    }

    /// 배너 닫기 (외부에서 호출)
    func dismissBanner() {
        consolidationState = .idle
    }

    // MARK: - Revert

    func revert(changeId: UUID) {
        guard let entry = changelog.first(where: { $0.id == changeId }) else {
            Log.storage.warning("되돌리기 대상을 찾을 수 없음: \(changeId)")
            return
        }

        // In a real implementation, this would restore the previous memory content
        // For now, log the revert attempt
        Log.storage.info("메모리 변경 되돌리기: \(changeId), 변경 \(entry.changes.count)건")
    }

    // MARK: - Changelog

    func loadChangelog() {
        guard FileManager.default.fileExists(atPath: changelogURL.path) else {
            changelog = []
            return
        }

        do {
            let data = try Data(contentsOf: changelogURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            changelog = try decoder.decode([ChangelogEntry].self, from: data)
        } catch {
            Log.storage.error("Changelog 로드 실패: \(error.localizedDescription)")
            changelog = []
        }
    }

    // MARK: - Private

    private func extractFacts(
        from conversation: Conversation,
        settings: AppSettings
    ) async throws -> [ExtractedFact] {
        let provider = resolveProvider(settings: settings)
        let model = resolveModel(settings: settings)
        let apiKey = keychainService.load(account: provider.keychainAccount) ?? ""

        guard !apiKey.isEmpty || !provider.requiresAPIKey else {
            throw ConsolidationError.noAPIKey
        }

        let conversationText = conversation.messages
            .filter { $0.role == .user || $0.role == .assistant }
            .prefix(50)
            .map { "\($0.role == .user ? "사용자" : "AI"): \($0.content)" }
            .joined(separator: "\n")

        let systemPrompt = """
        당신은 대화에서 중요한 사실과 결정을 추출하는 분석가입니다.
        대화 내용을 분석하여 기억할 가치가 있는 주요 사실, 결정, 선호도를 추출하세요.

        규칙:
        - 각 항목은 한 줄로 간결하게 작성
        - "- " 접두사로 시작
        - 사용자의 개인 정보, 선호도, 결정 사항 위주로 추출
        - 일상적 인사나 대화 흐름은 제외
        - 최대 10개까지만 추출
        - JSON 형식으로 응답: [{"content": "사실 내용", "scope": "personal"}]
        - scope은 "personal" (개인), "workspace" (프로젝트), "agent" (에이전트 관련) 중 하나

        대화 내용에서 기억할 사실이 없으면 빈 배열 [] 을 반환하세요.
        """

        let messages = [
            Message(role: .user, content: "다음 대화에서 중요한 사실과 결정을 추출하세요:\n\n\(conversationText)")
        ]

        let response = try await llmService.send(
            messages: messages,
            systemPrompt: systemPrompt,
            model: model,
            provider: provider,
            apiKey: apiKey,
            tools: nil,
            onPartial: { _ in }
        )

        guard case .text(let text) = response else {
            return []
        }

        return parseFacts(from: text)
    }

    private func parseFacts(from text: String) -> [ExtractedFact] {
        // Try to extract JSON array from the response
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON array in the text
        guard let startIndex = cleaned.firstIndex(of: "["),
              let endIndex = cleaned.lastIndex(of: "]") else {
            return parseLineFacts(from: text)
        }

        let jsonStr = String(cleaned[startIndex...endIndex])
        guard let data = jsonStr.data(using: .utf8) else {
            return parseLineFacts(from: text)
        }

        do {
            let decoded = try JSONDecoder().decode([ExtractedFact].self, from: data)
            return decoded
        } catch {
            Log.storage.debug("JSON 파싱 실패, 라인 파싱 시도: \(error.localizedDescription)")
            return parseLineFacts(from: text)
        }
    }

    /// Fallback: parse line-by-line if JSON parsing fails
    private func parseLineFacts(from text: String) -> [ExtractedFact] {
        return text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .prefix(10)
            .map { line in
                let content = String(line.dropFirst(2))
                return ExtractedFact(content: content, scope: .personal)
            }
    }

    private func resolveProvider(settings: AppSettings) -> LLMProvider {
        if settings.memoryConsolidationModel == "light" {
            // Use light model if configured
            if !settings.lightModelProvider.isEmpty,
               let provider = LLMProvider(rawValue: settings.lightModelProvider) {
                return provider
            }
        }
        return settings.currentProvider
    }

    private func resolveModel(settings: AppSettings) -> String {
        if settings.memoryConsolidationModel == "light" {
            if !settings.lightModelName.isEmpty {
                return settings.lightModelName
            }
            // Default light model
            switch settings.currentProvider {
            case .openai: return "gpt-4o-mini"
            case .anthropic: return "claude-3-5-haiku-20241022"
            default: return settings.llmModel
            }
        }
        return settings.llmModel
    }

    private func loadCurrentMemory(
        sessionContext: SessionContext,
        settings: AppSettings
    ) -> [MemoryScope: String] {
        var result: [MemoryScope: String] = [:]

        if let userId = sessionContext.currentUserId {
            result[.personal] = contextService.loadUserMemory(userId: userId) ?? ""
        }

        result[.workspace] = contextService.loadWorkspaceMemory(workspaceId: sessionContext.workspaceId) ?? ""

        result[.agent] = contextService.loadAgentMemory(
            workspaceId: sessionContext.workspaceId,
            agentName: settings.activeAgentName
        ) ?? ""

        return result
    }

    /// 문자열 유사도 기반 중복 감지
    private func isDuplicate(fact: String, existingLines: [String]) -> Bool {
        let normalizedFact = fact.lowercased().trimmingCharacters(in: .whitespaces)
        for line in existingLines {
            let normalizedLine = line.replacingOccurrences(of: "- ", with: "")
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
            if normalizedFact == normalizedLine { return true }
            if jaccardSimilarity(normalizedFact, normalizedLine) > 0.7 { return true }
        }
        return false
    }

    /// Jaccard similarity between two strings (word-level)
    private func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        let wordsB = Set(b.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 0.0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union)
    }

    /// 간단한 모순 감지 (주어 동일, 내용 상이)
    private func findConflict(fact: String, existingLines: [String]) -> String? {
        let factLower = fact.lowercased()
        for line in existingLines {
            let lineLower = line.replacingOccurrences(of: "- ", with: "").lowercased().trimmingCharacters(in: .whitespaces)
            guard !lineLower.isEmpty else { continue }

            // 유사도가 중간 범위이면 모순 가능성
            let sim = jaccardSimilarity(factLower, lineLower)
            if sim > 0.3 && sim < 0.7 {
                // 같은 주제이지만 다른 내용일 가능성
                let factWords = Set(factLower.components(separatedBy: .whitespaces))
                let lineWords = Set(lineLower.components(separatedBy: .whitespaces))
                let shared = factWords.intersection(lineWords)

                // 주요 키워드는 공유하지만 다른 정보가 있으면 모순 가능성
                if shared.count >= 2 && factWords.symmetricDifference(lineWords).count >= 2 {
                    return line
                }
            }
        }
        return nil
    }

    private func applyChanges(
        _ changes: [MemoryChange],
        sessionContext: SessionContext,
        settings: AppSettings
    ) {
        for change in changes where change.type == .added {
            let line = "- \(change.content)"
            switch change.scope {
            case .personal:
                if let userId = sessionContext.currentUserId {
                    contextService.appendUserMemory(userId: userId, content: line)
                }
            case .workspace:
                contextService.appendWorkspaceMemory(
                    workspaceId: sessionContext.workspaceId,
                    content: line
                )
            case .agent:
                contextService.appendAgentMemory(
                    workspaceId: sessionContext.workspaceId,
                    agentName: settings.activeAgentName,
                    content: line
                )
            }
        }
    }

    private func checkSizeLimits(
        sessionContext: SessionContext,
        settings: AppSettings,
        changes: inout [MemoryChange]
    ) {
        guard settings.memoryAutoArchiveEnabled else { return }

        // Check personal memory
        if let userId = sessionContext.currentUserId,
           let memory = contextService.loadUserMemory(userId: userId),
           memory.count > settings.memoryPersonalSizeLimit {
            archiveMemory(scope: .personal, identifier: userId, content: memory)
            // Trim to limit
            let trimmed = String(memory.suffix(settings.memoryPersonalSizeLimit))
            contextService.saveUserMemory(userId: userId, content: trimmed)
            changes.append(MemoryChange(scope: .personal, type: .archived, content: "크기 한도 초과로 일부 아카이브됨"))
        }

        // Check workspace memory
        if let memory = contextService.loadWorkspaceMemory(workspaceId: sessionContext.workspaceId),
           memory.count > settings.memoryWorkspaceSizeLimit {
            archiveMemory(scope: .workspace, identifier: sessionContext.workspaceId.uuidString, content: memory)
            let trimmed = String(memory.suffix(settings.memoryWorkspaceSizeLimit))
            contextService.saveWorkspaceMemory(workspaceId: sessionContext.workspaceId, content: trimmed)
            changes.append(MemoryChange(scope: .workspace, type: .archived, content: "크기 한도 초과로 일부 아카이브됨"))
        }

        // Check agent memory
        if let memory = contextService.loadAgentMemory(
            workspaceId: sessionContext.workspaceId,
            agentName: settings.activeAgentName
        ), memory.count > settings.memoryAgentSizeLimit {
            archiveMemory(scope: .agent, identifier: settings.activeAgentName, content: memory)
            let trimmed = String(memory.suffix(settings.memoryAgentSizeLimit))
            contextService.saveAgentMemory(
                workspaceId: sessionContext.workspaceId,
                agentName: settings.activeAgentName,
                content: trimmed
            )
            changes.append(MemoryChange(scope: .agent, type: .archived, content: "크기 한도 초과로 일부 아카이브됨"))
        }
    }

    private func archiveMemory(scope: MemoryScope, identifier: String, content: String) {
        do {
            try FileManager.default.createDirectory(at: archiveBaseURL, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
            let filename = "\(scope.rawValue)_\(identifier)_\(timestamp).md"
            let fileURL = archiveBaseURL.appendingPathComponent(filename)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            Log.storage.info("메모리 아카이브 저장: \(filename)")
        } catch {
            Log.storage.error("메모리 아카이브 실패: \(error.localizedDescription)")
        }
    }

    private func appendChangelog(_ result: ConsolidationResult) {
        let entry = ChangelogEntry(from: result)
        changelog.insert(entry, at: 0)

        // FIFO: keep max entries
        if changelog.count > Self.maxChangelogEntries {
            changelog = Array(changelog.prefix(Self.maxChangelogEntries))
        }

        saveChangelog()
    }

    private func saveChangelog() {
        do {
            let dir = changelogURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(changelog)
            try data.write(to: changelogURL, options: .atomic)
        } catch {
            Log.storage.error("Changelog 저장 실패: \(error.localizedDescription)")
        }
    }

    private func scheduleAutoDismiss() {
        guard case .analyzing = consolidationState else {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                if case .analyzing = self.consolidationState { return }
                self.consolidationState = .idle
            }
            return
        }
    }
}

// MARK: - ConsolidationError

enum ConsolidationError: LocalizedError {
    case noAPIKey
    case extractionFailed
    case memoryLoadFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API 키가 설정되지 않았습니다."
        case .extractionFailed: return "사실 추출에 실패했습니다."
        case .memoryLoadFailed: return "메모리 로드에 실패했습니다."
        }
    }
}
