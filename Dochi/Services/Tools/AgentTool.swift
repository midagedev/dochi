import Foundation
import os

// MARK: - agent.create

@MainActor
final class AgentCreateTool: BuiltInToolProtocol {
    let name = "agent.create"
    let category: ToolCategory = .sensitive
    let description = "새 에이전트를 생성합니다."
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
                "name": ["type": "string", "description": "에이전트 이름"],
                "wake_word": ["type": "string", "description": "호출어 (선택)"],
                "description": ["type": "string", "description": "에이전트 설명 (선택)"]
            ],
            "required": ["name"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let agentName = arguments["name"] as? String, !agentName.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: name은 필수입니다.", isError: true)
        }

        let existingAgents = contextService.listAgents(workspaceId: sessionContext.workspaceId)
        if existingAgents.contains(agentName) {
            return ToolResult(toolCallId: "", content: "오류: '\(agentName)' 에이전트가 이미 존재합니다.", isError: true)
        }

        let wakeWord = arguments["wake_word"] as? String
        let description = arguments["description"] as? String

        contextService.createAgent(
            workspaceId: sessionContext.workspaceId,
            name: agentName,
            wakeWord: wakeWord,
            description: description
        )

        Log.tool.info("Created agent: \(agentName)")
        return ToolResult(toolCallId: "", content: "에이전트 '\(agentName)'을(를) 생성했습니다.")
    }
}

// MARK: - agent.list

@MainActor
final class AgentListTool: BuiltInToolProtocol {
    let name = "agent.list"
    let category: ToolCategory = .sensitive
    let description = "워크스페이스의 에이전트 목록을 조회합니다."
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
            "properties": [String: Any]()
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let agentNames = contextService.listAgents(workspaceId: sessionContext.workspaceId)

        if agentNames.isEmpty {
            return ToolResult(toolCallId: "", content: "등록된 에이전트가 없습니다.")
        }

        let activeAgent = settings.activeAgentName
        var lines: [String] = []

        for agentName in agentNames {
            let config = contextService.loadAgentConfig(workspaceId: sessionContext.workspaceId, agentName: agentName)
            let isActive = agentName == activeAgent
            let marker = isActive ? " ★ (활성)" : ""

            var parts: [String] = ["• \(agentName)\(marker)"]
            if let wakeWord = config?.wakeWord {
                parts.append("  호출어: \(wakeWord)")
            }
            if let desc = config?.description {
                parts.append("  설명: \(desc)")
            }
            if let config = config {
                parts.append("  권한: \(config.effectivePermissions.joined(separator: ", "))")
            }
            lines.append(parts.joined(separator: "\n"))
        }

        Log.tool.info("Listed \(agentNames.count) agents")
        return ToolResult(toolCallId: "", content: "에이전트 목록 (\(agentNames.count)개):\n\(lines.joined(separator: "\n"))")
    }
}

// MARK: - agent.set_active

@MainActor
final class AgentSetActiveTool: BuiltInToolProtocol {
    let name = "agent.set_active"
    let category: ToolCategory = .sensitive
    let description = "활성 에이전트를 변경합니다."
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
                "name": ["type": "string", "description": "활성화할 에이전트 이름"]
            ],
            "required": ["name"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let agentName = arguments["name"] as? String, !agentName.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: name은 필수입니다.", isError: true)
        }

        let existingAgents = contextService.listAgents(workspaceId: sessionContext.workspaceId)
        guard existingAgents.contains(agentName) else {
            let available = existingAgents.joined(separator: ", ")
            let hint = available.isEmpty ? "등록된 에이전트가 없습니다." : "사용 가능한 에이전트: \(available)"
            return ToolResult(toolCallId: "", content: "오류: '\(agentName)' 에이전트를 찾을 수 없습니다. \(hint)", isError: true)
        }

        settings.activeAgentName = agentName
        Log.tool.info("Active agent set to: \(agentName)")
        return ToolResult(toolCallId: "", content: "활성 에이전트를 '\(agentName)'(으)로 변경했습니다.")
    }
}
