import AgentRuntimeCore
import AgentRuntimeMemory
import Foundation
import Observation

enum MobileAgentPhase: String, Sendable {
    case starting
    case ready
    case thinking
    case usingTool
    case speaking
    case failed

    var statusText: String {
        switch self {
        case .starting: "준비하는 중"
        case .ready: "대화할 준비가 됐어요"
        case .thinking: "생각하는 중"
        case .usingTool: "도구를 사용하는 중"
        case .speaking: "답변하는 중"
        case .failed: "설정을 확인해 주세요"
        }
    }

    var isBusy: Bool {
        switch self {
        case .starting, .thinking, .usingTool, .speaking: true
        case .ready, .failed: false
        }
    }
}

enum MobileProviderKind: String, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openAI
    case gemini
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .openAICompatible: "OpenAI 호환"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-5"
        case .openAI: "gpt-5.6"
        case .gemini: "gemini-3.5-flash"
        case .openAICompatible: ""
        }
    }

    var keychainAccount: String { "agent-provider-\(rawValue)-api-key" }

    var requiresAPIKey: Bool { self != .openAICompatible }
}

struct MobileAvatar: Identifiable, Hashable, Sendable {
    let assetName: String
    let displayName: String

    var id: String { assetName }

    static let all: [MobileAvatar] = [
        MobileAvatar(assetName: "Avatar_dogo_burger", displayName: "버거 강아지"),
        MobileAvatar(assetName: "Avatar_chubby_tubby_cat", displayName: "통통 고양이"),
        MobileAvatar(assetName: "Avatar_cute_moth", displayName: "보송 나방"),
        MobileAvatar(assetName: "Avatar_cute_saurus", displayName: "꼬마 공룡"),
        MobileAvatar(assetName: "Avatar_dino_kid", displayName: "공룡 친구"),
        MobileAvatar(assetName: "Avatar_megan_the_fox", displayName: "여우 메건"),
        MobileAvatar(assetName: "Avatar_weird_cat", displayName: "엉뚱 고양이"),
    ]

    static func named(_ assetName: String) -> MobileAvatar {
        all.first { $0.assetName == assetName } ?? all[0]
    }
}

enum MobileMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

struct MobileChatMessage: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var role: MobileMessageRole
    var text: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: MobileMessageRole,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }

    var agentMessage: AgentMessage {
        AgentMessage(
            id: id,
            role: role == .user ? .user : .assistant,
            content: [.text(text)],
            createdAt: createdAt
        )
    }

    static func displayMessages(from history: [AgentMessage]) -> [MobileChatMessage] {
        history.compactMap { message in
            let role: MobileMessageRole
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system, .tool: return nil
            }
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MobileChatMessage(
                id: message.id,
                role: role,
                text: text,
                createdAt: message.createdAt
            )
        }
    }
}

struct MobileConversationSnapshot: Codable, Sendable, Hashable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var userID: String
    var sessionID: String
    var providerID: String?
    var modelID: String?
    var messages: [AgentMessage]
    var updatedAt: Date

    init(
        schemaVersion: Int = currentSchemaVersion,
        userID: String,
        sessionID: String,
        providerID: String? = nil,
        modelID: String? = nil,
        messages: [AgentMessage],
        updatedAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.userID = userID
        self.sessionID = sessionID
        self.providerID = providerID
        self.modelID = modelID
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

@MainActor
@Observable
final class MobileAgentPreferences {
    private enum Key {
        static let provider = "mobile.agent.provider"
        // Used only to migrate the original single-model preference.
        static let model = "mobile.agent.model"
        static let modelPrefix = "mobile.agent.model."
        static let compatibleBaseURL = "mobile.agent.compatibleBaseURL"
        static let memoryEnabled = "mobile.agent.memoryEnabled"
        static let speechInputEnabled = "mobile.agent.speechInputEnabled"
        static let speakReplies = "mobile.agent.speakReplies"
        static let hapticsEnabled = "mobile.agent.hapticsEnabled"
        static let avatar = "mobile.avatar"
        static let userID = "mobile.agent.userID"
        static let sessionID = "mobile.agent.sessionID"
    }

    private(set) var providerKind: String {
        didSet { defaults.set(providerKind, forKey: Key.provider) }
    }
    var model: String {
        didSet {
            defaults.set(model, forKey: Self.modelKey(for: currentProvider))
            defaults.set(model, forKey: Key.model)
        }
    }
    var compatibleBaseURL: String {
        didSet { defaults.set(compatibleBaseURL, forKey: Key.compatibleBaseURL) }
    }
    var memoryEnabled: Bool {
        didSet { defaults.set(memoryEnabled, forKey: Key.memoryEnabled) }
    }
    var speechInputEnabled: Bool {
        didSet { defaults.set(speechInputEnabled, forKey: Key.speechInputEnabled) }
    }
    var speakReplies: Bool {
        didSet { defaults.set(speakReplies, forKey: Key.speakReplies) }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }
    var avatarName: String {
        didSet { defaults.set(avatarName, forKey: Key.avatar) }
    }

    private(set) var userID: String
    private(set) var sessionID: String

    var currentProvider: MobileProviderKind {
        MobileProviderKind(rawValue: providerKind) ?? .anthropic
    }

    var selectedAvatar: MobileAvatar { MobileAvatar.named(avatarName) }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let provider = MobileProviderKind(
            rawValue: defaults.string(forKey: Key.provider) ?? ""
        ) ?? .anthropic
        providerKind = provider.rawValue
        let providerModel = defaults.string(forKey: Self.modelKey(for: provider))
        let legacyModel = defaults.string(forKey: Key.model)
        model = providerModel ?? legacyModel ?? provider.defaultModel
        compatibleBaseURL = defaults.string(forKey: Key.compatibleBaseURL) ?? "http://127.0.0.1:11434/v1"
        memoryEnabled = defaults.object(forKey: Key.memoryEnabled) as? Bool ?? true
        speechInputEnabled = defaults.object(forKey: Key.speechInputEnabled) as? Bool ?? true
        speakReplies = defaults.object(forKey: Key.speakReplies) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        avatarName = defaults.string(forKey: Key.avatar) ?? MobileAvatar.all[0].assetName

        let storedUserID = defaults.string(forKey: Key.userID)
        userID = Self.validIdentifier(storedUserID) ?? UUID().uuidString.lowercased()
        let storedSessionID = defaults.string(forKey: Key.sessionID)
        sessionID = Self.validIdentifier(storedSessionID) ?? UUID().uuidString.lowercased()
        defaults.set(userID, forKey: Key.userID)
        defaults.set(sessionID, forKey: Key.sessionID)
        defaults.set(model, forKey: Self.modelKey(for: provider))
    }

    func selectProvider(_ provider: MobileProviderKind) {
        providerKind = provider.rawValue
        model = defaults.string(forKey: Self.modelKey(for: provider)) ?? provider.defaultModel
    }

    func restoreSessionID(_ candidate: String) {
        guard let identifier = Self.validIdentifier(candidate) else { return }
        sessionID = identifier
        defaults.set(identifier, forKey: Key.sessionID)
    }

    @discardableResult
    func beginNewSession() -> String {
        let identifier = UUID().uuidString.lowercased()
        sessionID = identifier
        defaults.set(identifier, forKey: Key.sessionID)
        return identifier
    }

    private static func validIdentifier(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= 128,
              value.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics
                      .union(CharacterSet(charactersIn: "-_."))
                      .contains(scalar)
              }) else { return nil }
        return value
    }

    private static func modelKey(for provider: MobileProviderKind) -> String {
        Key.modelPrefix + provider.rawValue
    }
}

enum MobileHistoryCompatibility {
    static func sanitizedHistory(
        _ history: [AgentMessage],
        storedProviderID: String?,
        storedModelID: String?,
        currentProviderID: String,
        currentModelID: String
    ) -> [AgentMessage] {
        let hasProviderBoundState = history.contains { message in
            message.providerContinuation != nil
                || message.role == .tool
                || message.content.contains { content in
                    switch content {
                    case .toolCall, .toolResult: true
                    case .text, .image: false
                    }
                }
        }
        let providerChanged = storedProviderID.map { $0 != currentProviderID }
            ?? hasProviderBoundState
        let modelChanged = storedModelID.map { $0 != currentModelID }
            ?? hasProviderBoundState
        guard providerChanged || modelChanged else { return history }
        return MobileChatMessage.displayMessages(from: history).map(\.agentMessage)
    }
}

enum MobileToolPresentation {
    static func friendlyName(_ name: String) -> String {
        switch name {
        case "memory.save": "기억 저장"
        case "memory.search": "기억 찾기"
        case "memory.archive": "기억 보관"
        case "memory.persist_sensitive": "민감한 기억 저장"
        default: name.replacingOccurrences(of: ".", with: " ")
        }
    }

    static func approvalMessage(for request: AgentToolApprovalRequest) -> String {
        let risk: String
        switch request.descriptor.risk {
        case .safe: risk = "일반 도구"
        case .sensitive: risk = "민감한 정보에 접근할 수 있는 도구"
        case .restricted: risk = "제한된 작업을 수행하는 도구"
        }
        var sections = [
            "\(friendlyName(request.call.name))은(는) \(risk)입니다.",
            "요청 이유: \(request.reason)",
        ]
        if let argumentSummary = redactedArgumentSummary(for: request) {
            sections.append("요청 인수 (민감 값 제외):\n\(argumentSummary)")
        }
        if request.call.name == "memory.persist_sensitive",
           let content = request.call.arguments["content"]?.stringValue {
            sections.append("저장할 내용:\n\(content)")
        }
        sections.append("내용을 확인한 경우에만 허용해 주세요.")
        return sections.joined(separator: "\n\n")
    }

    /// Shows the exact fields required to make an informed decision while
    /// redacting every argument that is not explicitly safe for that tool.
    /// This prevents a future tool schema from accidentally exposing a secret
    /// merely because it was added to the model-generated argument object.
    static func redactedArgumentSummary(for request: AgentToolApprovalRequest) -> String? {
        guard let arguments = request.call.arguments.objectValue,
              !arguments.isEmpty else { return nil }

        let visibleKeys: Set<String>
        switch request.call.name {
        case "memory.archive":
            visibleKeys = ["scope", "id", "expected_revision"]
        case "memory.persist_sensitive":
            visibleKeys = ["scope", "kind", "sensitivity"]
        default:
            visibleKeys = []
        }

        return arguments.keys.sorted().map { key in
            guard visibleKeys.contains(key), let value = arguments[key] else {
                if request.call.name == "memory.persist_sensitive", key == "content" {
                    return "content: [아래에서 직접 확인]"
                }
                return "\(key): [값 숨김]"
            }
            return "\(key): \(safeScalarDescription(value))"
        }
        .joined(separator: "\n")
    }

    static func allowsSessionApproval(_ request: AgentToolApprovalRequest) -> Bool {
        guard request.call.name != "memory.persist_sensitive",
              request.descriptor.risk != .restricted else { return false }
        switch request.descriptor.sideEffect {
        case .nonIdempotent: return false
        case .none, .idempotent: return true
        }
    }

    private static func safeScalarDescription(_ value: JSONValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        case .number, .integer, .unsignedInteger, .decimal, .null:
            return (try? value.encodedString()) ?? "[표시할 수 없음]"
        case .array, .object:
            return "[구조화된 값 숨김]"
        }
    }
}

enum MobileMemoryPresentation {
    static func scopeLabel(_ scope: MemoryScope) -> String {
        switch scope.level {
        case .application:
            return "앱 전체"
        case .user:
            return "사용자"
        case .agent:
            return identifierLabel(prefix: "에이전트", identifier: scope.agentID)
        case .workspace:
            return identifierLabel(prefix: "작업 공간", identifier: scope.workspaceID)
        case .session:
            return identifierLabel(prefix: "대화", identifier: scope.sessionID)
        }
    }

    static func kindLabel(_ kind: MemoryKind) -> String {
        switch kind {
        case .fact: "사실"
        case .preference: "선호"
        case .instruction: "지침"
        case .summary: "요약"
        case .episode: "경험"
        case .relationship: "관계"
        case .task: "할 일"
        case .observation: "관찰"
        }
    }

    static func statusLabel(_ record: MemoryRecord, at date: Date = .now) -> String {
        let status: String
        switch record.status {
        case .proposed: status = "제안됨"
        case .active: status = "활성"
        case .superseded: status = "대체됨"
        case .archived: status = "보관됨"
        case .rejected: status = "거절됨"
        case .deleted: status = "삭제 표시됨"
        }
        return record.isExpired(at: date) ? "\(status) · 만료됨" : status
    }

    static func updatedLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func deletionPreview(_ content: String, maximumLength: Int = 100) -> String {
        let normalized = content
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard normalized.count > maximumLength else { return normalized }
        return String(normalized.prefix(maximumLength)) + "…"
    }

    private static func identifierLabel(prefix: String, identifier: String?) -> String {
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else { return prefix }
        return "\(prefix) · \(identifier.prefix(8))"
    }
}

enum MobileCompatibleEndpoint {
    static func validatedBaseURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw MobileAgentError.invalidBaseURL
        }

        guard scheme == "https" || (scheme == "http" && isLoopback(host)) else {
            throw MobileAgentError.insecureBaseURL
        }
        components.scheme = scheme
        guard let url = components.url else { throw MobileAgentError.invalidBaseURL }
        return url
    }

    static func chatCompletionsEndpoint(from rawValue: String) throws -> URL {
        let baseURL = try validatedBaseURL(from: rawValue)
        let components = baseURL.pathComponents.filter { $0 != "/" }
        if components.suffix(2) == ["chat", "completions"] { return baseURL }
        if components.isEmpty {
            return baseURL
                .appendingPathComponent("v1", isDirectory: true)
                .appendingPathComponent("chat", isDirectory: true)
                .appendingPathComponent("completions", isDirectory: false)
        }
        return baseURL
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("completions", isDirectory: false)
    }

    static func isLoopback(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if normalized == "localhost" || normalized.hasSuffix(".localhost") || normalized == "::1" {
            return true
        }
        let octets = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.first == "127",
              octets.allSatisfy({ part in
                  guard let value = Int(part) else { return false }
                  return (0...255).contains(value)
              }) else { return false }
        return true
    }
}

actor MobileConversationStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func load(fallbackUserID: String, fallbackSessionID: String) throws -> MobileConversationSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        try ensureRegularDestination(fileURL)
        let data = try Data(contentsOf: fileURL)
        if let snapshot = try? decoder.decode(MobileConversationSnapshot.self, from: data) {
            guard snapshot.schemaVersion <= MobileConversationSnapshot.currentSchemaVersion else {
                throw MobileAgentError.unsupportedConversationSnapshot
            }
            return snapshot
        }

        // One-time migration from the first mobile prototype, which stored only
        // rendered user/assistant text and could not preserve provider turn state.
        let legacy = try decoder.decode([MobileChatMessage].self, from: data)
        return MobileConversationSnapshot(
            userID: fallbackUserID,
            sessionID: fallbackSessionID,
            messages: legacy.map(\.agentMessage)
        )
    }

    func save(_ snapshot: MobileConversationSnapshot) throws {
        try Task.checkCancellation()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard directoryAttributes[.type] as? FileAttributeType == .typeDirectory else {
            throw MobileAgentError.unsafeConversationLocation
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )
        try ensureRegularDestination(fileURL)
        let data = try encoder.encode(snapshot)
        try Task.checkCancellation()
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }

    private func ensureRegularDestination(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw MobileAgentError.unsafeConversationLocation
        }
    }
}

enum MobileAgentError: LocalizedError, Equatable {
    case notInitialized
    case invalidBaseURL
    case insecureBaseURL
    case emptyModel
    case unsupportedConversationSnapshot
    case unsafeConversationLocation

    var errorDescription: String? {
        switch self {
        case .notInitialized: "에이전트 런타임을 초기화하지 못했습니다."
        case .invalidBaseURL: "OpenAI 호환 서버 주소가 올바르지 않습니다."
        case .insecureBaseURL: "외부 서버는 HTTPS만 허용합니다. HTTP는 이 기기의 loopback 주소에서만 사용할 수 있어요."
        case .emptyModel: "사용할 모델 이름을 입력해 주세요."
        case .unsupportedConversationSnapshot: "저장된 대화 형식이 이 앱보다 새 버전입니다."
        case .unsafeConversationLocation: "보호된 대화 저장 위치가 안전하지 않아 사용을 중단했습니다."
        }
    }
}
