import XCTest
@testable import Dochi

final class AgentDefinitionTests: XCTestCase {

    // MARK: - Model Codable Tests

    func testAgentDefinitionEncodeDecode() throws {
        let definition = AgentDefinition(
            id: "assistant-1",
            name: "도치",
            wakeWord: "도치야",
            description: "가정 비서",
            defaultModel: "claude-sonnet-4-6",
            permissionProfile: .default,
            toolGroups: ["calendar", "reminders", "memory"],
            subagents: [
                SubagentDefinition(id: "planner", name: "플래너", toolGroups: ["calendar"])
            ],
            memoryPolicy: .default,
            version: 3,
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(definition)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentDefinition.self, from: data)

        XCTAssertEqual(decoded.id, "assistant-1")
        XCTAssertEqual(decoded.name, "도치")
        XCTAssertEqual(decoded.wakeWord, "도치야")
        XCTAssertEqual(decoded.description, "가정 비서")
        XCTAssertEqual(decoded.defaultModel, "claude-sonnet-4-6")
        XCTAssertEqual(decoded.toolGroups, ["calendar", "reminders", "memory"])
        XCTAssertEqual(decoded.subagents.count, 1)
        XCTAssertEqual(decoded.subagents.first?.id, "planner")
        XCTAssertEqual(decoded.memoryPolicy, .default)
        XCTAssertEqual(decoded.version, 3)
    }

    func testAgentDefinitionBackwardCompatibility() throws {
        // 기존 AgentConfig JSON 형식 → AgentDefinition 디코딩
        let legacyJSON = """
        {
            "name": "도치",
            "wakeWord": "도치야",
            "description": "가정 비서",
            "defaultModel": "gpt-4o",
            "permissions": ["safe", "sensitive"],
            "preferredToolGroups": ["calendar", "reminders"]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let definition = try decoder.decode(AgentDefinition.self, from: legacyJSON)

        XCTAssertEqual(definition.name, "도치")
        XCTAssertEqual(definition.id, "도치") // name에서 생성
        XCTAssertEqual(definition.wakeWord, "도치야")
        XCTAssertEqual(definition.toolGroups, ["calendar", "reminders"]) // preferredToolGroups에서 변환
        XCTAssertEqual(definition.permissions, ["safe", "sensitive"])
        XCTAssertEqual(definition.version, 1) // 기본값
        XCTAssertTrue(definition.subagents.isEmpty) // 기본값
    }

    func testAgentDefinitionMinimalJSON() throws {
        let minimalJSON = """
        { "name": "테스트" }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let definition = try decoder.decode(AgentDefinition.self, from: minimalJSON)

        XCTAssertEqual(definition.name, "테스트")
        XCTAssertEqual(definition.id, "테스트")
        XCTAssertEqual(definition.version, 1)
        XCTAssertTrue(definition.toolGroups.isEmpty)
        XCTAssertTrue(definition.subagents.isEmpty)
        XCTAssertNil(definition.permissionProfile)
        XCTAssertNil(definition.memoryPolicy)
    }

    func testPermissionProfileEncodeDecode() throws {
        let profile = PermissionProfile(safe: .allow, sensitive: .confirm, restricted: .deny)
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(PermissionProfile.self, from: data)

        XCTAssertEqual(decoded.safe, .allow)
        XCTAssertEqual(decoded.sensitive, .confirm)
        XCTAssertEqual(decoded.restricted, .deny)
    }

    func testSubagentDefinitionEncodeDecode() throws {
        let subagent = SubagentDefinition(
            id: "reviewer",
            name: "리뷰어",
            description: "코드 리뷰 전용",
            toolGroups: ["code"],
            permissionProfile: .minimal
        )

        let data = try JSONEncoder().encode(subagent)
        let decoded = try JSONDecoder().decode(SubagentDefinition.self, from: data)

        XCTAssertEqual(decoded.id, "reviewer")
        XCTAssertEqual(decoded.name, "리뷰어")
        XCTAssertEqual(decoded.toolGroups, ["code"])
        XCTAssertEqual(decoded.permissionProfile?.safe, .allow)
        XCTAssertEqual(decoded.permissionProfile?.restricted, .deny)
    }

    func testMemoryPolicyEncodeDecode() throws {
        let policy = MemoryPolicy(
            personalMemoryAccess: false,
            workspaceMemoryAccess: true,
            agentMemoryAccess: true,
            autoExtractEnabled: false
        )

        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(MemoryPolicy.self, from: data)

        XCTAssertFalse(decoded.personalMemoryAccess)
        XCTAssertTrue(decoded.workspaceMemoryAccess)
        XCTAssertFalse(decoded.autoExtractEnabled)
    }

    func testMemoryPolicyDefaults() {
        XCTAssertTrue(MemoryPolicy.default.personalMemoryAccess)
        XCTAssertTrue(MemoryPolicy.default.autoExtractEnabled)
        XCTAssertFalse(MemoryPolicy.subagentDefault.personalMemoryAccess)
        XCTAssertFalse(MemoryPolicy.subagentDefault.autoExtractEnabled)
    }

    // MARK: - Conversion Tests

    func testToAgentConfig() {
        let definition = AgentDefinition(
            name: "도치",
            wakeWord: "도치야",
            description: "가정 비서",
            defaultModel: "gpt-4o",
            toolGroups: ["calendar", "memory"],
            permissions: ["safe"]
        )

        let config = definition.toAgentConfig()
        XCTAssertEqual(config.name, "도치")
        XCTAssertEqual(config.wakeWord, "도치야")
        XCTAssertEqual(config.description, "가정 비서")
        XCTAssertEqual(config.defaultModel, "gpt-4o")
        XCTAssertEqual(config.preferredToolGroups, ["calendar", "memory"])
        XCTAssertEqual(config.permissions, ["safe"])
    }

    func testFromAgentConfig() {
        let config = AgentConfig(
            name: "보조",
            wakeWord: "보조야",
            description: "보조 에이전트",
            permissions: ["safe", "sensitive"],
            preferredToolGroups: ["calendar"]
        )

        let definition = AgentDefinition.from(config: config)
        XCTAssertEqual(definition.name, "보조")
        XCTAssertEqual(definition.id, "보조")
        XCTAssertEqual(definition.wakeWord, "보조야")
        XCTAssertEqual(definition.toolGroups, ["calendar"])
        XCTAssertEqual(definition.permissions, ["safe", "sensitive"])
        XCTAssertEqual(definition.version, 1)
    }

    func testEffectivePermissionProfile() {
        // v2 profile이 있으면 그것을 사용
        let withProfile = AgentDefinition(
            name: "test",
            permissionProfile: .minimal
        )
        XCTAssertEqual(withProfile.effectivePermissionProfile.restricted, .deny)

        // v2 profile이 없으면 레거시 permissions에서 변환
        let withLegacy = AgentDefinition(
            name: "test",
            permissions: ["safe"]
        )
        XCTAssertEqual(withLegacy.effectivePermissionProfile.safe, .allow)
        XCTAssertEqual(withLegacy.effectivePermissionProfile.sensitive, .deny)
        XCTAssertEqual(withLegacy.effectivePermissionProfile.restricted, .deny)
    }

    func testEffectiveToolGroups() {
        let definition = AgentDefinition(
            name: "test",
            toolGroups: ["Calendar", " memory ", "CALENDAR", ""]
        )
        let effective = definition.effectiveToolGroups
        XCTAssertEqual(effective, ["calendar", "memory"]) // 정규화 + 중복 제거
    }

    func testIncrementedVersion() {
        let definition = AgentDefinition(name: "test", version: 2)
        let incremented = definition.incrementedVersion()
        XCTAssertEqual(incremented.version, 3)
        XCTAssertGreaterThanOrEqual(incremented.updatedAt, definition.updatedAt)
    }

    // MARK: - AgentDefinitionValidator Tests

    @MainActor
    func testValidatorAcceptsValidDefinition() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(
            name: "도치",
            wakeWord: "도치야",
            toolGroups: ["calendar"],
            version: 1
        )
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.isEmpty, "Errors: \(errors)")
    }

    @MainActor
    func testValidatorRejectsEmptyName() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(id: "test", name: "")
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.emptyName))
    }

    @MainActor
    func testValidatorRejectsEmptyId() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(id: "", name: "test")
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.emptyId))
    }

    @MainActor
    func testValidatorRejectsInvalidNameFormat() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(name: "agent@#$!")
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(where: {
            if case .invalidNameFormat = $0 { return true }
            return false
        }))
    }

    @MainActor
    func testValidatorAcceptsKoreanName() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(name: "도치 비서-1")
        let errors = validator.validate(definition)
        XCTAssertFalse(errors.contains(where: {
            if case .invalidNameFormat = $0 { return true }
            return false
        }))
    }

    @MainActor
    func testValidatorWarnsRestrictedAllowed() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(
            name: "test",
            permissionProfile: PermissionProfile(safe: .allow, sensitive: .allow, restricted: .allow)
        )
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.restrictedToolsAllowed))
    }

    @MainActor
    func testValidatorWarnsSafeDenied() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(
            name: "test",
            permissionProfile: PermissionProfile(safe: .deny, sensitive: .deny, restricted: .deny)
        )
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.safeToolsDenied))
    }

    @MainActor
    func testValidatorChecksUnknownToolGroups() {
        let validator = AgentDefinitionValidator(knownToolGroups: ["calendar", "memory", "reminders"])
        let definition = AgentDefinition(
            name: "test",
            toolGroups: ["calendar", "nonexistent"]
        )
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.unknownToolGroup("nonexistent")))
    }

    @MainActor
    func testValidatorAcceptsKnownToolGroups() {
        let validator = AgentDefinitionValidator(knownToolGroups: ["calendar", "memory"])
        let definition = AgentDefinition(
            name: "test",
            toolGroups: ["calendar", "memory"]
        )
        let errors = validator.validate(definition)
        XCTAssertFalse(errors.contains(where: {
            if case .unknownToolGroup = $0 { return true }
            return false
        }))
    }

    @MainActor
    func testValidatorChecksSubagentEmptyId() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(
            name: "test",
            subagents: [SubagentDefinition(id: "")]
        )
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.subagentEmptyId))
    }

    @MainActor
    func testValidatorChecksInvalidVersion() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(name: "test", version: 0)
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.invalidVersion(0)))
    }

    @MainActor
    func testValidatorChecksEmptyWakeWord() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(name: "test", wakeWord: "  ")
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.emptyWakeWord))
    }

    @MainActor
    func testValidatorChecksNoMemoryAccess() {
        let validator = AgentDefinitionValidator()
        let definition = AgentDefinition(
            name: "test",
            memoryPolicy: MemoryPolicy(
                personalMemoryAccess: false,
                workspaceMemoryAccess: false,
                agentMemoryAccess: false
            )
        )
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.noMemoryAccess))
    }

    @MainActor
    func testValidatorChecksSubagentUnknownToolGroups() {
        let validator = AgentDefinitionValidator(knownToolGroups: ["calendar", "memory", "reminders"])
        let definition = AgentDefinition(
            name: "test",
            subagents: [
                SubagentDefinition(id: "planner", toolGroups: ["calendar", "nonexistent"]),
                SubagentDefinition(id: "reviewer", toolGroups: ["unknown_group"])
            ]
        )
        let errors = validator.validate(definition)
        XCTAssertTrue(errors.contains(.subagentUnknownToolGroup(subagentId: "planner", group: "nonexistent")))
        XCTAssertTrue(errors.contains(.subagentUnknownToolGroup(subagentId: "reviewer", group: "unknown_group")))
    }

    @MainActor
    func testValidatorAcceptsSubagentKnownToolGroups() {
        let validator = AgentDefinitionValidator(knownToolGroups: ["calendar", "memory", "reminders"])
        let definition = AgentDefinition(
            name: "test",
            subagents: [
                SubagentDefinition(id: "planner", toolGroups: ["calendar", "memory"])
            ]
        )
        let errors = validator.validate(definition)
        XCTAssertFalse(errors.contains(where: {
            if case .subagentUnknownToolGroup = $0 { return true }
            return false
        }))
    }

    @MainActor
    func testValidatorSkipsSubagentToolGroupsWhenNoKnownGroups() {
        let validator = AgentDefinitionValidator() // knownToolGroups = [] (기본값)
        let definition = AgentDefinition(
            name: "test",
            subagents: [
                SubagentDefinition(id: "planner", toolGroups: ["anything"])
            ]
        )
        let errors = validator.validate(definition)
        XCTAssertFalse(errors.contains(where: {
            if case .subagentUnknownToolGroup = $0 { return true }
            return false
        }))
    }

    @MainActor
    func testIsValidConvenience() {
        let validator = AgentDefinitionValidator()
        let valid = AgentDefinition(name: "도치")
        XCTAssertTrue(validator.isValid(valid))

        let invalid = AgentDefinition(id: "", name: "")
        XCTAssertFalse(validator.isValid(invalid))
    }

    // MARK: - AgentDefinitionLoader Tests

    @MainActor
    func testLoaderLoadDefinitionFromV2Data() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "도치", wakeWord: "도치야", description: "가정 비서")

        // v2 데이터 저장
        let v2 = AgentDefinition(
            id: "agent-v2",
            name: "도치",
            wakeWord: "도치야",
            description: "가정 비서 v2",
            toolGroups: ["calendar", "memory"],
            version: 2,
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(v2)
        ctx.saveAgentConfigData(workspaceId: wsId, agentName: "도치", data: data)

        let loader = AgentDefinitionLoader(contextService: ctx)
        let loaded = loader.loadDefinition(workspaceId: wsId, agentName: "도치")

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "agent-v2")
        XCTAssertEqual(loaded?.version, 2)
        XCTAssertEqual(loaded?.toolGroups, ["calendar", "memory"])
    }

    @MainActor
    func testLoaderFallbackToLegacyConfig() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "보조", wakeWord: "보조야", description: "보조 에이전트")

        let loader = AgentDefinitionLoader(contextService: ctx)
        let loaded = loader.loadDefinition(workspaceId: wsId, agentName: "보조")

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "보조")
        XCTAssertEqual(loaded?.id, "보조") // name에서 자동 생성
        XCTAssertEqual(loaded?.version, 1)
    }

    @MainActor
    func testLoaderLoadFull() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "도치", wakeWord: "도치야", description: nil)
        ctx.saveAgentPersona(workspaceId: wsId, agentName: "도치", content: "You are a helpful assistant.")
        ctx.saveAgentMemory(workspaceId: wsId, agentName: "도치", content: "- 사용자가 커피를 좋아함")

        let loader = AgentDefinitionLoader(contextService: ctx)
        let loaded = loader.load(workspaceId: wsId, agentName: "도치")

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.definition.name, "도치")
        XCTAssertEqual(loaded?.systemPrompt, "You are a helpful assistant.")
        XCTAssertEqual(loaded?.memory, "- 사용자가 커피를 좋아함")
        XCTAssertEqual(loaded?.workspaceId, wsId)
    }

    @MainActor
    func testLoaderLoadAll() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "도치", wakeWord: "도치야", description: nil)
        ctx.createAgent(workspaceId: wsId, name: "번역기", wakeWord: "번역해줘", description: nil)

        let loader = AgentDefinitionLoader(contextService: ctx)
        let all = loader.loadAll(workspaceId: wsId)

        XCTAssertEqual(all.count, 2)
    }

    @MainActor
    func testLoaderLoadNonexistent() {
        let ctx = MockContextService()
        let loader = AgentDefinitionLoader(contextService: ctx)
        let loaded = loader.load(workspaceId: UUID(), agentName: "없는에이전트")
        XCTAssertNil(loaded)
    }

    @MainActor
    func testLoaderSaveAndReload() throws {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createLocalWorkspace(id: wsId)
        ctx.agents[wsId] = ["도치"]

        let definition = AgentDefinition(
            id: "dochi-1",
            name: "도치",
            wakeWord: "도치야",
            toolGroups: ["calendar"],
            version: 2,
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let loader = AgentDefinitionLoader(contextService: ctx)
        try loader.save(workspaceId: wsId, definition: definition)

        // Reload
        let reloaded = loader.loadDefinition(workspaceId: wsId, agentName: "도치")
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.id, "dochi-1")
        XCTAssertEqual(reloaded?.version, 2)
        XCTAssertEqual(reloaded?.toolGroups, ["calendar"])

        // Legacy config도 동기화 확인
        let legacyConfig = ctx.loadAgentConfig(workspaceId: wsId, agentName: "도치")
        XCTAssertNotNil(legacyConfig)
        XCTAssertEqual(legacyConfig?.name, "도치")
    }

    // MARK: - WakeWordRouter Tests

    @MainActor
    func testWakeWordRoutingPrefixMatch() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "도치", wakeWord: "도치야", description: nil)

        let router = WakeWordRouter(contextService: ctx)
        let decision = router.route(
            input: "도치야 오늘 일정 알려줘",
            availableWorkspaces: [wsId],
            currentWorkspaceId: wsId,
            currentAgentName: "기본"
        )

        XCTAssertEqual(decision.agentName, "도치")
        XCTAssertEqual(decision.matchedWakeWord, "도치야")
        XCTAssertEqual(decision.reason, .wakeWordPrefix)
        XCTAssertGreaterThan(decision.confidence, 0.9)
    }

    @MainActor
    func testWakeWordRoutingContainsMatch() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "도치", wakeWord: "도치야", description: nil)

        let router = WakeWordRouter(contextService: ctx)
        let decision = router.route(
            input: "오늘 도치야 일정 알려줘",
            availableWorkspaces: [wsId],
            currentWorkspaceId: wsId,
            currentAgentName: "기본"
        )

        XCTAssertEqual(decision.agentName, "도치")
        XCTAssertEqual(decision.matchedWakeWord, "도치야")
        XCTAssertEqual(decision.reason, .wakeWordContains)
        XCTAssertLessThan(decision.confidence, 0.9)
    }

    @MainActor
    func testWakeWordRoutingNoMatch() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "도치", wakeWord: "도치야", description: nil)

        let router = WakeWordRouter(contextService: ctx)
        let decision = router.route(
            input: "오늘 날씨 어때",
            availableWorkspaces: [wsId],
            currentWorkspaceId: wsId,
            currentAgentName: "기본"
        )

        XCTAssertEqual(decision.agentName, "기본")
        XCTAssertNil(decision.matchedWakeWord)
        XCTAssertEqual(decision.reason, .currentDefault)
    }

    @MainActor
    func testWakeWordRoutingEmptyInput() {
        let ctx = MockContextService()
        let wsId = UUID()

        let router = WakeWordRouter(contextService: ctx)
        let decision = router.route(
            input: "",
            availableWorkspaces: [wsId],
            currentWorkspaceId: wsId,
            currentAgentName: "기본"
        )

        XCTAssertEqual(decision.agentName, "기본")
        XCTAssertEqual(decision.reason, .currentDefault)
    }

    @MainActor
    func testWakeWordRoutingLongestMatch() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "도치", wakeWord: "도치", description: nil)
        ctx.createAgent(workspaceId: wsId, name: "도치비서", wakeWord: "도치비서야", description: nil)

        let router = WakeWordRouter(contextService: ctx)
        let decision = router.route(
            input: "도치비서야 오늘 일정",
            availableWorkspaces: [wsId],
            currentWorkspaceId: wsId,
            currentAgentName: "기본"
        )

        // 더 긴 wakeWord가 우선
        XCTAssertEqual(decision.agentName, "도치비서")
    }

    @MainActor
    func testWakeWordRoutingCaseInsensitive() {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.createAgent(workspaceId: wsId, name: "CodeBot", wakeWord: "CodeBot", description: nil)

        let router = WakeWordRouter(contextService: ctx)
        let decision = router.route(
            input: "codebot help me",
            availableWorkspaces: [wsId],
            currentWorkspaceId: wsId,
            currentAgentName: "기본"
        )

        XCTAssertEqual(decision.agentName, "CodeBot")
    }

    @MainActor
    func testWakeWordRoutingCrossWorkspace() {
        let ctx = MockContextService()
        let ws1 = UUID()
        let ws2 = UUID()
        ctx.createAgent(workspaceId: ws1, name: "도치", wakeWord: "도치야", description: nil)
        ctx.createAgent(workspaceId: ws2, name: "번역기", wakeWord: "번역해줘", description: nil)

        let router = WakeWordRouter(contextService: ctx)
        let decision = router.route(
            input: "번역해줘 이 문장",
            availableWorkspaces: [ws1, ws2],
            currentWorkspaceId: ws1,
            currentAgentName: "도치"
        )

        XCTAssertEqual(decision.agentName, "번역기")
        XCTAssertEqual(decision.workspaceId, ws2)
    }

    @MainActor
    func testQuickMatchWithPreloadedAgents() {
        let ctx = MockContextService()
        let wsId = UUID()
        let router = WakeWordRouter(contextService: ctx)

        let agents: [(workspaceId: UUID, definition: AgentDefinition)] = [
            (wsId, AgentDefinition(name: "도치", wakeWord: "도치야")),
            (wsId, AgentDefinition(name: "번역기", wakeWord: "번역해줘")),
        ]

        let decision = router.quickMatch(input: "도치야 안녕", agents: agents)
        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.agentName, "도치")

        let noMatch = router.quickMatch(input: "안녕하세요", agents: agents)
        XCTAssertNil(noMatch)
    }

    // MARK: - Version Tests

    @MainActor
    func testVersionChangeAppliesOnNewSession() throws {
        let ctx = MockContextService()
        let wsId = UUID()
        ctx.agents[wsId] = ["도치"]

        let loader = AgentDefinitionLoader(contextService: ctx)

        // Save v1
        let v1 = AgentDefinition(
            id: "dochi",
            name: "도치",
            toolGroups: ["calendar"],
            version: 1,
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )
        try loader.save(workspaceId: wsId, definition: v1)

        // Simulate "session starts" - load v1
        let sessionSnapshot = loader.loadDefinition(workspaceId: wsId, agentName: "도치")
        XCTAssertEqual(sessionSnapshot?.version, 1)
        XCTAssertEqual(sessionSnapshot?.toolGroups, ["calendar"])

        // Agent is updated to v2 while session is running
        let v2 = v1.incrementedVersion()
        var updated = v2
        updated.toolGroups = ["calendar", "memory"]
        try loader.save(workspaceId: wsId, definition: updated)

        // Session snapshot stays at v1 (session pins version at start)
        XCTAssertEqual(sessionSnapshot?.version, 1)
        XCTAssertEqual(sessionSnapshot?.toolGroups, ["calendar"])

        // New session loads v2
        let newSession = loader.loadDefinition(workspaceId: wsId, agentName: "도치")
        XCTAssertEqual(newSession?.version, 2)
        XCTAssertEqual(newSession?.toolGroups, ["calendar", "memory"])
    }

    // MARK: - RoutingDecision Tests

    func testRoutingDecisionIsWakeWordMatch() {
        let wsId = UUID()
        let withMatch = RoutingDecision(
            workspaceId: wsId,
            agentName: "도치",
            matchedWakeWord: "도치야",
            reason: .wakeWordPrefix
        )
        XCTAssertTrue(withMatch.isWakeWordMatch)

        let noMatch = RoutingDecision(
            workspaceId: wsId,
            agentName: "기본",
            reason: .currentDefault
        )
        XCTAssertFalse(noMatch.isWakeWordMatch)
    }

    func testRoutingReasonRawValues() {
        XCTAssertEqual(RoutingReason.wakeWordPrefix.rawValue, "wakeWordPrefix")
        XCTAssertEqual(RoutingReason.wakeWordContains.rawValue, "wakeWordContains")
        XCTAssertEqual(RoutingReason.currentDefault.rawValue, "currentDefault")
        XCTAssertEqual(RoutingReason.explicit.rawValue, "explicit")
    }

    // MARK: - LoadedAgentDefinition Tests

    func testLoadedAgentDefinitionFields() {
        let wsId = UUID()
        let definition = AgentDefinition(name: "도치")
        let loaded = LoadedAgentDefinition(
            definition: definition,
            systemPrompt: "You are helpful.",
            memory: "- fact1",
            workspaceId: wsId
        )

        XCTAssertEqual(loaded.definition.name, "도치")
        XCTAssertEqual(loaded.systemPrompt, "You are helpful.")
        XCTAssertEqual(loaded.memory, "- fact1")
        XCTAssertEqual(loaded.workspaceId, wsId)
    }
}
