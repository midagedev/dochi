import Foundation

/// 내장 도구 라우터 - 각 도구 모듈을 통합 관리
@MainActor
final class BuiltInToolService: ObservableObject {
    @Published private(set) var error: String?

    let webSearchTool = WebSearchTool()
    let remindersTool = RemindersTool()
    let alarmTool = AlarmTool()
    let imageGenerationTool = ImageGenerationTool()
    let printImageTool = PrintImageTool()
    let memoryTool = MemoryTool()
    let profileTool = ProfileTool()

    /// 활성 알람 (AlarmTool에서 포워딩)
    var activeAlarms: [AlarmTool.AlarmEntry] {
        alarmTool.activeAlarms
    }

    /// 알람 발동 콜백 (AlarmTool에서 포워딩)
    var onAlarmFired: ((String) -> Void)? {
        get { alarmTool.onAlarmFired }
        set { alarmTool.onAlarmFired = newValue }
    }

    func configure(tavilyApiKey: String, falaiApiKey: String) {
        webSearchTool.apiKey = tavilyApiKey
        imageGenerationTool.apiKey = falaiApiKey
    }

    /// 사용자 컨텍스트 설정 (MemoryTool, ProfileTool에 contextService와 현재 사용자 전달)
    func configureUserContext(contextService: (any ContextServiceProtocol)?, currentUserId: UUID?) {
        memoryTool.contextService = contextService
        memoryTool.currentUserId = currentUserId
        profileTool.contextService = contextService
    }

    var availableTools: [MCPToolInfo] {
        var tools: [MCPToolInfo] = []

        // 웹검색: API 키 있을 때만
        if !webSearchTool.apiKey.isEmpty {
            tools.append(contentsOf: webSearchTool.tools)
        }

        // 미리알림: 항상 사용 가능
        tools.append(contentsOf: remindersTool.tools)

        // 알람: 항상 사용 가능
        tools.append(contentsOf: alarmTool.tools)

        // 이미지 생성: API 키 있을 때만
        if !imageGenerationTool.apiKey.isEmpty {
            tools.append(contentsOf: imageGenerationTool.tools)
        }

        // 이미지 프린트: 항상 사용 가능
        tools.append(contentsOf: printImageTool.tools)

        // 기억 관리: 프로필이 있을 때만
        if memoryTool.contextService != nil {
            tools.append(contentsOf: memoryTool.tools)
        }

        // 사용자 식별: 프로필이 있을 때만
        if profileTool.contextService != nil {
            tools.append(contentsOf: profileTool.tools)
        }

        return tools
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        // 각 도구 모듈에 라우팅
        let allModules: [any BuiltInTool] = [webSearchTool, remindersTool, alarmTool, imageGenerationTool, printImageTool, memoryTool, profileTool]

        for module in allModules {
            if module.tools.contains(where: { $0.name == name }) {
                return try await module.callTool(name: name, arguments: arguments)
            }
        }

        throw BuiltInToolError.unknownTool(name)
    }
}

// MARK: - Errors

enum BuiltInToolError: LocalizedError {
    case unknownTool(String)
    case missingApiKey(String)
    case invalidArguments(String)
    case apiError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown built-in tool: \(name)"
        case .missingApiKey(let service):
            return "\(service) API key is not configured"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .apiError(let message):
            return message
        case .invalidResponse(let message):
            return message
        }
    }
}
