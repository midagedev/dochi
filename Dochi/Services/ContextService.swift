import Foundation
import os

/// 프롬프트 파일 관리 서비스
/// ~/Library/Application Support/Dochi/ 디렉토리의 md 파일들을 관리
/// - system.md: 페르소나 + 행동 지침 (수동 편집)
/// - memory.md: 사용자 기억 (레거시, fallback)
/// - family.md: 가족 공유 기억
/// - memory/{userId}.md: 개인 기억
/// - profiles.json: 사용자 프로필
@MainActor
final class ContextService: ContextServiceProtocol {
    private let fileManager: FileManager
    private let baseDir: URL

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDir = baseDirectory
        } else {
            let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dochi", isDirectory: true)
            self.baseDir = dir
        }
        do {
            try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } catch {
            Log.storage.error("기본 디렉토리 생성 실패: \(error, privacy: .public)")
        }
        do {
            try fileManager.createDirectory(at: memoryDir, withIntermediateDirectories: true)
        } catch {
            Log.storage.error("메모리 디렉토리 생성 실패: \(error, privacy: .public)")
        }
    }

    private var systemFileURL: URL {
        baseDir.appendingPathComponent("system.md")
    }

    private var memoryFileURL: URL {
        baseDir.appendingPathComponent("memory.md")
    }

    private var familyFileURL: URL {
        baseDir.appendingPathComponent("family.md")
    }

    private var profilesFileURL: URL {
        baseDir.appendingPathComponent("profiles.json")
    }

    private var memoryDir: URL {
        baseDir.appendingPathComponent("memory", isDirectory: true)
    }

    private var agentsDir: URL {
        baseDir.appendingPathComponent("agents", isDirectory: true)
    }

    private var baseSystemPromptURL: URL {
        baseDir.appendingPathComponent("system_prompt.md")
    }

    private func agentDir(name: String) -> URL {
        agentsDir.appendingPathComponent(name, isDirectory: true)
    }

    private func agentPersonaURL(name: String) -> URL {
        agentDir(name: name).appendingPathComponent("persona.md")
    }

    private func agentMemoryURL(name: String) -> URL {
        agentDir(name: name).appendingPathComponent("memory.md")
    }

    private func agentConfigURL(name: String) -> URL {
        agentDir(name: name).appendingPathComponent("config.json")
    }

    private func userMemoryFileURL(userId: UUID) -> URL {
        memoryDir.appendingPathComponent("\(userId.uuidString).md")
    }

    // MARK: - Workspace Paths

    private var workspacesDir: URL {
        baseDir.appendingPathComponent("workspaces", isDirectory: true)
    }

    private func workspaceDir(id: UUID) -> URL {
        workspacesDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func workspaceConfigURL(id: UUID) -> URL {
        workspaceDir(id: id).appendingPathComponent("config.json")
    }

    private func workspaceMemoryURL(id: UUID) -> URL {
        workspaceDir(id: id).appendingPathComponent("memory.md")
    }

    private func workspaceAgentsDir(id: UUID) -> URL {
        workspaceDir(id: id).appendingPathComponent("agents", isDirectory: true)
    }

    private func workspaceAgentDir(workspaceId: UUID, agentName: String) -> URL {
        workspaceAgentsDir(id: workspaceId).appendingPathComponent(agentName, isDirectory: true)
    }

    private func ensureWorkspaceDir(id: UUID) {
        let dir = workspaceDir(id: id)
        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                Log.storage.error("워크스페이스 디렉토리 생성 실패 \(id): \(error, privacy: .public)")
            }
        }
    }

    private func ensureWorkspaceAgentDir(workspaceId: UUID, agentName: String) {
        let dir = workspaceAgentDir(workspaceId: workspaceId, agentName: agentName)
        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                Log.storage.error("워크스페이스 에이전트 디렉토리 생성 실패 \(agentName): \(error, privacy: .public)")
            }
        }
    }

    // MARK: - System (페르소나 + 행동 지침)

    func loadSystem() -> String {
        do {
            return try String(contentsOf: systemFileURL, encoding: .utf8)
        } catch {
            Log.storage.debug("system.md 로드 실패 (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveSystem(_ content: String) {
        do {
            try content.write(to: systemFileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("system.md 저장 실패: \(error, privacy: .public)")
        }
    }

    var systemPath: String {
        systemFileURL.path
    }

    // MARK: - Memory (레거시 사용자 기억)

    func loadMemory() -> String {
        do {
            return try String(contentsOf: memoryFileURL, encoding: .utf8)
        } catch {
            Log.storage.debug("memory.md 로드 실패 (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveMemory(_ content: String) {
        do {
            try content.write(to: memoryFileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("memory.md 저장 실패: \(error, privacy: .public)")
        }
    }

    func appendMemory(_ content: String) {
        var current = loadMemory()
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveMemory(current)
    }

    var memoryPath: String {
        memoryFileURL.path
    }

    var memorySize: Int {
        do {
            let attrs = try fileManager.attributesOfItem(atPath: memoryFileURL.path)
            return attrs[.size] as? Int ?? 0
        } catch {
            Log.storage.debug("memory.md 크기 조회 실패: \(error, privacy: .public)")
            return 0
        }
    }

    // MARK: - Family Memory (가족 공유 기억)

    func loadFamilyMemory() -> String {
        do {
            return try String(contentsOf: familyFileURL, encoding: .utf8)
        } catch {
            Log.storage.debug("family.md 로드 실패 (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveFamilyMemory(_ content: String) {
        do {
            try content.write(to: familyFileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("family.md 저장 실패: \(error, privacy: .public)")
        }
    }

    func appendFamilyMemory(_ content: String) {
        var current = loadFamilyMemory()
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveFamilyMemory(current)
    }

    // MARK: - User Memory (개인 기억)

    func loadUserMemory(userId: UUID) -> String {
        do {
            return try String(contentsOf: userMemoryFileURL(userId: userId), encoding: .utf8)
        } catch {
            Log.storage.debug("사용자 메모리 로드 실패 \(userId) (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveUserMemory(userId: UUID, content: String) {
        do {
            try content.write(to: userMemoryFileURL(userId: userId), atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("사용자 메모리 저장 실패 \(userId): \(error, privacy: .public)")
        }
    }

    func appendUserMemory(userId: UUID, content: String) {
        var current = loadUserMemory(userId: userId)
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveUserMemory(userId: userId, content: current)
    }

    // MARK: - Profiles (사용자 프로필)

    func loadProfiles() -> [UserProfile] {
        let data: Data
        do {
            data = try Data(contentsOf: profilesFileURL)
        } catch {
            // 파일 없으면 프로필 미설정 상태 (정상)
            Log.storage.debug("profiles.json 없음 (미설정 상태): \(error, privacy: .public)")
            return []
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([UserProfile].self, from: data)
        } catch {
            Log.storage.error("profiles.json 로드 실패: \(error, privacy: .public)")
            return []
        }
    }

    func saveProfiles(_ profiles: [UserProfile]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: profilesFileURL)
        } catch {
            Log.storage.error("profiles.json 저장 실패: \(error, privacy: .public)")
        }
    }

    // MARK: - Base System Prompt (앱 레벨 기본 규칙)

    func loadBaseSystemPrompt() -> String {
        do {
            return try String(contentsOf: baseSystemPromptURL, encoding: .utf8)
        } catch {
            Log.storage.debug("system_prompt.md 로드 실패 (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveBaseSystemPrompt(_ content: String) {
        do {
            try content.write(to: baseSystemPromptURL, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("system_prompt.md 저장 실패: \(error, privacy: .public)")
        }
    }

    var baseSystemPromptPath: String {
        baseSystemPromptURL.path
    }

    // MARK: - Agent Persona

    func loadAgentPersona(agentName: String) -> String {
        do {
            return try String(contentsOf: agentPersonaURL(name: agentName), encoding: .utf8)
        } catch {
            Log.storage.debug("에이전트 페르소나 로드 실패 \(agentName, privacy: .public): \(error, privacy: .public)")
            return ""
        }
    }

    func saveAgentPersona(agentName: String, content: String) {
        ensureAgentDir(name: agentName)
        do {
            try content.write(to: agentPersonaURL(name: agentName), atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("에이전트 페르소나 저장 실패 \(agentName, privacy: .public): \(error, privacy: .public)")
        }
    }

    // MARK: - Agent Memory

    func loadAgentMemory(agentName: String) -> String {
        do {
            return try String(contentsOf: agentMemoryURL(name: agentName), encoding: .utf8)
        } catch {
            Log.storage.debug("에이전트 메모리 로드 실패 \(agentName, privacy: .public): \(error, privacy: .public)")
            return ""
        }
    }

    func saveAgentMemory(agentName: String, content: String) {
        ensureAgentDir(name: agentName)
        do {
            try content.write(to: agentMemoryURL(name: agentName), atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("에이전트 메모리 저장 실패 \(agentName, privacy: .public): \(error, privacy: .public)")
        }
    }

    func appendAgentMemory(agentName: String, content: String) {
        var current = loadAgentMemory(agentName: agentName)
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveAgentMemory(agentName: agentName, content: current)
    }

    // MARK: - Agent Config

    func loadAgentConfig(agentName: String) -> AgentConfig? {
        let url = agentConfigURL(name: agentName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(AgentConfig.self, from: data)
        } catch {
            Log.storage.error("에이전트 설정 로드 실패 \(agentName, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    func saveAgentConfig(_ config: AgentConfig) {
        ensureAgentDir(name: config.name)
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: agentConfigURL(name: config.name))
        } catch {
            Log.storage.error("에이전트 설정 저장 실패 \(config.name, privacy: .public): \(error, privacy: .public)")
        }
    }

    // MARK: - Agent Management

    func listAgents() -> [String] {
        guard fileManager.fileExists(atPath: agentsDir.path) else { return [] }
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: agentsDir.path)
            return contents.filter { name in
                var isDir: ObjCBool = false
                let path = agentsDir.appendingPathComponent(name).path
                return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            }.sorted()
        } catch {
            Log.storage.error("에이전트 목록 조회 실패: \(error, privacy: .public)")
            return []
        }
    }

    func createAgent(name: String, wakeWord: String, description: String) {
        ensureAgentDir(name: name)

        let config = AgentConfig(name: name, wakeWord: wakeWord, description: description)
        saveAgentConfig(config)

        // 기본 페르소나 생성 (없는 경우)
        if loadAgentPersona(agentName: name).isEmpty {
            saveAgentPersona(agentName: name, content: Constants.Agent.defaultPersona)
        }

        Log.storage.info("에이전트 생성: \(name, privacy: .public)")
    }

    // MARK: - Workspace Management

    func listWorkspaces() -> [Workspace] {
        guard fileManager.fileExists(atPath: workspacesDir.path) else { return [] }
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: workspacesDir.path)
            var workspaces: [Workspace] = []
            for idString in contents {
                guard let id = UUID(uuidString: idString) else { continue }
                if let config = loadWorkspaceConfig(id: id) {
                    workspaces.append(config)
                }
            }
            return workspaces.sorted { $0.createdAt < $1.createdAt }
        } catch {
            Log.storage.error("워크스페이스 목록 조회 실패: \(error, privacy: .public)")
            return []
        }
    }

    func loadWorkspaceConfig(id: UUID) -> Workspace? {
        let url = workspaceConfigURL(id: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Workspace.self, from: data)
        } catch {
            Log.storage.error("워크스페이스 설정 로드 실패 \(id): \(error, privacy: .public)")
            return nil
        }
    }

    func saveWorkspaceConfig(_ workspace: Workspace) {
        ensureWorkspaceDir(id: workspace.id)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(workspace)
            try data.write(to: workspaceConfigURL(id: workspace.id))
        } catch {
            Log.storage.error("워크스페이스 설정 저장 실패 \(workspace.id): \(error, privacy: .public)")
        }
    }

    // MARK: - Workspace Memory

    func loadWorkspaceMemory(workspaceId: UUID) -> String {
        do {
            return try String(contentsOf: workspaceMemoryURL(id: workspaceId), encoding: .utf8)
        } catch {
            // 파일이 없으면 빈 문자열 반환 (정상)
            return ""
        }
    }

    func saveWorkspaceMemory(workspaceId: UUID, content: String) {
        ensureWorkspaceDir(id: workspaceId)
        do {
            try content.write(to: workspaceMemoryURL(id: workspaceId), atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("워크스페이스 메모리 저장 실패 \(workspaceId): \(error, privacy: .public)")
        }
    }

    func appendWorkspaceMemory(workspaceId: UUID, content: String) {
        var current = loadWorkspaceMemory(workspaceId: workspaceId)
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveWorkspaceMemory(workspaceId: workspaceId, content: current)
    }

    // MARK: - Agent Persona (Workspace-aware)

    func loadAgentPersona(workspaceId: UUID, agentName: String) -> String {
        let url = workspaceAgentDir(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("persona.md")
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return ""
        }
    }

    func saveAgentPersona(workspaceId: UUID, agentName: String, content: String) {
        ensureWorkspaceAgentDir(workspaceId: workspaceId, agentName: agentName)
        let url = workspaceAgentDir(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("persona.md")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("에이전트 페르소나 저장 실패 \(agentName): \(error, privacy: .public)")
        }
    }

    // MARK: - Agent Memory (Workspace-aware)

    func loadAgentMemory(workspaceId: UUID, agentName: String) -> String {
        let url = workspaceAgentDir(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("memory.md")
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return ""
        }
    }

    func saveAgentMemory(workspaceId: UUID, agentName: String, content: String) {
        ensureWorkspaceAgentDir(workspaceId: workspaceId, agentName: agentName)
        let url = workspaceAgentDir(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("memory.md")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("에이전트 메모리 저장 실패 \(agentName): \(error, privacy: .public)")
        }
    }

    func appendAgentMemory(workspaceId: UUID, agentName: String, content: String) {
        var current = loadAgentMemory(workspaceId: workspaceId, agentName: agentName)
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveAgentMemory(workspaceId: workspaceId, agentName: agentName, content: current)
    }

    // MARK: - Agent Config (Workspace-aware)

    func loadAgentConfig(workspaceId: UUID, agentName: String) -> AgentConfig? {
        let url = workspaceAgentDir(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(AgentConfig.self, from: data)
        } catch {
            return nil
        }
    }

    func saveAgentConfig(workspaceId: UUID, config: AgentConfig) {
        ensureWorkspaceAgentDir(workspaceId: workspaceId, agentName: config.name)
        let url = workspaceAgentDir(workspaceId: workspaceId, agentName: config.name).appendingPathComponent("config.json")
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: url)
        } catch {
            Log.storage.error("에이전트 설정 저장 실패 \(config.name): \(error, privacy: .public)")
        }
    }

    // MARK: - Agent Management (Workspace-aware)

    func listAgents(workspaceId: UUID) -> [String] {
        let dir = workspaceAgentsDir(id: workspaceId)
        guard fileManager.fileExists(atPath: dir.path) else { return [] }
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: dir.path)
            return contents.filter { name in
                var isDir: ObjCBool = false
                let path = dir.appendingPathComponent(name).path
                return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            }.sorted()
        } catch {
            return []
        }
    }

    func createAgent(workspaceId: UUID, name: String, wakeWord: String, description: String) {
        ensureWorkspaceAgentDir(workspaceId: workspaceId, agentName: name)
        let config = AgentConfig(name: name, wakeWord: wakeWord, description: description)
        saveAgentConfig(workspaceId: workspaceId, config: config)
        
        if loadAgentPersona(workspaceId: workspaceId, agentName: name).isEmpty {
            saveAgentPersona(workspaceId: workspaceId, agentName: name, content: Constants.Agent.defaultPersona)
        }
    }

    // MARK: - Migration to Workspace

    func migrateToWorkspaceStructure() {
        // 기본 워크스페이스 ID 생성 (항상 동일한 UUID 사용하거나 저장된 것 사용)
        // 여기서는 마이그레이션을 위해 고정된 UUID를 사용하거나, 기존에 생성된게 없으면 생성
        
        // 워크스페이스 디렉토리가 이미 존재하면 마이그레이션 완료된 것으로 간주 (혹은 체크)
        if fileManager.fileExists(atPath: workspacesDir.path) {
            return
        }

        Log.storage.info("워크스페이스 구조로 마이그레이션 시작")
        
        // 1. 기본 워크스페이스 생성
        let defaultWorkspaceId = UUID()
        let defaultWorkspace = Workspace(
            id: defaultWorkspaceId,
            name: "기본 워크스페이스",
            ownerId: UUID(), // 임시 owner ID (실제로는 로그인된 사용자여야 함)
            createdAt: Date()
        )
        saveWorkspaceConfig(defaultWorkspace)
        
        // 2. 기존 agents 디렉토리 이동
        if fileManager.fileExists(atPath: agentsDir.path) {
            let targetDir = workspaceAgentsDir(id: defaultWorkspaceId)
            do {
                // agentsDir의 상위 디렉토리(workspaceDir)가 이미 saveWorkspaceConfig로 생성됨
                // agentsDir 자체는 아직 없을 수 있음 (saveWorkspaceConfig는 config file만 씀? 아니 ensure함)
                // 하지만 moveItem을 위해선 targetDir가 없어야 하거나, 내용물을 옮겨야 함
                // 여기선 agents/ 폴더 자체를 workspaces/{id}/agents/ 로 이동
                try fileManager.moveItem(at: agentsDir, to: targetDir)
                Log.storage.info("기존 agents 디렉토리 이동 완료")
            } catch {
                Log.storage.error("agents 디렉토리 이동 실패: \(error, privacy: .public)")
            }
        }
        
        // 3. 기존 memory 파일들을 workspace memory로 이동
        // family.md 우선, 없으면 memory.md 사용
        let legacyMemory: String
        if fileManager.fileExists(atPath: familyFileURL.path) {
            legacyMemory = (try? String(contentsOf: familyFileURL, encoding: .utf8)) ?? ""
            try? fileManager.removeItem(at: familyFileURL)
        } else if fileManager.fileExists(atPath: memoryFileURL.path) {
            legacyMemory = (try? String(contentsOf: memoryFileURL, encoding: .utf8)) ?? ""
            try? fileManager.removeItem(at: memoryFileURL)
        } else {
            legacyMemory = ""
        }
        
        if !legacyMemory.isEmpty {
            saveWorkspaceMemory(workspaceId: defaultWorkspaceId, content: legacyMemory)
            Log.storage.info("레거시 메모리를 워크스페이스 메모리로 이동 완료")
        }
        
        // 4. system.md가 있으면 기본 에이전트의 persona로 마이그레이션
        if fileManager.fileExists(atPath: systemFileURL.path) {
            let systemContent = (try? String(contentsOf: systemFileURL, encoding: .utf8)) ?? ""
            if !systemContent.isEmpty {
                let defaultAgentName = Constants.Agent.defaultName
                saveAgentPersona(workspaceId: defaultWorkspaceId, agentName: defaultAgentName, content: systemContent)
                Log.storage.info("system.md를 에이전트 페르소나로 이동 완료")
            }
        }
        
        Log.storage.info("워크스페이스 마이그레이션 파일 작업 완료. ID: \(defaultWorkspaceId)")
    }

    private func ensureAgentDir(name: String) {
        // Deprecated helper (kept for legacy methods)
        let dir = agentDir(name: name)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Legacy (마이그레이션용)

    /// 기존 context.md → memory.md 마이그레이션
    func migrateIfNeeded() {
        let oldContextURL = baseDir.appendingPathComponent("context.md")

        // 기존 context.md가 있고 memory.md가 없으면 이동
        if fileManager.fileExists(atPath: oldContextURL.path) && !fileManager.fileExists(atPath: memoryFileURL.path) {
            do {
                try fileManager.moveItem(at: oldContextURL, to: memoryFileURL)
                Log.storage.info("context.md → memory.md 마이그레이션 완료")
            } catch {
                Log.storage.error("context.md → memory.md 마이그레이션 실패: \(error, privacy: .public)")
            }
        }
    }

    /// system.md → agents/도치 구조로 마이그레이션
    func migrateToAgentStructure(currentWakeWord: String) {
        // 자동 마이그레이션 제거됨 (수동 마이그레이션 권장)
        Log.storage.info("자동 마이그레이션이 비활성화되었습니다. 수동으로 파일을 이동해주세요.")
    }
}
