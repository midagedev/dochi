import Foundation
import os

// MARK: - Delegate Task to Agent

@MainActor
final class AgentDelegateTaskTool: BuiltInToolProtocol {
    let name = "agent.delegate_task"
    let category: ToolCategory = .sensitive
    let description = "다른 에이전트에게 작업을 위임합니다. 해당 에이전트의 페르소나와 메모리를 사용하여 별도의 LLM 호출을 수행합니다."
    let isBaseline = false

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext
    private let settings: AppSettings
    private let keychainService: KeychainServiceProtocol?
    private let delegationManager: DelegationManager?

    init(
        contextService: ContextServiceProtocol,
        sessionContext: SessionContext,
        settings: AppSettings,
        keychainService: KeychainServiceProtocol? = nil,
        delegationManager: DelegationManager? = nil
    ) {
        self.contextService = contextService
        self.sessionContext = sessionContext
        self.settings = settings
        self.keychainService = keychainService
        self.delegationManager = delegationManager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "agent_name": ["type": "string", "description": "위임할 에이전트 이름"],
                "task": ["type": "string", "description": "에이전트에게 전달할 작업 설명"],
                "context": ["type": "string", "description": "추가 컨텍스트 (선택)"],
                "priority": ["type": "string", "description": "우선순위: low, normal, high (선택, 기본값: normal)"],
                "timeout_seconds": ["type": "integer", "description": "타임아웃(초) (선택, 기본값: 설정값)"],
            ] as [String: Any],
            "required": ["agent_name", "task"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let agentName = arguments["agent_name"] as? String, !agentName.isEmpty else {
            return ToolResult(toolCallId: "", content: "agent_name 파라미터가 필요합니다.", isError: true)
        }
        guard let task = arguments["task"] as? String, !task.isEmpty else {
            return ToolResult(toolCallId: "", content: "task 파라미터가 필요합니다.", isError: true)
        }

        // Check delegation enabled
        guard settings.delegationEnabled else {
            return ToolResult(toolCallId: "", content: "위임 기능이 비활성화되어 있습니다. 설정에서 활성화해주세요.", isError: true)
        }

        let workspaceId = sessionContext.workspaceId
        let agents = contextService.listAgents(workspaceId: workspaceId)

        // Validate agent exists
        guard agents.contains(where: { $0.localizedCaseInsensitiveCompare(agentName) == .orderedSame }) else {
            let available = agents.joined(separator: ", ")
            return ToolResult(toolCallId: "", content: "에이전트 '\(agentName)'을(를) 찾을 수 없습니다. 사용 가능: \(available)", isError: true)
        }

        let originAgent = settings.activeAgentName

        // Self-delegation guard
        guard originAgent.localizedCaseInsensitiveCompare(agentName) != .orderedSame else {
            return ToolResult(toolCallId: "", content: "자기 자신에게 위임할 수 없습니다. 다른 에이전트를 지정하세요.", isError: true)
        }

        // Load origin agent config and check delegation policy
        let originConfig = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: originAgent)
        let originPolicy = originConfig?.effectiveDelegationPolicy ?? .default

        guard originPolicy.canDelegate else {
            return ToolResult(toolCallId: "", content: "현재 에이전트 '\(originAgent)'은(는) 위임이 허용되지 않습니다.", isError: true)
        }

        guard originPolicy.allowsDelegationTo(agentName) else {
            return ToolResult(toolCallId: "", content: "에이전트 '\(originAgent)'에서 '\(agentName)'으로의 위임이 정책에 의해 차단되었습니다.", isError: true)
        }

        // Load target agent config and check receive policy
        let targetConfig = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: agentName)
        let targetPolicy = targetConfig?.effectiveDelegationPolicy ?? .default

        guard targetPolicy.canReceiveDelegation else {
            return ToolResult(toolCallId: "", content: "에이전트 '\(agentName)'은(는) 위임 수신이 허용되지 않습니다.", isError: true)
        }

        // Check chain depth
        let maxDepth = min(settings.delegationMaxChainDepth, originPolicy.maxChainDepth)
        let currentDepth = delegationManager?.currentChain?.currentDepth ?? 0
        guard currentDepth < maxDepth else {
            return ToolResult(toolCallId: "", content: "위임 체인 최대 깊이(\(maxDepth))에 도달했습니다. 더 이상 위임할 수 없습니다.", isError: true)
        }

        // Check for cycles
        if let chain = delegationManager?.currentChain, chain.wouldCreateCycle(targetAgent: agentName) {
            return ToolResult(toolCallId: "", content: "위임 순환이 감지되었습니다. '\(agentName)'은(는) 이미 위임 체인에 포함되어 있습니다.", isError: true)
        }

        // Create delegation task
        let delegationTask = DelegationTask(
            parentDelegationId: delegationManager?.currentChain?.tasks.last?.id,
            originAgentName: originAgent,
            targetAgentName: agentName,
            task: task,
            context: arguments["context"] as? String,
            chainDepth: currentDepth + 1
        )

        // Register with delegation manager
        delegationManager?.startDelegation(delegationTask)

        // Load agent persona and memory
        let persona = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: agentName)
        let memory = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName)
        let additionalContext = arguments["context"] as? String ?? ""

        Log.tool.info("Delegating task to agent '\(agentName)': \(task.prefix(100))")

        // Build delegation system prompt
        var systemPrompt = "당신은 '\(agentName)' 에이전트입니다.\n"
        if let persona {
            systemPrompt += "\n## 페르소나\n\(persona)\n"
        }
        if let memory {
            systemPrompt += "\n## 메모리\n\(memory)\n"
        }
        systemPrompt += "\n## 위임 작업\n다음 작업을 수행하고 결과를 반환하세요. 간결하고 명확하게 답변하세요.\n"

        // Build user message
        var userContent = "작업: \(task)"
        if !additionalContext.isEmpty {
            userContent += "\n\n추가 컨텍스트: \(additionalContext)"
        }

        // Return prepared summary (LLM-based delegation removed; use SDK runtime for actual delegation)
        let summary = """
            위임 작업 준비 완료:
            - 대상 에이전트: \(agentName)
            - 작업: \(task)
            - 페르소나: \(persona?.prefix(200) ?? "(없음)")...
            - 메모리: \(memory?.prefix(200) ?? "(없음)")...
            \(additionalContext.isEmpty ? "" : "- 추가 컨텍스트: \(additionalContext)")

            에이전트 '\(agentName)'에게 작업이 전달되었습니다. 해당 에이전트의 페르소나와 메모리를 참고하여 응답을 생성하세요.
            """
        delegationManager?.completeDelegation(id: delegationTask.id, result: summary)
        return ToolResult(toolCallId: "", content: summary)
    }
}

// MARK: - Delegation Error

enum DelegationError: Error, LocalizedError {
    case timeout(seconds: Int)
    case notEnabled
    case agentNotFound(String)
    case policyDenied(String)
    case cyclicDelegation(String)
    case maxDepthExceeded(Int)

    var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "위임 타임아웃: \(seconds)초 초과"
        case .notEnabled:
            return "위임 기능이 비활성화됨"
        case .agentNotFound(let name):
            return "에이전트 '\(name)' 없음"
        case .policyDenied(let reason):
            return "위임 정책 거부: \(reason)"
        case .cyclicDelegation(let agent):
            return "순환 위임 감지: \(agent)"
        case .maxDepthExceeded(let depth):
            return "최대 위임 깊이 초과: \(depth)"
        }
    }
}

// MARK: - Delegation Manager

@MainActor
@Observable
final class DelegationManager {
    var activeDelegations: [DelegationTask] = []
    var recentDelegations: [DelegationTask] = []
    var currentChain: DelegationChain?

    private static let maxRecentDelegations = 20

    func startDelegation(_ task: DelegationTask) {
        var mutableTask = task
        mutableTask.status = .running
        mutableTask.startedAt = Date()
        activeDelegations.append(mutableTask)

        // Add to chain
        if currentChain == nil {
            currentChain = DelegationChain(tasks: [mutableTask])
        } else {
            currentChain?.tasks.append(mutableTask)
        }
    }

    func completeDelegation(id: UUID, result: String) {
        guard let index = activeDelegations.firstIndex(where: { $0.id == id }) else { return }
        activeDelegations[index].status = .completed
        activeDelegations[index].completedAt = Date()
        activeDelegations[index].result = result

        // Update chain
        if let chainIndex = currentChain?.tasks.firstIndex(where: { $0.id == id }) {
            currentChain?.tasks[chainIndex].status = .completed
            currentChain?.tasks[chainIndex].completedAt = Date()
            currentChain?.tasks[chainIndex].result = result
        }

        // Move to recent
        let completed = activeDelegations.remove(at: index)
        recentDelegations.insert(completed, at: 0)
        if recentDelegations.count > Self.maxRecentDelegations {
            recentDelegations = Array(recentDelegations.prefix(Self.maxRecentDelegations))
        }

        // Clear chain if all done
        if currentChain?.isComplete == true {
            currentChain = nil
        }
    }

    func failDelegation(id: UUID, error: String) {
        guard let index = activeDelegations.firstIndex(where: { $0.id == id }) else { return }
        activeDelegations[index].status = .failed
        activeDelegations[index].completedAt = Date()
        activeDelegations[index].errorMessage = error

        // Update chain
        if let chainIndex = currentChain?.tasks.firstIndex(where: { $0.id == id }) {
            currentChain?.tasks[chainIndex].status = .failed
            currentChain?.tasks[chainIndex].completedAt = Date()
            currentChain?.tasks[chainIndex].errorMessage = error
        }

        // Move to recent
        let failed = activeDelegations.remove(at: index)
        recentDelegations.insert(failed, at: 0)
        if recentDelegations.count > Self.maxRecentDelegations {
            recentDelegations = Array(recentDelegations.prefix(Self.maxRecentDelegations))
        }

        // Clear chain if all done
        if currentChain?.isComplete == true {
            currentChain = nil
        }
    }

    func cancelDelegation(id: UUID) {
        guard let index = activeDelegations.firstIndex(where: { $0.id == id }) else { return }
        activeDelegations[index].status = .cancelled
        activeDelegations[index].completedAt = Date()

        // Update chain
        if let chainIndex = currentChain?.tasks.firstIndex(where: { $0.id == id }) {
            currentChain?.tasks[chainIndex].status = .cancelled
            currentChain?.tasks[chainIndex].completedAt = Date()
        }

        let cancelled = activeDelegations.remove(at: index)
        recentDelegations.insert(cancelled, at: 0)
        if recentDelegations.count > Self.maxRecentDelegations {
            recentDelegations = Array(recentDelegations.prefix(Self.maxRecentDelegations))
        }

        // Clear chain if complete
        if currentChain?.isComplete == true {
            currentChain = nil
        }

        Log.app.info("Delegation cancelled: \(id)")
    }

    /// Summary of all delegations for the status tool.
    func statusSummary(delegationId: UUID? = nil) -> String {
        if let id = delegationId {
            // Find specific delegation
            if let task = activeDelegations.first(where: { $0.id == id }) {
                return formatTaskStatus(task)
            }
            if let task = recentDelegations.first(where: { $0.id == id }) {
                return formatTaskStatus(task)
            }
            return "위임 ID '\(id.uuidString)'을(를) 찾을 수 없습니다."
        }

        var lines: [String] = []

        if activeDelegations.isEmpty && recentDelegations.isEmpty {
            return "진행 중인 위임이 없습니다."
        }

        if !activeDelegations.isEmpty {
            lines.append("## 진행 중 (\(activeDelegations.count))")
            for task in activeDelegations {
                lines.append(formatTaskBrief(task))
            }
        }

        if !recentDelegations.isEmpty {
            lines.append("\n## 최근 완료 (\(recentDelegations.count))")
            for task in recentDelegations.prefix(5) {
                lines.append(formatTaskBrief(task))
            }
        }

        if let chain = currentChain {
            lines.append("\n## 체인 (깊이: \(chain.currentDepth))")
            lines.append("관련 에이전트: \(chain.involvedAgents.joined(separator: " -> "))")
        }

        return lines.joined(separator: "\n")
    }

    private func formatTaskStatus(_ task: DelegationTask) -> String {
        var lines = [
            "위임 ID: \(task.id.uuidString.prefix(8))",
            "상태: \(task.status.rawValue)",
            "발신: \(task.originAgentName) -> 수신: \(task.targetAgentName)",
            "작업: \(task.task)",
        ]
        if let result = task.result {
            lines.append("결과: \(result.prefix(200))")
        }
        if let error = task.errorMessage {
            lines.append("오류: \(error)")
        }
        if let duration = task.durationSeconds {
            lines.append("소요: \(String(format: "%.1f", duration))초")
        }
        return lines.joined(separator: "\n")
    }

    private func formatTaskBrief(_ task: DelegationTask) -> String {
        let statusIcon: String
        switch task.status {
        case .pending: statusIcon = "⏳"
        case .running: statusIcon = "🔄"
        case .completed: statusIcon = "✅"
        case .failed: statusIcon = "❌"
        case .cancelled: statusIcon = "🚫"
        }
        let duration = task.durationSeconds.map { String(format: "%.1fs", $0) } ?? ""
        return "\(statusIcon) \(task.originAgentName)->\(task.targetAgentName): \(task.task.prefix(40)) \(duration)"
    }
}

// MARK: - Delegation Status Tool

@MainActor
final class AgentDelegationStatusTool: BuiltInToolProtocol {
    let name = "agent.delegation_status"
    let category: ToolCategory = .safe
    let description = "에이전트 위임 상태를 확인합니다. 진행 중인 위임과 최근 완료된 위임 목록을 반환합니다."
    let isBaseline = false

    private let delegationManager: DelegationManager?

    init(delegationManager: DelegationManager?) {
        self.delegationManager = delegationManager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "delegation_id": ["type": "string", "description": "특정 위임 ID (미지정 시 전체 요약)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let manager = delegationManager else {
            return ToolResult(toolCallId: "", content: "위임 관리자가 초기화되지 않았습니다.", isError: true)
        }

        var delegationId: UUID?
        if let idStr = arguments["delegation_id"] as? String, !idStr.isEmpty {
            delegationId = UUID(uuidString: idStr)
        }

        let summary = manager.statusSummary(delegationId: delegationId)
        return ToolResult(toolCallId: "", content: summary)
    }
}

// MARK: - Check Agent Status

@MainActor
final class AgentCheckStatusTool: BuiltInToolProtocol {
    let name = "agent.check_status"
    let category: ToolCategory = .safe
    let description = "워크스페이스의 에이전트 목록과 상태를 확인합니다."
    let isBaseline = false

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext
    private let settings: AppSettings

    init(contextService: ContextServiceProtocol, sessionContext: SessionContext, settings: AppSettings) {
        self.contextService = contextService
        self.sessionContext = sessionContext
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "agent_name": ["type": "string", "description": "특정 에이전트 이름 (미지정 시 전체)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let workspaceId = sessionContext.workspaceId
        let agents = contextService.listAgents(workspaceId: workspaceId)

        guard !agents.isEmpty else {
            return ToolResult(toolCallId: "", content: "워크스페이스에 에이전트가 없습니다.")
        }

        if let agentName = arguments["agent_name"] as? String, !agentName.isEmpty {
            guard agents.contains(where: { $0.localizedCaseInsensitiveCompare(agentName) == .orderedSame }) else {
                return ToolResult(toolCallId: "", content: "에이전트 '\(agentName)'을(를) 찾을 수 없습니다.", isError: true)
            }

            let config = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: agentName)
            let hasPersona = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: agentName) != nil
            let hasMemory = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName) != nil
            let isActive = settings.activeAgentName == agentName

            var output = "에이전트: \(agentName)\n"
            output += "상태: \(isActive ? "활성" : "대기")\n"
            output += "페르소나: \(hasPersona ? "있음" : "없음")\n"
            output += "메모리: \(hasMemory ? "있음" : "없음")\n"
            if let config {
                output += "모델: \(config.defaultModel ?? settings.llmModel)\n"
                output += "권한: \(config.effectivePermissions.joined(separator: ", "))\n"
                let delegation = config.effectiveDelegationPolicy
                output += "위임 가능: \(delegation.canDelegate ? "예" : "아니오")\n"
                output += "위임 수신: \(delegation.canReceiveDelegation ? "예" : "아니오")\n"
            }

            return ToolResult(toolCallId: "", content: output)
        }

        var lines: [String] = []
        for agent in agents {
            let isActive = settings.activeAgentName == agent
            let icon = isActive ? "🟢" : "⚪"
            let config = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: agent)
            let perms = config?.effectivePermissions.joined(separator: ",") ?? "기본"
            lines.append("\(icon) \(agent) [\(perms)]")
        }

        return ToolResult(toolCallId: "", content: "에이전트 목록 (\(agents.count)):\n\(lines.joined(separator: "\n"))")
    }
}

