import Foundation
import OSLog

// MARK: - Dochi Dev Bridge Tools

enum DochiDevBridgeTools {

    @MainActor
    static func register(
        toolService: BuiltInToolService,
        manager: ExternalToolSessionManagerProtocol
    ) {
        toolService.registerTool(DochiBridgeOpenTool(manager: manager))
        toolService.registerTool(DochiBridgeStatusTool(manager: manager))
        toolService.registerTool(DochiBridgeRootsTool(manager: manager))
        toolService.registerTool(DochiBridgeSendTool(manager: manager))
        toolService.registerTool(DochiBridgeReadTool(manager: manager))
        toolService.registerTool(DochiLogRecentTool())
        Log.tool.info("Registered 6 dochi dev bridge tools")
    }
}

private enum DochiBridgeAgentPreset: String {
    case codex
    case claude
    case aider

    var command: String {
        switch self {
        case .codex:
            return "codex"
        case .claude:
            return "claude"
        case .aider:
            return "aider"
        }
    }

    var healthPatterns: HealthCheckPatterns {
        switch self {
        case .codex:
            return .codexCLI
        case .claude:
            return .claudeCode
        case .aider:
            return .aider
        }
    }

    var defaultProfileName: String {
        switch self {
        case .codex:
            return "Dochi Bridge Codex"
        case .claude:
            return "Dochi Bridge Claude"
        case .aider:
            return "Dochi Bridge Aider"
        }
    }
}

@MainActor
final class DochiBridgeOpenTool: BuiltInToolProtocol {
    let name = "dochi.bridge_open"
    let category: ToolCategory = .restricted
    let description = "Dochi 개발 브리지 세션을 생성(또는 재사용)하여 Codex/Claude/aider 에이전트 실행 채널을 엽니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "agent": [
                    "type": "string",
                    "enum": ["codex", "claude", "aider"],
                    "description": "브리지에 연결할 에이전트 종류 (기본: codex)",
                ],
                "working_directory": ["type": "string", "description": "작업 디렉토리 (기본: ~)"],
                "force_working_directory": [
                    "type": "boolean",
                    "description": "기존 프로파일의 working_directory를 강제로 덮어씁니다.",
                ],
                "profile_name": ["type": "string", "description": "브리지 프로파일 이름 (기본: 에이전트별 기본값)"],
                "arguments": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "에이전트 명령에 전달할 추가 인자",
                ],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard manager.isTmuxAvailable else {
            return ToolResult(toolCallId: "", content: "tmux를 찾을 수 없어 브리지를 열 수 없습니다. 설정에서 tmux 경로를 확인하세요.", isError: true)
        }

        let agentRaw = (arguments["agent"] as? String ?? "codex").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let preset = DochiBridgeAgentPreset(rawValue: agentRaw) else {
            return ToolResult(toolCallId: "", content: "agent는 codex, claude, aider 중 하나여야 합니다.", isError: true)
        }

        let customName = (arguments["profile_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileName = (customName?.isEmpty == false) ? customName! : preset.defaultProfileName
        let requestedWorkingDirectoryRaw = (arguments["working_directory"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedWorkingDirectory = (requestedWorkingDirectoryRaw?.isEmpty == false)
            ? requestedWorkingDirectoryRaw
            : nil
        let forceWorkingDirectory = arguments["force_working_directory"] as? Bool ?? false
        let extraArgs = arguments["arguments"] as? [String] ?? []

        let existingProfile = manager.profiles.first(where: { $0.name == profileName })
        if let existingProfile,
           let active = manager.sessions.first(where: { $0.profileId == existingProfile.id && $0.status != .dead }) {
            let decision = BridgeWorkingDirectorySelector.decideForActiveSession(
                profileWorkingDirectory: existingProfile.workingDirectory,
                requestedWorkingDirectory: requestedWorkingDirectory,
                forceWorkingDirectory: forceWorkingDirectory
            )
            return ToolResult(toolCallId: "", content: """
                브리지 채널이 이미 열려 있습니다.
                - profile: \(existingProfile.name) (\(existingProfile.id.uuidString))
                - session_id: \(active.id.uuidString)
                - status: \(active.status.rawValue)
                - working_directory: \(decision.workingDirectory)
                - selection_reason: \(decision.selectionReason.rawValue)
                - selection_detail: \(decision.selectionDetail)
                """)
        }

        let recommendedRoots: [GitRepositoryInsight]
        if existingProfile == nil, requestedWorkingDirectory == nil {
            recommendedRoots = await manager.discoverGitRepositoryInsights(searchPaths: nil, limit: 10)
        } else {
            recommendedRoots = []
        }
        let decision = BridgeWorkingDirectorySelector.decide(
            existingProfile: existingProfile,
            requestedWorkingDirectory: requestedWorkingDirectory,
            forceWorkingDirectory: forceWorkingDirectory,
            recommendedRoots: recommendedRoots
        )

        let profile: ExternalToolProfile
        if var existing = existingProfile {
            if decision.selectionReason == .existingProfileOverridden {
                existing.workingDirectory = decision.workingDirectory
                manager.saveProfile(existing)
            }
            profile = existing
        } else {
            let created = ExternalToolProfile(
                name: profileName,
                command: preset.command,
                arguments: extraArgs,
                workingDirectory: decision.workingDirectory,
                healthCheckPatterns: preset.healthPatterns
            )
            manager.saveProfile(created)
            profile = created
        }

        do {
            try await manager.startSession(profileId: profile.id)
            guard let session = manager.sessions.first(where: { $0.profileId == profile.id && $0.status != .dead }) else {
                return ToolResult(toolCallId: "", content: "브리지 세션을 시작했지만 세션 조회에 실패했습니다.", isError: true)
            }

            return ToolResult(toolCallId: "", content: """
                브리지 채널 준비 완료.
                - profile: \(profile.name) (\(profile.id.uuidString))
                - session_id: \(session.id.uuidString)
                - status: \(session.status.rawValue)
                - working_directory: \(decision.workingDirectory)
                - selection_reason: \(decision.selectionReason.rawValue)
                - selection_detail: \(decision.selectionDetail)
                다음 단계:
                1) dochi.bridge_send로 명령 전달
                2) dochi.bridge_read로 출력 확인
                """)
        } catch {
            return ToolResult(toolCallId: "", content: "브리지 채널 시작 실패: \(error.localizedDescription)", isError: true)
        }
    }
}

@MainActor
final class DochiBridgeStatusTool: BuiltInToolProtocol {
    let name = "dochi.bridge_status"
    let category: ToolCategory = .safe
    let description = "Dochi 개발 브리지 세션 상태를 조회합니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 ID(UUID). 생략 시 전체 표시"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        if let sessionIdStr = arguments["session_id"] as? String,
           let sessionId = UUID(uuidString: sessionIdStr) {
            guard let session = manager.sessions.first(where: { $0.id == sessionId }) else {
                return ToolResult(toolCallId: "", content: "세션을 찾을 수 없습니다: \(sessionIdStr)", isError: true)
            }
            let profileName = manager.profiles.first(where: { $0.id == session.profileId })?.name ?? "?"
            return ToolResult(toolCallId: "", content: "[\(profileName)] status=\(session.status.rawValue), session_id=\(session.id.uuidString)")
        }

        var lines = manager.sessions.map { session -> String in
            let profileName = manager.profiles.first(where: { $0.id == session.profileId })?.name ?? "?"
            return "- \(profileName): \(session.status.rawValue) (session_id: \(session.id.uuidString))"
        }

        let unified = await manager.listUnifiedCodingSessions(limit: 60)
        if !unified.isEmpty {
            if !lines.isEmpty { lines.append("") }
            let unassignedCount = unified.filter(\.isUnassigned).count
            lines.append("통합 세션 \(unified.count)개 (unassigned: \(unassignedCount))")
            for item in unified {
                let normalizedTitle = (item.title ?? item.summary)?
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let clippedTitle = normalizedTitle.map { String($0.prefix(100)).replacingOccurrences(of: "\"", with: "'") }
                let titleSegment = clippedTitle.map { " title=\"\($0)\"" } ?? ""
                lines.append("- [\(item.provider)] \(item.nativeSessionId)\(titleSegment) state=\(item.activityState.rawValue) score=\(item.activityScore) tier=\(item.controllabilityTier.rawValue) runtime=\(item.runtimeType.rawValue) repo=\(item.repositoryRoot ?? "(unassigned)")")
            }
        }

        guard !lines.isEmpty else {
            return ToolResult(toolCallId: "", content: "브리지/파일 기반 세션이 없습니다.")
        }
        return ToolResult(toolCallId: "", content: lines.joined(separator: "\n"))
    }
}

@MainActor
final class DochiBridgeRootsTool: BuiltInToolProtocol {
    let name = "dochi.bridge_roots"
    let category: ToolCategory = .safe
    let description = "로컬 Git 루트를 검색하고 활성도 기반 추천 순서로 반환합니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "description": "반환 개수 (기본 20, 최대 200)"],
                "search_paths": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "탐색할 시작 경로 목록",
                ],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let limit = max(1, min(200, arguments["limit"] as? Int ?? 20))
        let searchPaths = arguments["search_paths"] as? [String]
        let roots = await manager.discoverGitRepositoryInsights(searchPaths: searchPaths, limit: limit)

        guard !roots.isEmpty else {
            return ToolResult(toolCallId: "", content: "추천 가능한 Git 루트를 찾지 못했습니다.")
        }

        let lines = roots.map { root in
            let dirty = "\(root.changedFileCount)+\(root.untrackedFileCount)"
            return "[\(root.score)] \(root.name) (\(root.branch)) | \(root.workDomain) | local:\(root.lastCommitRelative) / origin:\(root.upstreamLastCommitRelative) | 30d:\(root.recentCommitCount30d) | dirty:\(dirty)\n\(root.path)"
        }
        return ToolResult(toolCallId: "", content: lines.joined(separator: "\n"))
    }
}

@MainActor
final class DochiBridgeSendTool: BuiltInToolProtocol {
    let name = "dochi.bridge_send"
    let category: ToolCategory = .sensitive
    let description = "브리지 세션으로 명령을 전송합니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 ID (UUID)"],
                "command": ["type": "string", "description": "전송할 명령"],
            ] as [String: Any],
            "required": ["session_id", "command"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let sessionIdStr = arguments["session_id"] as? String,
              let sessionId = UUID(uuidString: sessionIdStr),
              let command = arguments["command"] as? String,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(toolCallId: "", content: "session_id와 command는 필수입니다.", isError: true)
        }

        do {
            try await manager.sendCommand(sessionId: sessionId, command: command)
            return ToolResult(toolCallId: "", content: "브리지 명령 전송됨: \(command)")
        } catch {
            return ToolResult(toolCallId: "", content: "브리지 명령 전송 실패: \(error.localizedDescription)", isError: true)
        }
    }
}

@MainActor
final class DochiBridgeReadTool: BuiltInToolProtocol {
    let name = "dochi.bridge_read"
    let category: ToolCategory = .safe
    let description = "브리지 세션의 최근 출력을 읽습니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 ID (UUID)"],
                "lines": ["type": "integer", "description": "읽을 줄 수 (기본 80, 최대 500)"],
            ] as [String: Any],
            "required": ["session_id"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let sessionIdStr = arguments["session_id"] as? String,
              let sessionId = UUID(uuidString: sessionIdStr) else {
            return ToolResult(toolCallId: "", content: "유효한 session_id가 필요합니다.", isError: true)
        }

        let requestedLines = arguments["lines"] as? Int ?? 80
        let lines = max(1, min(500, requestedLines))
        let output = await manager.captureOutput(sessionId: sessionId, lines: lines)
        if output.isEmpty {
            return ToolResult(toolCallId: "", content: "(출력 없음)")
        }
        return ToolResult(toolCallId: "", content: output.joined(separator: "\n"))
    }
}

struct DochiLogLine: Sendable {
    let date: Date
    let category: String
    let level: String
    let message: String
}

enum DochiLogFetchError: LocalizedError {
    case storeAccessFailed(String)

    var errorDescription: String? {
        switch self {
        case .storeAccessFailed(let message):
            return message
        }
    }
}

typealias DochiLogFetcher = (_ minutes: Int, _ category: String?, _ level: String?, _ contains: String?, _ limit: Int) async throws -> [DochiLogLine]

func fetchDochiLogs(
    minutes: Int,
    category: String?,
    level: String?,
    contains: String?,
    limit: Int
) async throws -> [DochiLogLine] {
    let task = Task.detached { () throws -> [DochiLogLine] in
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let since = store.position(date: Date().addingTimeInterval(TimeInterval(-minutes * 60)))
            let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
            let rawEntries = try store.getEntries(at: since, matching: predicate)

            var matched: [DochiLogLine] = []
            for entry in rawEntries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }

                let categoryMatches: Bool
                if let category, !category.isEmpty {
                    categoryMatches = logEntry.category == category
                } else {
                    categoryMatches = true
                }
                guard categoryMatches else { continue }

                let levelLabel = dochiLogLevelLabel(logEntry.level)
                if let level, !level.isEmpty, levelLabel != level {
                    continue
                }

                let message = logEntry.composedMessage
                if let contains, !contains.isEmpty,
                   !message.localizedCaseInsensitiveContains(contains) {
                    continue
                }

                matched.append(DochiLogLine(
                    date: logEntry.date,
                    category: logEntry.category,
                    level: levelLabel,
                    message: message
                ))
            }

            if matched.count > limit {
                matched = Array(matched.suffix(limit))
            }

            return matched
        } catch {
            throw DochiLogFetchError.storeAccessFailed(error.localizedDescription)
        }
    }
    return try await task.value
}

private func dochiLogLevelLabel(_ level: OSLogEntryLog.Level) -> String {
    switch level {
    case .debug: return "debug"
    case .info: return "info"
    case .notice: return "notice"
    case .error: return "error"
    case .fault: return "fault"
    default: return "undefined"
    }
}

@MainActor
final class DochiLogRecentTool: BuiltInToolProtocol {
    let name = "dochi.log_recent"
    let category: ToolCategory = .safe
    let description = "Dochi 앱의 최근 로그를 필터링해서 조회합니다."
    let isBaseline = false

    private let fetcher: DochiLogFetcher

    init(fetcher: @escaping DochiLogFetcher = fetchDochiLogs) {
        self.fetcher = fetcher
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "minutes": ["type": "integer", "description": "조회 범위(분). 기본 10, 최대 1440"],
                "limit": ["type": "integer", "description": "최대 줄 수. 기본 120, 최대 500"],
                "category": ["type": "string", "description": "카테고리 필터 (예: App, Tool, LLM)"],
                "level": [
                    "type": "string",
                    "enum": ["debug", "info", "notice", "error", "fault"],
                    "description": "레벨 필터",
                ],
                "contains": ["type": "string", "description": "메시지 부분 검색"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let requestedMinutes = arguments["minutes"] as? Int ?? 10
        let minutes = max(1, min(1_440, requestedMinutes))

        let requestedLimit = arguments["limit"] as? Int ?? 120
        let limit = max(1, min(500, requestedLimit))

        let categoryRaw = (arguments["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = (categoryRaw?.isEmpty == false) ? categoryRaw : nil

        let levelRaw = (arguments["level"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowedLevels: Set<String> = ["debug", "info", "notice", "error", "fault"]
        if let levelRaw, !allowedLevels.contains(levelRaw) {
            return ToolResult(toolCallId: "", content: "level은 debug, info, notice, error, fault 중 하나여야 합니다.", isError: true)
        }

        let containsRaw = (arguments["contains"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contains = (containsRaw?.isEmpty == false) ? containsRaw : nil

        do {
            let entries = try await fetcher(minutes, category, levelRaw, contains, limit)
            if entries.isEmpty {
                return ToolResult(toolCallId: "", content: "조건에 맞는 최근 로그가 없습니다.")
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"

            let lines = entries.map { entry in
                let ts = formatter.string(from: entry.date)
                let singleLineMessage = entry.message.replacingOccurrences(of: "\n", with: " ")
                return "[\(ts)] [\(entry.category)] [\(entry.level)] \(singleLineMessage)"
            }

            let header = "최근 로그 \(entries.count)건 (최근 \(minutes)분)"
            return ToolResult(toolCallId: "", content: ([header] + lines).joined(separator: "\n"))
        } catch {
            let errorMessage = error.localizedDescription
            Log.tool.error("dochi.log_recent failed: \(errorMessage)")
            return ToolResult(toolCallId: "", content: "로그 조회 실패: \(errorMessage)", isError: true)
        }
    }
}
