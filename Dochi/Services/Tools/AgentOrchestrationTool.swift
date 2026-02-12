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

    init(contextService: ContextServiceProtocol, sessionContext: SessionContext, settings: AppSettings) {
        self.contextService = contextService
        self.sessionContext = sessionContext
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "agent_name": ["type": "string", "description": "위임할 에이전트 이름"],
                "task": ["type": "string", "description": "에이전트에게 전달할 작업 설명"],
                "context": ["type": "string", "description": "추가 컨텍스트 (선택)"],
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

        let workspaceId = sessionContext.workspaceId
        let agents = contextService.listAgents(workspaceId: workspaceId)

        guard agents.contains(where: { $0.localizedCaseInsensitiveCompare(agentName) == .orderedSame }) else {
            let available = agents.joined(separator: ", ")
            return ToolResult(toolCallId: "", content: "에이전트 '\(agentName)'을(를) 찾을 수 없습니다. 사용 가능: \(available)", isError: true)
        }

        // Load agent persona
        let persona = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: agentName)
        let memory = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName)
        let additionalContext = arguments["context"] as? String ?? ""

        Log.tool.info("Delegating task to agent '\(agentName)': \(task.prefix(100))")

        let summary = """
            위임 작업 준비 완료:
            - 대상 에이전트: \(agentName)
            - 작업: \(task)
            - 페르소나: \(persona?.prefix(200) ?? "(없음)")…
            - 메모리: \(memory?.prefix(200) ?? "(없음)")…
            \(additionalContext.isEmpty ? "" : "- 추가 컨텍스트: \(additionalContext)")

            에이전트 '\(agentName)'에게 작업이 전달되었습니다. 해당 에이전트의 페르소나와 메모리를 참고하여 응답을 생성하세요.
            """

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
