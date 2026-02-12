import Foundation
import os

// MARK: - Shared Helper

private enum AgentResolveResult {
    case success(String)
    case failure(ToolResult)
}

@MainActor
private func resolveAgentName(
    arguments: [String: Any],
    settings: AppSettings,
    contextService: ContextServiceProtocol,
    sessionContext: SessionContext
) -> AgentResolveResult {
    let agentName: String
    if let name = arguments["name"] as? String, !name.isEmpty {
        agentName = name
    } else {
        agentName = settings.activeAgentName
    }

    let existingAgents = contextService.listAgents(workspaceId: sessionContext.workspaceId)
    guard existingAgents.contains(agentName) else {
        let available = existingAgents.joined(separator: ", ")
        let hint = available.isEmpty ? "등록된 에이전트가 없습니다." : "사용 가능한 에이전트: \(available)"
        return .failure(ToolResult(toolCallId: "", content: "오류: '\(agentName)' 에이전트를 찾을 수 없습니다. \(hint)", isError: true))
    }

    return .success(agentName)
}

// MARK: - agent.persona_get

@MainActor
final class AgentPersonaGetTool: BuiltInToolProtocol {
    let name = "agent.persona_get"
    let category: ToolCategory = .sensitive
    let description = "에이전트의 페르소나 전체 텍스트를 조회합니다."
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
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            guard let persona = contextService.loadAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 페르소나가 비어 있습니다.")
            }
            Log.tool.info("Loaded persona for agent: \(agentName)")
            return ToolResult(toolCallId: "", content: persona)
        }
    }
}

// MARK: - agent.persona_search

@MainActor
final class AgentPersonaSearchTool: BuiltInToolProtocol {
    let name = "agent.persona_search"
    let category: ToolCategory = .sensitive
    let description = "에이전트 페르소나에서 특정 문자열이 포함된 줄을 검색합니다."
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
                "query": ["type": "string", "description": "검색할 문자열"],
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ],
            "required": ["query"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: query는 필수입니다.", isError: true)
        }

        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            guard let persona = contextService.loadAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 페르소나가 비어 있습니다.")
            }

            let lines = persona.components(separatedBy: "\n")
            var matches: [String] = []
            for (index, line) in lines.enumerated() {
                if line.localizedCaseInsensitiveContains(query) {
                    matches.append("\(index + 1): \(line)")
                }
            }

            if matches.isEmpty {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 페르소나에서 '\(query)'을(를) 찾을 수 없습니다.")
            }

            Log.tool.info("Persona search for agent \(agentName): \(matches.count) matches")
            return ToolResult(toolCallId: "", content: "검색 결과 (\(matches.count)건):\n\(matches.joined(separator: "\n"))")
        }
    }
}

// MARK: - agent.persona_update

@MainActor
final class AgentPersonaUpdateTool: BuiltInToolProtocol {
    let name = "agent.persona_update"
    let category: ToolCategory = .sensitive
    let description = "에이전트 페르소나를 교체하거나 내용을 추가합니다."
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
                "mode": [
                    "type": "string",
                    "enum": ["replace", "append"],
                    "description": "replace: 전체 교체, append: 끝에 추가"
                ],
                "content": ["type": "string", "description": "페르소나 내용"],
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ],
            "required": ["mode", "content"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let mode = arguments["mode"] as? String, mode == "replace" || mode == "append" else {
            return ToolResult(toolCallId: "", content: "오류: mode는 'replace' 또는 'append'이어야 합니다.", isError: true)
        }
        guard let content = arguments["content"] as? String, !content.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: content는 필수입니다.", isError: true)
        }

        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            if mode == "replace" {
                contextService.saveAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName, content: content)
                Log.tool.info("Replaced persona for agent: \(agentName)")
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 페르소나를 교체했습니다.")
            } else {
                let existing = contextService.loadAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName) ?? ""
                let updated = existing.isEmpty ? content : existing + "\n" + content
                contextService.saveAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName, content: updated)
                Log.tool.info("Appended to persona for agent: \(agentName)")
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 페르소나에 내용을 추가했습니다.")
            }
        }
    }
}

// MARK: - agent.persona_replace

@MainActor
final class AgentPersonaReplaceTool: BuiltInToolProtocol {
    let name = "agent.persona_replace"
    let category: ToolCategory = .sensitive
    let description = "에이전트 페르소나에서 특정 문자열을 찾아 대체합니다."
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
                "find": ["type": "string", "description": "찾을 문자열"],
                "replace": ["type": "string", "description": "대체할 문자열"],
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"],
                "preview": ["type": "boolean", "description": "미리보기만 수행 (실제 변경 안 함)"],
                "confirm": ["type": "boolean", "description": "다수 매치 시 확인 플래그"]
            ],
            "required": ["find", "replace"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let find = arguments["find"] as? String, !find.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: find는 필수입니다.", isError: true)
        }
        guard let replaceWith = arguments["replace"] as? String else {
            return ToolResult(toolCallId: "", content: "오류: replace는 필수입니다.", isError: true)
        }

        let preview = arguments["preview"] as? Bool ?? false
        let confirm = arguments["confirm"] as? Bool ?? false

        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            guard let persona = contextService.loadAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 페르소나가 비어 있습니다.", isError: true)
            }

            let matchCount = persona.components(separatedBy: find).count - 1
            if matchCount == 0 {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 페르소나에서 '\(find)'을(를) 찾을 수 없습니다.", isError: true)
            }

            if matchCount > 5 && !confirm {
                return ToolResult(toolCallId: "", content: "오류: \(matchCount)건의 매치가 발견되었습니다. 다수 변경을 진행하려면 confirm: true를 전달해주세요.", isError: true)
            }

            let updated = persona.replacingOccurrences(of: find, with: replaceWith)

            if preview {
                return ToolResult(toolCallId: "", content: "[미리보기] \(matchCount)건 매치 — 변경 후:\n\(updated)")
            }

            contextService.saveAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName, content: updated)
            Log.tool.info("Persona replace for agent \(agentName): \(matchCount) matches")
            return ToolResult(toolCallId: "", content: "'\(agentName)' 페르소나에서 \(matchCount)건을 대체했습니다.")
        }
    }
}

// MARK: - agent.persona_delete_lines

@MainActor
final class AgentPersonaDeleteLinesTool: BuiltInToolProtocol {
    let name = "agent.persona_delete_lines"
    let category: ToolCategory = .sensitive
    let description = "에이전트 페르소나에서 특정 문자열을 포함하는 줄을 삭제합니다."
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
                "contains": ["type": "string", "description": "삭제할 줄에 포함된 문자열"],
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"],
                "preview": ["type": "boolean", "description": "미리보기만 수행 (실제 삭제 안 함)"],
                "confirm": ["type": "boolean", "description": "다수 매치 시 확인 플래그"]
            ],
            "required": ["contains"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let containsStr = arguments["contains"] as? String, !containsStr.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: contains는 필수입니다.", isError: true)
        }

        let preview = arguments["preview"] as? Bool ?? false
        let confirm = arguments["confirm"] as? Bool ?? false

        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            guard let persona = contextService.loadAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 페르소나가 비어 있습니다.", isError: true)
            }

            let lines = persona.components(separatedBy: "\n")
            let matchingLines = lines.enumerated().filter { $0.element.contains(containsStr) }
            let matchCount = matchingLines.count

            if matchCount == 0 {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 페르소나에서 '\(containsStr)'을(를) 포함하는 줄을 찾을 수 없습니다.", isError: true)
            }

            if matchCount > 5 && !confirm {
                return ToolResult(toolCallId: "", content: "오류: \(matchCount)줄이 매치되었습니다. 다수 삭제를 진행하려면 confirm: true를 전달해주세요.", isError: true)
            }

            let deletedLines = matchingLines.map { "\($0.offset + 1): \($0.element)" }

            if preview {
                return ToolResult(toolCallId: "", content: "[미리보기] 삭제 대상 \(matchCount)줄:\n\(deletedLines.joined(separator: "\n"))")
            }

            let remaining = lines.enumerated()
                .filter { !$0.element.contains(containsStr) }
                .map { $0.element }
            let updated = remaining.joined(separator: "\n")

            contextService.saveAgentPersona(workspaceId: sessionContext.workspaceId, agentName: agentName, content: updated)
            Log.tool.info("Persona delete lines for agent \(agentName): \(matchCount) lines removed")
            return ToolResult(toolCallId: "", content: "'\(agentName)' 페르소나에서 \(matchCount)줄을 삭제했습니다.\n삭제된 줄:\n\(deletedLines.joined(separator: "\n"))")
        }
    }
}

// MARK: - agent.memory_get

@MainActor
final class AgentMemoryGetTool: BuiltInToolProtocol {
    let name = "agent.memory_get"
    let category: ToolCategory = .sensitive
    let description = "에이전트의 메모리 내용을 조회합니다."
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
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            guard let memory = contextService.loadAgentMemory(workspaceId: sessionContext.workspaceId, agentName: agentName) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 메모리가 비어 있습니다.")
            }
            Log.tool.info("Loaded memory for agent: \(agentName)")
            return ToolResult(toolCallId: "", content: memory)
        }
    }
}

// MARK: - agent.memory_append

@MainActor
final class AgentMemoryAppendTool: BuiltInToolProtocol {
    let name = "agent.memory_append"
    let category: ToolCategory = .sensitive
    let description = "에이전트 메모리에 내용을 추가합니다."
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
                "content": ["type": "string", "description": "추가할 내용"],
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ],
            "required": ["content"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let content = arguments["content"] as? String, !content.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: content는 필수입니다.", isError: true)
        }

        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            contextService.appendAgentMemory(workspaceId: sessionContext.workspaceId, agentName: agentName, content: content)
            Log.tool.info("Appended memory for agent: \(agentName)")
            return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 메모리에 내용을 추가했습니다.")
        }
    }
}

// MARK: - agent.memory_replace

@MainActor
final class AgentMemoryReplaceTool: BuiltInToolProtocol {
    let name = "agent.memory_replace"
    let category: ToolCategory = .sensitive
    let description = "에이전트 메모리 전체를 교체합니다."
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
                "content": ["type": "string", "description": "새 메모리 내용"],
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ],
            "required": ["content"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let content = arguments["content"] as? String, !content.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: content는 필수입니다.", isError: true)
        }

        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            contextService.saveAgentMemory(workspaceId: sessionContext.workspaceId, agentName: agentName, content: content)
            Log.tool.info("Replaced memory for agent: \(agentName)")
            return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 메모리를 교체했습니다.")
        }
    }
}

// MARK: - agent.memory_update

@MainActor
final class AgentMemoryUpdateTool: BuiltInToolProtocol {
    let name = "agent.memory_update"
    let category: ToolCategory = .sensitive
    let description = "에이전트 메모리에서 특정 문자열을 찾아 대체합니다."
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
                "find": ["type": "string", "description": "찾을 문자열"],
                "replace": ["type": "string", "description": "대체할 문자열"],
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ],
            "required": ["find", "replace"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let find = arguments["find"] as? String, !find.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: find는 필수입니다.", isError: true)
        }
        guard let replaceWith = arguments["replace"] as? String else {
            return ToolResult(toolCallId: "", content: "오류: replace는 필수입니다.", isError: true)
        }

        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            guard let memory = contextService.loadAgentMemory(workspaceId: sessionContext.workspaceId, agentName: agentName) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 메모리가 비어 있습니다.", isError: true)
            }

            guard memory.contains(find) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 메모리에서 '\(find)'을(를) 찾을 수 없습니다.", isError: true)
            }

            let updated = memory.replacingOccurrences(of: find, with: replaceWith)
            contextService.saveAgentMemory(workspaceId: sessionContext.workspaceId, agentName: agentName, content: updated)
            Log.tool.info("Updated memory for agent: \(agentName)")
            return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 메모리를 수정했습니다.")
        }
    }
}

// MARK: - agent.config_get

@MainActor
final class AgentConfigGetTool: BuiltInToolProtocol {
    let name = "agent.config_get"
    let category: ToolCategory = .sensitive
    let description = "에이전트의 설정 정보를 조회합니다."
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
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            guard let config = contextService.loadAgentConfig(workspaceId: sessionContext.workspaceId, agentName: agentName) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 설정을 찾을 수 없습니다.", isError: true)
            }

            let lines: [String] = [
                "이름: \(config.name)",
                "호출어: \(config.wakeWord ?? "(없음)")",
                "설명: \(config.description ?? "(없음)")",
                "기본 모델: \(config.defaultModel ?? "(없음)")",
                "권한: \(config.effectivePermissions.joined(separator: ", "))"
            ]

            Log.tool.info("Loaded config for agent: \(agentName)")
            return ToolResult(toolCallId: "", content: lines.joined(separator: "\n"))
        }
    }
}

// MARK: - agent.config_update

@MainActor
final class AgentConfigUpdateTool: BuiltInToolProtocol {
    let name = "agent.config_update"
    let category: ToolCategory = .sensitive
    let description = "에이전트 설정의 특정 필드를 수정합니다."
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
                "wake_word": ["type": "string", "description": "새 호출어"],
                "description": ["type": "string", "description": "새 설명"],
                "name": ["type": "string", "description": "에이전트 이름 (미지정 시 활성 에이전트)"]
            ]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let newWakeWord = arguments["wake_word"] as? String
        let newDescription = arguments["description"] as? String

        if newWakeWord == nil && newDescription == nil {
            return ToolResult(toolCallId: "", content: "오류: 수정할 필드가 없습니다. wake_word 또는 description을 지정해주세요.", isError: true)
        }

        switch resolveAgentName(arguments: arguments, settings: settings, contextService: contextService, sessionContext: sessionContext) {
        case .failure(let error):
            return error
        case .success(let agentName):
            guard var config = contextService.loadAgentConfig(workspaceId: sessionContext.workspaceId, agentName: agentName) else {
                return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트의 설정을 찾을 수 없습니다.", isError: true)
            }

            var changes: [String] = []

            if let wakeWord = newWakeWord {
                config.wakeWord = wakeWord
                changes.append("호출어: \(wakeWord)")
            }
            if let description = newDescription {
                config.description = description
                changes.append("설명: \(description)")
            }

            contextService.saveAgentConfig(workspaceId: sessionContext.workspaceId, config: config)
            Log.tool.info("Updated config for agent: \(agentName)")
            return ToolResult(toolCallId: "", content: "'\(agentName)' 에이전트 설정을 수정했습니다.\n변경: \(changes.joined(separator: ", "))")
        }
    }
}
