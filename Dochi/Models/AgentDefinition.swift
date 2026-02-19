import Foundation

// MARK: - AgentDefinition

/// 선언적 에이전트 정의 v2.
/// config.json에서 디코딩되며, 기존 AgentConfig와 역호환된다.
struct AgentDefinition: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    var wakeWord: String?
    var description: String?
    var defaultModel: String?
    var permissionProfile: PermissionProfile?
    var toolGroups: [String]
    var subagents: [SubagentDefinition]
    var memoryPolicy: MemoryPolicy?
    var version: Int
    var updatedAt: Date

    // Legacy fields for backward compatibility
    var permissions: [String]?
    var shellPermissions: ShellPermissionConfig?
    var delegationPolicy: DelegationPolicy?

    init(
        id: String = UUID().uuidString,
        name: String,
        wakeWord: String? = nil,
        description: String? = nil,
        defaultModel: String? = nil,
        permissionProfile: PermissionProfile? = nil,
        toolGroups: [String] = [],
        subagents: [SubagentDefinition] = [],
        memoryPolicy: MemoryPolicy? = nil,
        version: Int = 1,
        updatedAt: Date = Date(),
        permissions: [String]? = nil,
        shellPermissions: ShellPermissionConfig? = nil,
        delegationPolicy: DelegationPolicy? = nil
    ) {
        self.id = id
        self.name = name
        self.wakeWord = wakeWord
        self.description = description
        self.defaultModel = defaultModel
        self.permissionProfile = permissionProfile
        self.toolGroups = toolGroups
        self.subagents = subagents
        self.memoryPolicy = memoryPolicy
        self.version = version
        self.updatedAt = updatedAt
        self.permissions = permissions
        self.shellPermissions = shellPermissions
        self.delegationPolicy = delegationPolicy
    }

    // MARK: - Backward Compatible Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // id: 없으면 name에서 생성
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .name)
        name = try container.decode(String.self, forKey: .name)
        wakeWord = try container.decodeIfPresent(String.self, forKey: .wakeWord)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
        permissionProfile = try container.decodeIfPresent(PermissionProfile.self, forKey: .permissionProfile)

        // toolGroups or legacy preferredToolGroups
        if let groups = try container.decodeIfPresent([String].self, forKey: .toolGroups) {
            toolGroups = groups
        } else if let legacy = try container.decodeIfPresent([String].self, forKey: .preferredToolGroups) {
            toolGroups = legacy
        } else {
            toolGroups = []
        }

        subagents = try container.decodeIfPresent([SubagentDefinition].self, forKey: .subagents) ?? []
        memoryPolicy = try container.decodeIfPresent(MemoryPolicy.self, forKey: .memoryPolicy)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        // Legacy fields
        permissions = try container.decodeIfPresent([String].self, forKey: .permissions)
        shellPermissions = try container.decodeIfPresent(ShellPermissionConfig.self, forKey: .shellPermissions)
        delegationPolicy = try container.decodeIfPresent(DelegationPolicy.self, forKey: .delegationPolicy)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, wakeWord, description, defaultModel
        case permissionProfile, toolGroups, preferredToolGroups
        case subagents, memoryPolicy, version, updatedAt
        case permissions, shellPermissions, delegationPolicy
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(wakeWord, forKey: .wakeWord)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(defaultModel, forKey: .defaultModel)
        try container.encodeIfPresent(permissionProfile, forKey: .permissionProfile)
        try container.encode(toolGroups, forKey: .toolGroups)
        if !subagents.isEmpty {
            try container.encode(subagents, forKey: .subagents)
        }
        try container.encodeIfPresent(memoryPolicy, forKey: .memoryPolicy)
        try container.encode(version, forKey: .version)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(shellPermissions, forKey: .shellPermissions)
        try container.encodeIfPresent(delegationPolicy, forKey: .delegationPolicy)
    }

    // MARK: - Computed

    /// 유효한 permissionProfile 또는 레거시 permissions에서 변환
    var effectivePermissionProfile: PermissionProfile {
        if let profile = permissionProfile { return profile }
        // 레거시 permissions 배열에서 변환
        let perms = permissions ?? ["safe", "sensitive", "restricted"]
        return PermissionProfile(
            safe: perms.contains("safe") ? .allow : .deny,
            sensitive: perms.contains("sensitive") ? .confirm : .deny,
            restricted: perms.contains("restricted") ? .confirm : .deny
        )
    }

    var effectiveToolGroups: [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for raw in toolGroups {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    /// AgentConfig로 변환 (레거시 호환)
    func toAgentConfig() -> AgentConfig {
        AgentConfig(
            name: name,
            wakeWord: wakeWord,
            description: description,
            defaultModel: defaultModel,
            permissions: permissions,
            preferredToolGroups: toolGroups.isEmpty ? nil : toolGroups,
            shellPermissions: shellPermissions,
            delegationPolicy: delegationPolicy
        )
    }

    /// AgentConfig에서 변환
    static func from(config: AgentConfig) -> AgentDefinition {
        AgentDefinition(
            id: config.name,
            name: config.name,
            wakeWord: config.wakeWord,
            description: config.description,
            defaultModel: config.defaultModel,
            toolGroups: config.preferredToolGroups ?? [],
            version: 1,
            permissions: config.permissions,
            shellPermissions: config.shellPermissions,
            delegationPolicy: config.delegationPolicy
        )
    }

    /// 버전 증가 복사본
    func incrementedVersion() -> AgentDefinition {
        var copy = self
        copy.version = version + 1
        copy.updatedAt = Date()
        return copy
    }
}

// MARK: - PermissionProfile

/// safe/sensitive/restricted 각각의 권한 정책
struct PermissionProfile: Codable, Sendable, Equatable {
    let safe: PermissionAction
    let sensitive: PermissionAction
    let restricted: PermissionAction

    static let `default` = PermissionProfile(
        safe: .allow,
        sensitive: .confirm,
        restricted: .deny
    )

    /// 최소 권한 프로필 (safe만 허용)
    static let minimal = PermissionProfile(
        safe: .allow,
        sensitive: .deny,
        restricted: .deny
    )
}

// MARK: - PermissionAction

enum PermissionAction: String, Codable, Sendable {
    case allow
    case confirm
    case deny
}

// MARK: - SubagentDefinition

/// 서브에이전트 선언
struct SubagentDefinition: Codable, Sendable, Identifiable {
    let id: String
    var name: String?
    var description: String?
    var toolGroups: [String]
    var permissionProfile: PermissionProfile?

    init(
        id: String,
        name: String? = nil,
        description: String? = nil,
        toolGroups: [String] = [],
        permissionProfile: PermissionProfile? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.toolGroups = toolGroups
        self.permissionProfile = permissionProfile
    }
}

// MARK: - MemoryPolicy

/// 에이전트별 메모리 정책
struct MemoryPolicy: Codable, Sendable, Equatable {
    /// 개인 메모리 접근 가능 여부
    var personalMemoryAccess: Bool

    /// 워크스페이스 메모리 접근 가능 여부
    var workspaceMemoryAccess: Bool

    /// 에이전트 메모리 접근 가능 여부
    var agentMemoryAccess: Bool

    /// 메모리 자동 추출 활성화 여부
    var autoExtractEnabled: Bool

    init(
        personalMemoryAccess: Bool = true,
        workspaceMemoryAccess: Bool = true,
        agentMemoryAccess: Bool = true,
        autoExtractEnabled: Bool = true
    ) {
        self.personalMemoryAccess = personalMemoryAccess
        self.workspaceMemoryAccess = workspaceMemoryAccess
        self.agentMemoryAccess = agentMemoryAccess
        self.autoExtractEnabled = autoExtractEnabled
    }

    static let `default` = MemoryPolicy()

    /// 서브에이전트 기본 정책: 개인 메모리 없음
    static let subagentDefault = MemoryPolicy(
        personalMemoryAccess: false,
        workspaceMemoryAccess: true,
        agentMemoryAccess: true,
        autoExtractEnabled: false
    )
}

// MARK: - LoadedAgentDefinition

/// 파일시스템에서 로드된 에이전트 정의 (config + persona + memory)
struct LoadedAgentDefinition: Sendable {
    let definition: AgentDefinition
    let systemPrompt: String?
    let memory: String?
    let workspaceId: UUID
}
