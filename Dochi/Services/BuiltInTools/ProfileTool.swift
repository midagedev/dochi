import Foundation
import os

/// 사용자 식별 도구 (set_current_user)
@MainActor
final class ProfileTool: BuiltInTool {
    var contextService: ContextServiceProtocol?
    var onUserIdentified: ((UserProfile) -> Void)?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:set_current_user",
                name: "set_current_user",
                description: "Identify the current user by name. If the name matches an existing profile, that profile is used. If not, a new profile is created automatically.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "The user's name or nickname"
                        ]
                    ],
                    "required": ["name"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard name == "set_current_user" else {
            throw BuiltInToolError.unknownTool(name)
        }
        guard let contextService else {
            throw BuiltInToolError.invalidArguments("ContextService not configured")
        }
        return setCurrentUser(arguments: arguments, contextService: contextService)
    }

    private func setCurrentUser(arguments: [String: Any], contextService: ContextServiceProtocol) -> MCPToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return MCPToolResult(content: "name is required", isError: true)
        }

        var profiles = contextService.loadProfiles()

        // 기존 프로필에서 이름/별칭 매칭 (case-insensitive, contains)
        if let existing = profiles.first(where: { profile in
            profile.allNames.contains { $0.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0) }
        }) {
            onUserIdentified?(existing)
            Log.tool.info("사용자 식별: \(existing.name) (기존 프로필)")
            return MCPToolResult(content: "사용자를 \(existing.name)(으)로 식별했습니다.", isError: false)
        }

        // 프로필에 없으면 자동 생성
        let newProfile = UserProfile(name: name)
        profiles.append(newProfile)
        contextService.saveProfiles(profiles)
        onUserIdentified?(newProfile)
        Log.tool.info("사용자 식별: \(name) (새 프로필 생성)")
        return MCPToolResult(content: "\(name) 프로필을 새로 생성하고 현재 사용자로 설정했습니다.", isError: false)
    }
}
