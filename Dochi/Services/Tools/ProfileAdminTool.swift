import Foundation
import os

// MARK: - profile.create

@MainActor
final class ProfileCreateTool: BuiltInToolProtocol {
    let name = "profile.create"
    let category: ToolCategory = .sensitive
    let description = "새 사용자 프로필을 생성합니다."
    let isBaseline = false

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext

    init(contextService: ContextServiceProtocol, sessionContext: SessionContext) {
        self.contextService = contextService
        self.sessionContext = sessionContext
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "프로필 이름"],
                "aliases": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "별칭 목록 (선택)"
                ],
                "description": ["type": "string", "description": "프로필 설명 (선택)"]
            ],
            "required": ["name"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: name은 필수입니다.", isError: true)
        }

        var profiles = contextService.loadProfiles()
        let lowered = name.lowercased()

        if profiles.contains(where: { $0.name.lowercased() == lowered }) {
            return ToolResult(toolCallId: "", content: "오류: '\(name)' 이름의 프로필이 이미 존재합니다.", isError: true)
        }

        let aliases = arguments["aliases"] as? [String] ?? []
        let desc = arguments["description"] as? String

        let profile = UserProfile(name: name, aliases: aliases, description: desc)
        profiles.append(profile)
        contextService.saveProfiles(profiles)

        Log.tool.info("Created profile: \(name) (id: \(profile.id))")
        return ToolResult(toolCallId: "", content: "프로필 '\(name)'을(를) 생성했습니다. (ID: \(profile.id.uuidString))")
    }
}

// MARK: - profile.add_alias

@MainActor
final class ProfileAddAliasTool: BuiltInToolProtocol {
    let name = "profile.add_alias"
    let category: ToolCategory = .sensitive
    let description = "기존 프로필에 별칭을 추가합니다."
    let isBaseline = false

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext

    init(contextService: ContextServiceProtocol, sessionContext: SessionContext) {
        self.contextService = contextService
        self.sessionContext = sessionContext
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "프로필 이름"],
                "alias": ["type": "string", "description": "추가할 별칭"]
            ],
            "required": ["name", "alias"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: name은 필수입니다.", isError: true)
        }
        guard let alias = arguments["alias"] as? String, !alias.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: alias는 필수입니다.", isError: true)
        }

        var profiles = contextService.loadProfiles()
        let loweredName = name.lowercased()
        let loweredAlias = alias.lowercased()

        guard let index = profiles.firstIndex(where: { $0.name.lowercased() == loweredName }) else {
            return ToolResult(toolCallId: "", content: "오류: '\(name)' 프로필을 찾을 수 없습니다.", isError: true)
        }

        // Check if alias already exists on any profile
        let aliasExists = profiles.contains { profile in
            profile.name.lowercased() == loweredAlias ||
            profile.aliases.contains(where: { $0.lowercased() == loweredAlias })
        }
        if aliasExists {
            return ToolResult(toolCallId: "", content: "오류: '\(alias)' 별칭이 이미 다른 프로필에 존재합니다.", isError: true)
        }

        profiles[index].aliases.append(alias)
        contextService.saveProfiles(profiles)

        Log.tool.info("Added alias '\(alias)' to profile '\(profiles[index].name)'")
        return ToolResult(toolCallId: "", content: "'\(profiles[index].name)' 프로필에 별칭 '\(alias)'을(를) 추가했습니다.")
    }
}

// MARK: - profile.rename

@MainActor
final class ProfileRenameTool: BuiltInToolProtocol {
    let name = "profile.rename"
    let category: ToolCategory = .sensitive
    let description = "프로필의 이름을 변경합니다."
    let isBaseline = false

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext

    init(contextService: ContextServiceProtocol, sessionContext: SessionContext) {
        self.contextService = contextService
        self.sessionContext = sessionContext
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "from": ["type": "string", "description": "현재 프로필 이름"],
                "to": ["type": "string", "description": "변경할 새 이름"]
            ],
            "required": ["from", "to"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let from = arguments["from"] as? String, !from.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: from은 필수입니다.", isError: true)
        }
        guard let to = arguments["to"] as? String, !to.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: to는 필수입니다.", isError: true)
        }

        var profiles = contextService.loadProfiles()
        let loweredFrom = from.lowercased()
        let loweredTo = to.lowercased()

        guard let index = profiles.firstIndex(where: { $0.name.lowercased() == loweredFrom }) else {
            return ToolResult(toolCallId: "", content: "오류: '\(from)' 프로필을 찾을 수 없습니다.", isError: true)
        }

        if profiles.contains(where: { $0.name.lowercased() == loweredTo }) {
            return ToolResult(toolCallId: "", content: "오류: '\(to)' 이름의 프로필이 이미 존재합니다.", isError: true)
        }

        let oldName = profiles[index].name
        profiles[index].name = to
        contextService.saveProfiles(profiles)

        Log.tool.info("Renamed profile '\(oldName)' to '\(to)'")
        return ToolResult(toolCallId: "", content: "프로필 이름을 '\(oldName)'에서 '\(to)'(으)로 변경했습니다.")
    }
}

// MARK: - profile.merge

@MainActor
final class ProfileMergeTool: BuiltInToolProtocol {
    let name = "profile.merge"
    let category: ToolCategory = .sensitive
    let description = "두 프로필을 병합합니다. 소스 프로필이 대상 프로필로 통합됩니다."
    let isBaseline = false

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext

    init(contextService: ContextServiceProtocol, sessionContext: SessionContext) {
        self.contextService = contextService
        self.sessionContext = sessionContext
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "source": ["type": "string", "description": "병합할 소스 프로필 이름"],
                "target": ["type": "string", "description": "병합 대상 프로필 이름"],
                "merge_memory": [
                    "type": "string",
                    "enum": ["append", "skip", "replace"],
                    "description": "메모리 병합 전략: append (추가), skip (대상 유지), replace (소스로 교체)"
                ]
            ],
            "required": ["source", "target", "merge_memory"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let sourceName = arguments["source"] as? String, !sourceName.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: source는 필수입니다.", isError: true)
        }
        guard let targetName = arguments["target"] as? String, !targetName.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: target은 필수입니다.", isError: true)
        }
        guard let mergeMemory = arguments["merge_memory"] as? String,
              ["append", "skip", "replace"].contains(mergeMemory) else {
            return ToolResult(toolCallId: "", content: "오류: merge_memory는 'append', 'skip', 'replace' 중 하나여야 합니다.", isError: true)
        }

        let loweredSource = sourceName.lowercased()
        let loweredTarget = targetName.lowercased()

        if loweredSource == loweredTarget {
            return ToolResult(toolCallId: "", content: "오류: source와 target이 같은 프로필입니다.", isError: true)
        }

        var profiles = contextService.loadProfiles()

        guard let sourceIndex = profiles.firstIndex(where: { $0.name.lowercased() == loweredSource }) else {
            return ToolResult(toolCallId: "", content: "오류: 소스 프로필 '\(sourceName)'을(를) 찾을 수 없습니다.", isError: true)
        }
        guard let targetIndex = profiles.firstIndex(where: { $0.name.lowercased() == loweredTarget }) else {
            return ToolResult(toolCallId: "", content: "오류: 대상 프로필 '\(targetName)'을(를) 찾을 수 없습니다.", isError: true)
        }

        let sourceProfile = profiles[sourceIndex]
        let sourceId = sourceProfile.id.uuidString
        let targetId = profiles[targetIndex].id.uuidString

        // Move aliases from source to target
        profiles[targetIndex].aliases.append(contentsOf: sourceProfile.aliases)
        profiles[targetIndex].aliases.append(sourceProfile.name)

        // Handle personal memory based on merge strategy
        let sourceMemory = contextService.loadUserMemory(userId: sourceId)
        switch mergeMemory {
        case "append":
            if let memory = sourceMemory, !memory.isEmpty {
                contextService.appendUserMemory(userId: targetId, content: memory)
            }
        case "replace":
            contextService.saveUserMemory(userId: targetId, content: sourceMemory ?? "")
        case "skip":
            break
        default:
            break
        }

        // Update sessionContext if current user was pointing to source
        if sessionContext.currentUserId == sourceId {
            sessionContext.currentUserId = targetId
            Log.tool.info("Updated currentUserId from source to target after merge")
        }

        // Remove source profile (use id match to avoid index shift issues)
        profiles.removeAll { $0.id == sourceProfile.id }
        contextService.saveProfiles(profiles)

        Log.tool.info("Merged profile '\(sourceProfile.name)' into '\(targetName)' (memory: \(mergeMemory))")
        return ToolResult(toolCallId: "", content: "프로필 '\(sourceProfile.name)'을(를) '\(targetName)'(으)로 병합했습니다. (메모리 전략: \(mergeMemory))")
    }
}
