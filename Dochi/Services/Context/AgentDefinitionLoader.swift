import Foundation
import os

// MARK: - AgentDefinitionLoader

/// 파일시스템에서 에이전트 정의를 로드한다.
/// system.md + config.json + memory.md를 통합하여 LoadedAgentDefinition을 반환.
@MainActor
final class AgentDefinitionLoader {

    private let contextService: ContextServiceProtocol

    init(contextService: ContextServiceProtocol) {
        self.contextService = contextService
    }

    // MARK: - Load Single Agent

    /// 특정 에이전트의 전체 정의를 로드한다.
    func load(workspaceId: UUID, agentName: String) -> LoadedAgentDefinition? {
        guard let definition = loadDefinition(workspaceId: workspaceId, agentName: agentName) else {
            Log.app.debug("에이전트 정의 로드 실패: \(agentName)")
            return nil
        }

        let systemPrompt = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: agentName)
        let memory = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName)

        return LoadedAgentDefinition(
            definition: definition,
            systemPrompt: systemPrompt,
            memory: memory,
            workspaceId: workspaceId
        )
    }

    // MARK: - Load All Agents in Workspace

    /// 워크스페이스 내 모든 에이전트 정의를 로드한다.
    func loadAll(workspaceId: UUID) -> [LoadedAgentDefinition] {
        let agentNames = contextService.listAgents(workspaceId: workspaceId)
        return agentNames.compactMap { load(workspaceId: workspaceId, agentName: $0) }
    }

    // MARK: - Load Definition Only

    /// config.json에서 AgentDefinition을 로드한다.
    /// v2 포맷 우선 시도, 실패 시 기존 AgentConfig에서 변환.
    func loadDefinition(workspaceId: UUID, agentName: String) -> AgentDefinition? {
        // v2: raw JSON에서 직접 AgentDefinition 디코딩
        if let data = contextService.loadAgentConfigData(workspaceId: workspaceId, agentName: agentName) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let definition = try? decoder.decode(AgentDefinition.self, from: data) {
                return definition
            }
        }

        // 레거시: AgentConfig에서 변환
        if let config = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: agentName) {
            return AgentDefinition.from(config: config)
        }

        return nil
    }

    // MARK: - Save Definition

    /// AgentDefinition을 config.json에 저장한다.
    func save(workspaceId: UUID, definition: AgentDefinition) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(definition)

        contextService.saveAgentConfigData(workspaceId: workspaceId, agentName: definition.name, data: data)

        // 레거시 AgentConfig도 동기화 (기존 코드 호환)
        let config = definition.toAgentConfig()
        contextService.saveAgentConfig(workspaceId: workspaceId, config: config)
    }
}
