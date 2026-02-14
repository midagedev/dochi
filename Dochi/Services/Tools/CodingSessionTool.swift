import Foundation

// MARK: - Session List Tool

@MainActor
final class CodingSessionListTool: BuiltInToolProtocol {
    let name = "coding.sessions"
    let category: ToolCategory = .safe
    let description = "현재 코딩 에이전트 세션 목록을 조회합니다."
    let isBaseline = false

    private let sessionManager: CodingSessionManager

    init(sessionManager: CodingSessionManager) {
        self.sessionManager = sessionManager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "status": [
                    "type": "string",
                    "enum": ["active", "paused", "completed", "failed", "all"],
                    "description": "필터할 상태 (기본: all)",
                ],
            ] as [String: Any],
            "required": [] as [String],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let filterStatus = arguments["status"] as? String ?? "all"

        let sessions: [CodingSession]
        if filterStatus == "all" {
            sessions = sessionManager.allSessions()
        } else if filterStatus == "active" {
            sessions = sessionManager.activeSessions()
        } else {
            let status = CodingSessionStatus(rawValue: filterStatus)
            sessions = sessionManager.allSessions().filter { $0.status == status }
        }

        guard !sessions.isEmpty else {
            return ToolResult(toolCallId: "", content: "코딩 세션이 없습니다.")
        }

        let lines = sessions.map { s in
            let statusIcon: String
            switch s.status {
            case .active: statusIcon = "▶️"
            case .paused: statusIcon = "⏸️"
            case .completed: statusIcon = "✅"
            case .failed: statusIcon = "❌"
            }
            return "\(statusIcon) [\(s.id.uuidString.prefix(8))] \(s.agentType.displayName) — \(s.workingDirectory) (\(s.stepCount)단계)"
        }

        return ToolResult(toolCallId: "", content: "코딩 세션 목록 (\(sessions.count)개):\n" + lines.joined(separator: "\n"))
    }
}

// MARK: - Session Start Tool

@MainActor
final class CodingSessionStartTool: BuiltInToolProtocol {
    let name = "coding.session_start"
    let category: ToolCategory = .restricted
    let description = "새 코딩 에이전트 세션을 시작합니다."
    let isBaseline = false

    private let sessionManager: CodingSessionManager

    init(sessionManager: CodingSessionManager) {
        self.sessionManager = sessionManager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "work_dir": ["type": "string", "description": "작업 디렉토리 경로"],
                "agent": [
                    "type": "string",
                    "enum": ["claude_code", "codex"],
                    "description": "코딩 에이전트 유형 (기본: claude_code)",
                ],
            ] as [String: Any],
            "required": ["work_dir"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let workDir = arguments["work_dir"] as? String, !workDir.isEmpty else {
            return ToolResult(toolCallId: "", content: "work_dir 파라미터가 필요합니다.", isError: true)
        }

        let expandedDir = NSString(string: workDir).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedDir) else {
            return ToolResult(toolCallId: "", content: "디렉토리를 찾을 수 없습니다: \(workDir)", isError: true)
        }

        let agentRaw = arguments["agent"] as? String ?? "claude_code"
        let agentType = CodingAgentType(rawValue: agentRaw) ?? .claudeCode

        let session = sessionManager.createSession(
            agentType: agentType,
            workingDirectory: expandedDir
        )

        return ToolResult(toolCallId: "", content: """
            세션 시작됨:
            - ID: \(session.id.uuidString.prefix(8))
            - 에이전트: \(session.agentType.displayName)
            - 디렉토리: \(session.workingDirectory)
            """)
    }
}

// MARK: - Session Pause/Resume Tool

@MainActor
final class CodingSessionPauseTool: BuiltInToolProtocol {
    let name = "coding.session_pause"
    let category: ToolCategory = .safe
    let description = "코딩 세션을 일시정지하거나 재개합니다."
    let isBaseline = false

    private let sessionManager: CodingSessionManager

    init(sessionManager: CodingSessionManager) {
        self.sessionManager = sessionManager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 UUID (앞 8자리 가능)"],
                "action": [
                    "type": "string",
                    "enum": ["pause", "resume"],
                    "description": "일시정지 또는 재개",
                ],
            ] as [String: Any],
            "required": ["session_id", "action"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let sessionIdStr = arguments["session_id"] as? String else {
            return ToolResult(toolCallId: "", content: "session_id가 필요합니다.", isError: true)
        }
        guard let action = arguments["action"] as? String else {
            return ToolResult(toolCallId: "", content: "action이 필요합니다.", isError: true)
        }

        let sessionId = resolveSessionId(sessionIdStr)
        guard let sessionId else {
            return ToolResult(toolCallId: "", content: "세션을 찾을 수 없습니다: \(sessionIdStr)", isError: true)
        }

        let success: Bool
        if action == "pause" {
            success = sessionManager.pauseSession(id: sessionId)
        } else {
            success = sessionManager.resumeSession(id: sessionId)
        }

        guard success else {
            return ToolResult(toolCallId: "", content: "세션 상태 변경 실패. 현재 상태를 확인해주세요.", isError: true)
        }

        return ToolResult(toolCallId: "", content: "세션 [\(sessionId.uuidString.prefix(8))] \(action == "pause" ? "일시정지" : "재개")됨")
    }

    private func resolveSessionId(_ input: String) -> UUID? {
        if let uuid = UUID(uuidString: input) {
            return sessionManager.session(id: uuid) != nil ? uuid : nil
        }
        // Partial match
        let lowered = input.lowercased()
        return sessionManager.allSessions()
            .first { $0.id.uuidString.lowercased().hasPrefix(lowered) }?.id
    }
}

// MARK: - Session End Tool

@MainActor
final class CodingSessionEndTool: BuiltInToolProtocol {
    let name = "coding.session_end"
    let category: ToolCategory = .safe
    let description = "코딩 세션을 완료 또는 실패로 종료합니다."
    let isBaseline = false

    private let sessionManager: CodingSessionManager

    init(sessionManager: CodingSessionManager) {
        self.sessionManager = sessionManager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 UUID (앞 8자리 가능)"],
                "result": [
                    "type": "string",
                    "enum": ["completed", "failed"],
                    "description": "종료 상태 (기본: completed)",
                ],
                "summary": ["type": "string", "description": "작업 요약"],
            ] as [String: Any],
            "required": ["session_id"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let sessionIdStr = arguments["session_id"] as? String else {
            return ToolResult(toolCallId: "", content: "session_id가 필요합니다.", isError: true)
        }

        let result = arguments["result"] as? String ?? "completed"
        let summary = arguments["summary"] as? String

        let sessionId = resolveSessionId(sessionIdStr)
        guard let sessionId else {
            return ToolResult(toolCallId: "", content: "세션을 찾을 수 없습니다: \(sessionIdStr)", isError: true)
        }

        let success: Bool
        if result == "failed" {
            success = sessionManager.failSession(id: sessionId, summary: summary)
        } else {
            success = sessionManager.completeSession(id: sessionId, summary: summary)
        }

        guard success else {
            return ToolResult(toolCallId: "", content: "세션 종료 실패.", isError: true)
        }

        let session = sessionManager.session(id: sessionId)!
        return ToolResult(toolCallId: "", content: """
            세션 종료됨:
            - ID: \(sessionId.uuidString.prefix(8))
            - 상태: \(result == "failed" ? "실패" : "완료")
            - 총 단계: \(session.stepCount) (성공: \(session.successfulSteps), 실패: \(session.failedSteps))
            \(summary.map { "- 요약: \($0)" } ?? "")
            """)
    }

    private func resolveSessionId(_ input: String) -> UUID? {
        if let uuid = UUID(uuidString: input) {
            return sessionManager.session(id: uuid) != nil ? uuid : nil
        }
        let lowered = input.lowercased()
        return sessionManager.allSessions()
            .first { $0.id.uuidString.lowercased().hasPrefix(lowered) }?.id
    }
}
