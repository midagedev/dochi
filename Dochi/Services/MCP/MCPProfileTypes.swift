import Foundation

// MARK: - MCPServerStatus

/// Represents the health state of an individual MCP server within a profile.
enum MCPServerStatus: Sendable, Equatable {
    case connected
    case disconnected
    case error(String)
    case restarting

    var isAvailable: Bool {
        if case .connected = self { return true }
        return false
    }

    var localizedDescription: String {
        switch self {
        case .connected:
            "연결됨"
        case .disconnected:
            "연결 해제"
        case .error(let msg):
            "오류: \(msg)"
        case .restarting:
            "재시작 중"
        }
    }
}

// MARK: - MCPProfileHealthReport

/// Aggregated health snapshot for all servers in a profile.
struct MCPProfileHealthReport: Sendable {
    let profileName: String
    let serverStatuses: [(serverName: String, status: MCPServerStatus)]
    let timestamp: Date

    init(
        profileName: String,
        serverStatuses: [(serverName: String, status: MCPServerStatus)],
        timestamp: Date = Date()
    ) {
        self.profileName = profileName
        self.serverStatuses = serverStatuses
        self.timestamp = timestamp
    }

    var allHealthy: Bool {
        serverStatuses.allSatisfy { $0.status.isAvailable }
    }

    var healthyCount: Int {
        serverStatuses.filter { $0.status.isAvailable }.count
    }

    var unhealthyServerNames: [String] {
        serverStatuses.filter { !$0.status.isAvailable }.map(\.serverName)
    }

    var localizedSummary: String {
        if allHealthy {
            return "프로파일 '\(profileName)': 모든 서버 정상 (\(serverStatuses.count)개)"
        }
        let unhealthy = unhealthyServerNames.joined(separator: ", ")
        return "프로파일 '\(profileName)': \(healthyCount)/\(serverStatuses.count)개 정상, 비정상: \(unhealthy)"
    }
}

// MARK: - MCPRestartTracker

/// Tracks restart attempts per server to enforce configurable limits.
struct MCPRestartTracker: Sendable {
    private(set) var attempts: Int = 0
    let maxAttempts: Int

    init(maxAttempts: Int = 3) {
        self.maxAttempts = max(1, maxAttempts)
    }

    var canRestart: Bool {
        attempts < maxAttempts
    }

    mutating func recordAttempt() {
        attempts += 1
    }

    mutating func reset() {
        attempts = 0
    }
}
