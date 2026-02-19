import Foundation

// MARK: - K-4: External AI Tool Session Manager Models

enum ExternalToolStatus: String, Codable, Sendable {
    case idle
    case busy
    case waiting
    case error
    case dead
    case unknown
}

enum DiscoveredCodingSessionSource: String, Codable, Sendable {
    case codexSessionFile = "codex_session_file"
    case claudeProjectFile = "claude_project_file"
    case claudeTaskDirectory = "claude_task_directory"
}

struct DiscoveredCodingSession: Sendable, Equatable {
    let source: DiscoveredCodingSessionSource
    let provider: String
    let sessionId: String
    let workingDirectory: String?
    let path: String
    let updatedAt: Date
    let isActive: Bool
}

enum ManagedGitRepositorySource: String, Codable, Sendable {
    case initialized = "initialized"
    case cloned = "cloned"
    case attached = "attached"
}

struct ManagedGitRepository: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var rootPath: String
    var source: ManagedGitRepositorySource
    var originURL: String?
    var defaultBranch: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        source: ManagedGitRepositorySource,
        originURL: String?,
        defaultBranch: String?,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.source = source
        self.originURL = originURL
        self.defaultBranch = defaultBranch
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ExternalTerminalApp: String, CaseIterable, Codable, Sendable {
    case auto
    case terminal
    case ghostty

    var displayName: String {
        switch self {
        case .auto:
            return "자동 (Ghostty 우선)"
        case .terminal:
            return "Terminal.app"
        case .ghostty:
            return "Ghostty"
        }
    }
}

struct HealthCheckPatterns: Codable, Sendable, Equatable {
    var idlePattern: String
    var busyPattern: String
    var waitingPattern: String
    var errorPattern: String

    static let claudeCode = HealthCheckPatterns(
        idlePattern: "^>\\s*$",
        busyPattern: "(Thinking|Writing|Reading|Editing)",
        waitingPattern: "\\[Y/n\\]|\\[y/N\\]",
        errorPattern: "(Error|error|FAILED)"
    )

    static let codexCLI = HealthCheckPatterns(
        idlePattern: "^\\$\\s*$",
        busyPattern: "(Running|Generating)",
        waitingPattern: "\\[Y/n\\]|\\[y/N\\]",
        errorPattern: "(Error|error|FAILED)"
    )

    static let aider = HealthCheckPatterns(
        idlePattern: "^>\\s*$",
        busyPattern: "(Thinking|Editing|Committing)",
        waitingPattern: "\\[Y/n\\]|\\[y/N\\]",
        errorPattern: "(Error|error|FAILED)"
    )
}

struct SSHConfig: Codable, Sendable, Equatable {
    var host: String
    var port: Int
    var user: String
    var keyPath: String?

    init(host: String, port: Int = 22, user: String, keyPath: String? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.keyPath = keyPath
    }
}

struct ExternalToolProfile: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var command: String
    var arguments: [String]
    var workingDirectory: String
    var sshConfig: SSHConfig?
    var healthCheckPatterns: HealthCheckPatterns

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "terminal.fill",
        command: String,
        arguments: [String] = [],
        workingDirectory: String = "~",
        sshConfig: SSHConfig? = nil,
        healthCheckPatterns: HealthCheckPatterns = .claudeCode
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.sshConfig = sshConfig
        self.healthCheckPatterns = healthCheckPatterns
    }

    var isRemote: Bool { sshConfig != nil }
}

// MARK: - Presets

enum ExternalToolPreset: String, CaseIterable, Sendable {
    case claudeCode = "Claude Code"
    case codexCLI = "Codex CLI"
    case aider = "aider"

    var profile: ExternalToolProfile {
        switch self {
        case .claudeCode:
            return ExternalToolProfile(
                name: "Claude Code",
                icon: "terminal.fill",
                command: "claude",
                arguments: [],
                healthCheckPatterns: .claudeCode
            )
        case .codexCLI:
            return ExternalToolProfile(
                name: "Codex CLI",
                icon: "terminal.fill",
                command: "codex",
                arguments: [],
                healthCheckPatterns: .codexCLI
            )
        case .aider:
            return ExternalToolProfile(
                name: "aider",
                icon: "terminal.fill",
                command: "aider",
                arguments: [],
                healthCheckPatterns: .aider
            )
        }
    }
}

// MARK: - Session

@MainActor
@Observable
final class ExternalToolSession: Identifiable, @unchecked Sendable {
    let id: UUID
    let profileId: UUID
    var tmuxSessionName: String
    var status: ExternalToolStatus
    var lastOutput: [String]
    var lastHealthCheckDate: Date?
    var startedAt: Date?
    var lastActivityText: String?

    init(
        id: UUID = UUID(),
        profileId: UUID,
        tmuxSessionName: String,
        status: ExternalToolStatus = .unknown,
        lastOutput: [String] = [],
        startedAt: Date? = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.tmuxSessionName = tmuxSessionName
        self.status = status
        self.lastOutput = lastOutput
        self.startedAt = startedAt
    }
}
