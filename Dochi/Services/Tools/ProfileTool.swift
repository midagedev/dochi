import Foundation
import os

@MainActor
final class SetCurrentUserTool: BuiltInToolProtocol {
    let name = "set_current_user"
    let category: ToolCategory = .safe
    let description = "현재 대화 사용자를 이름 또는 별칭으로 설정합니다."
    let isBaseline = true

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
                "name": ["type": "string", "description": "사용자 이름 또는 별칭"]
            ],
            "required": ["name"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: name은 필수입니다.", isError: true)
        }

        let profiles = contextService.loadProfiles()
        let lowered = name.lowercased()

        let matched = profiles.first { profile in
            profile.name.lowercased() == lowered ||
            profile.aliases.contains(where: { $0.lowercased() == lowered })
        }

        guard let profile = matched else {
            let available = profiles.map(\.name).joined(separator: ", ")
            let hint = available.isEmpty ? "등록된 프로필이 없습니다." : "등록된 사용자: \(available)"
            return ToolResult(toolCallId: "", content: "오류: '\(name)' 사용자를 찾을 수 없습니다. \(hint)", isError: true)
        }

        sessionContext.currentUserId = profile.id.uuidString
        Log.tool.info("Current user set to: \(profile.name) (\(profile.id))")
        return ToolResult(toolCallId: "", content: "현재 사용자를 '\(profile.name)'(으)로 설정했습니다.")
    }
}
