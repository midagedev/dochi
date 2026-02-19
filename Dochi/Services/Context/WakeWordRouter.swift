import Foundation
import os

// MARK: - WakeWordRouter

/// 입력 텍스트에서 wakeWord를 매칭하여 workspace + agent를 확정한다.
@MainActor
final class WakeWordRouter {

    private let contextService: ContextServiceProtocol
    private let loader: AgentDefinitionLoader

    init(contextService: ContextServiceProtocol) {
        self.contextService = contextService
        self.loader = AgentDefinitionLoader(contextService: contextService)
    }

    // MARK: - Route

    /// 입력 텍스트를 분석하여 라우팅 결정을 반환한다.
    func route(
        input: String,
        availableWorkspaces: [UUID],
        currentWorkspaceId: UUID,
        currentAgentName: String
    ) -> RoutingDecision {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return RoutingDecision(
                workspaceId: currentWorkspaceId,
                agentName: currentAgentName,
                matchedWakeWord: nil,
                confidence: 1.0,
                reason: .currentDefault
            )
        }

        // 모든 워크스페이스에서 에이전트 로드
        var allAgents: [(UUID, AgentDefinition)] = []
        for wsId in availableWorkspaces {
            let loaded = loader.loadAll(workspaceId: wsId)
            for agent in loaded {
                allAgents.append((wsId, agent.definition))
            }
        }

        // wakeWord 매칭
        let inputLower = trimmedInput.lowercased()
        var bestMatch: (UUID, AgentDefinition, String, MatchType)?
        var bestScore = 0

        for (wsId, definition) in allAgents {
            guard let wakeWord = definition.wakeWord, !wakeWord.isEmpty else { continue }
            let wakeWordLower = wakeWord.lowercased()

            // 접두사 매칭
            if inputLower.hasPrefix(wakeWordLower) {
                let score = wakeWordLower.count * 2  // 접두사 매칭은 가중치 2배
                if score > bestScore {
                    bestScore = score
                    bestMatch = (wsId, definition, wakeWord, .prefix)
                }
            }
            // 포함 매칭
            else if inputLower.contains(wakeWordLower) {
                let score = wakeWordLower.count
                if score > bestScore {
                    bestScore = score
                    bestMatch = (wsId, definition, wakeWord, .contains)
                }
            }
        }

        if let (wsId, definition, wakeWord, matchType) = bestMatch {
            let confidence: Double = matchType == .prefix ? 0.95 : 0.7
            Log.app.info("wakeWord 라우팅: '\(wakeWord)' → \(definition.name) (\(matchType))")

            return RoutingDecision(
                workspaceId: wsId,
                agentName: definition.name,
                matchedWakeWord: wakeWord,
                confidence: confidence,
                reason: matchType == .prefix ? .wakeWordPrefix : .wakeWordContains
            )
        }

        // 매칭 없음: 현재 에이전트 유지
        Log.app.debug("wakeWord 라우팅: 매칭 없음 — input='\(trimmedInput)', agents=\(allAgents.count)개 검색")
        return RoutingDecision(
            workspaceId: currentWorkspaceId,
            agentName: currentAgentName,
            matchedWakeWord: nil,
            confidence: 1.0,
            reason: .currentDefault
        )
    }

    // MARK: - Quick Match (no workspace scan)

    /// 사전에 로드된 에이전트 목록에서 wakeWord 매칭만 수행.
    func quickMatch(
        input: String,
        agents: [(workspaceId: UUID, definition: AgentDefinition)]
    ) -> RoutingDecision? {
        let inputLower = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !inputLower.isEmpty else { return nil }

        var bestMatch: (UUID, AgentDefinition, String, MatchType)?
        var bestScore = 0

        for (wsId, definition) in agents {
            guard let wakeWord = definition.wakeWord, !wakeWord.isEmpty else { continue }
            let wakeWordLower = wakeWord.lowercased()

            if inputLower.hasPrefix(wakeWordLower) {
                let score = wakeWordLower.count * 2
                if score > bestScore {
                    bestScore = score
                    bestMatch = (wsId, definition, wakeWord, .prefix)
                }
            } else if inputLower.contains(wakeWordLower) {
                let score = wakeWordLower.count
                if score > bestScore {
                    bestScore = score
                    bestMatch = (wsId, definition, wakeWord, .contains)
                }
            }
        }

        guard let (wsId, definition, wakeWord, matchType) = bestMatch else { return nil }

        return RoutingDecision(
            workspaceId: wsId,
            agentName: definition.name,
            matchedWakeWord: wakeWord,
            confidence: matchType == .prefix ? 0.95 : 0.7,
            reason: matchType == .prefix ? .wakeWordPrefix : .wakeWordContains
        )
    }

    private enum MatchType: CustomStringConvertible {
        case prefix, contains

        var description: String {
            switch self {
            case .prefix: return "prefix"
            case .contains: return "contains"
            }
        }
    }
}

// MARK: - RoutingDecision

/// wakeWord 라우팅 결과
struct RoutingDecision: Sendable, Equatable {
    let workspaceId: UUID
    let agentName: String
    let matchedWakeWord: String?
    let confidence: Double
    let reason: RoutingReason
    let timestamp: Date

    init(
        workspaceId: UUID,
        agentName: String,
        matchedWakeWord: String? = nil,
        confidence: Double = 1.0,
        reason: RoutingReason = .currentDefault,
        timestamp: Date = Date()
    ) {
        self.workspaceId = workspaceId
        self.agentName = agentName
        self.matchedWakeWord = matchedWakeWord
        self.confidence = confidence
        self.reason = reason
        self.timestamp = timestamp
    }

    var isWakeWordMatch: Bool {
        matchedWakeWord != nil
    }
}

// MARK: - RoutingReason

enum RoutingReason: String, Codable, Sendable {
    case wakeWordPrefix
    case wakeWordContains
    case currentDefault
    case explicit
}
