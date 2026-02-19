import Foundation
import os

// MARK: - Protocol

@MainActor
protocol ExternalToolSessionManagerProtocol: AnyObject, Sendable {
    var profiles: [ExternalToolProfile] { get }
    var sessions: [ExternalToolSession] { get }
    var isTmuxAvailable: Bool { get }
    var managedRepositories: [ManagedGitRepository] { get }

    // Profile CRUD
    func loadProfiles()
    func saveProfile(_ profile: ExternalToolProfile)
    func deleteProfile(id: UUID)

    // Session lifecycle
    func startSession(profileId: UUID) async throws
    func stopSession(id: UUID) async
    func restartSession(id: UUID) async throws

    // Work dispatch
    func sendCommand(sessionId: UUID, command: String) async throws

    // Health check
    func checkHealth(sessionId: UUID) async
    func checkAllHealth() async

    // Output
    func captureOutput(sessionId: UUID, lines: Int) async -> [String]

    // Repository insights
    func discoverGitRepositoryInsights(searchPaths: [String]?, limit: Int) async -> [GitRepositoryInsight]

    // Repository registry lifecycle
    func initializeRepository(
        path: String,
        defaultBranch: String,
        createReadme: Bool,
        createGitignore: Bool
    ) async throws -> ManagedGitRepository
    func cloneRepository(
        remoteURL: String,
        destinationPath: String,
        branch: String?
    ) async throws -> ManagedGitRepository
    func attachRepository(path: String) async throws -> ManagedGitRepository
    func removeManagedRepository(id: UUID, deleteDirectory: Bool) async throws

    // Local discovery (file-backed sessions from CLI tools)
    func discoverLocalCodingSessions(limit: Int) async -> [DiscoveredCodingSession]
}

extension ExternalToolSessionManagerProtocol {
    func initializeRepository(
        path _: String,
        defaultBranch _: String,
        createReadme _: Bool,
        createGitignore _: Bool
    ) async throws -> ManagedGitRepository {
        throw ExternalToolError.repositoryOperationFailed("저장소 초기화를 지원하지 않습니다.")
    }

    func cloneRepository(
        remoteURL _: String,
        destinationPath _: String,
        branch _: String?
    ) async throws -> ManagedGitRepository {
        throw ExternalToolError.repositoryOperationFailed("저장소 복제를 지원하지 않습니다.")
    }

    func attachRepository(path _: String) async throws -> ManagedGitRepository {
        throw ExternalToolError.repositoryOperationFailed("저장소 연결을 지원하지 않습니다.")
    }

    func removeManagedRepository(id _: UUID, deleteDirectory _: Bool) async throws {
        throw ExternalToolError.repositoryOperationFailed("저장소 제거를 지원하지 않습니다.")
    }

    func discoverLocalCodingSessions(limit _: Int) async -> [DiscoveredCodingSession] {
        []
    }
}

// MARK: - Errors

enum ExternalToolError: LocalizedError {
    case tmuxNotAvailable
    case profileNotFound(UUID)
    case sessionNotFound(UUID)
    case sessionAlreadyRunning(UUID)
    case sessionStartFailed(String)
    case invalidRepositoryPath(String)
    case repositoryNotFound(UUID)
    case repositoryOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .tmuxNotAvailable:
            return "tmux가 설치되어 있지 않습니다."
        case .profileNotFound(let id):
            return "프로파일을 찾을 수 없습니다: \(id)"
        case .sessionNotFound(let id):
            return "세션을 찾을 수 없습니다: \(id)"
        case .sessionAlreadyRunning(let id):
            return "세션이 이미 실행 중입니다: \(id)"
        case .sessionStartFailed(let reason):
            return "세션 시작 실패: \(reason)"
        case .invalidRepositoryPath(let path):
            return "유효한 저장소 경로가 아닙니다: \(path)"
        case .repositoryNotFound(let id):
            return "저장소를 찾을 수 없습니다: \(id)"
        case .repositoryOperationFailed(let reason):
            return "저장소 작업 실패: \(reason)"
        }
    }
}

// MARK: - Implementation

@MainActor
@Observable
final class ExternalToolSessionManager: ExternalToolSessionManagerProtocol {
    private(set) var profiles: [ExternalToolProfile] = []
    private(set) var sessions: [ExternalToolSession] = []
    private(set) var isTmuxAvailable: Bool = false
    private(set) var managedRepositories: [ManagedGitRepository] = []

    private let settings: AppSettings
    private let profilesDir: URL
    private let repositoriesFile: URL
    private var healthMonitorTask: Task<Void, Never>?
    private var localDiscoveryCache: [DiscoveredCodingSession] = []
    private var localDiscoveryCacheDate: Date?

    init(settings: AppSettings) {
        self.settings = settings

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        self.profilesDir = appSupport.appendingPathComponent("external-tools/profiles")
        self.repositoriesFile = appSupport.appendingPathComponent("external-tools/repositories.json")

        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: repositoriesFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        checkTmuxAvailability()
        loadProfiles()
        loadManagedRepositories()
        startHealthMonitor()
    }

    // MARK: - tmux Check

    private func checkTmuxAvailability() {
        let tmuxPath = settings.externalToolTmuxPath
        isTmuxAvailable = FileManager.default.isExecutableFile(atPath: tmuxPath)
    }

    private func startHealthMonitor() {
        healthMonitorTask?.cancel()
        healthMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let interval = max(5, self.settings.externalToolHealthCheckIntervalSeconds)
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                guard self.settings.externalToolEnabled else { continue }
                await self.checkAllHealth()
            }
        }
    }

    // MARK: - Profile CRUD

    func loadProfiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil) else {
            profiles = []
            return
        }

        let decoder = JSONDecoder()
        var loaded: [ExternalToolProfile] = []
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let profile = try decoder.decode(ExternalToolProfile.self, from: data)
                loaded.append(profile)
            } catch {
                Log.app.error("Failed to load external tool profile \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        profiles = loaded
        Log.app.info("Loaded \(loaded.count) external tool profiles")
    }

    func saveProfile(_ profile: ExternalToolProfile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(profile)
            let fileURL = profilesDir.appendingPathComponent("\(profile.id.uuidString).json")
            try data.write(to: fileURL)

            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx] = profile
            } else {
                profiles.append(profile)
            }
            Log.app.info("Saved external tool profile: \(profile.name)")
        } catch {
            Log.app.error("Failed to save external tool profile: \(error.localizedDescription)")
        }
    }

    func deleteProfile(id: UUID) {
        let fileURL = profilesDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        profiles.removeAll { $0.id == id }

        // Stop any running session for this profile
        if let session = sessions.first(where: { $0.profileId == id }) {
            Task { await stopSession(id: session.id) }
        }
        Log.app.info("Deleted external tool profile: \(id)")
    }

    // MARK: - Repository Registry

    private func loadManagedRepositories() {
        guard let data = try? Data(contentsOf: repositoriesFile) else {
            managedRepositories = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ManagedGitRepository].self, from: data) else {
            managedRepositories = []
            return
        }
        managedRepositories = decoded.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private func persistManagedRepositories() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(managedRepositories)
            try data.write(to: repositoriesFile, options: .atomic)
        } catch {
            Log.app.error("Failed to persist managed repositories: \(error.localizedDescription)")
        }
    }

    func initializeRepository(
        path: String,
        defaultBranch: String,
        createReadme: Bool,
        createGitignore: Bool
    ) async throws -> ManagedGitRepository {
        let rootPath = try await Task.detached(priority: .utility) {
            try Self.initializeGitRepository(
                atPath: path,
                defaultBranch: defaultBranch,
                createReadme: createReadme,
                createGitignore: createGitignore
            )
        }.value
        return upsertManagedRepository(rootPath: rootPath, source: .initialized)
    }

    func cloneRepository(
        remoteURL: String,
        destinationPath: String,
        branch: String?
    ) async throws -> ManagedGitRepository {
        let rootPath = try await Task.detached(priority: .utility) {
            try Self.cloneGitRepository(
                remoteURL: remoteURL,
                destinationPath: destinationPath,
                branch: branch
            )
        }.value
        return upsertManagedRepository(rootPath: rootPath, source: .cloned)
    }

    func attachRepository(path: String) async throws -> ManagedGitRepository {
        let rootPath = try await Task.detached(priority: .utility) {
            guard let root = Self.resolveGitTopLevel(path: path) else {
                throw ExternalToolError.invalidRepositoryPath(path)
            }
            return root
        }.value
        return upsertManagedRepository(rootPath: rootPath, source: .attached)
    }

    func removeManagedRepository(id: UUID, deleteDirectory: Bool) async throws {
        guard let index = managedRepositories.firstIndex(where: { $0.id == id }) else {
            throw ExternalToolError.repositoryNotFound(id)
        }

        var repository = managedRepositories[index]
        if deleteDirectory {
            let path = repository.rootPath
            try await Task.detached(priority: .utility) {
                guard FileManager.default.fileExists(atPath: path) else { return }
                try FileManager.default.removeItem(atPath: path)
            }.value
        }

        repository.isArchived = true
        repository.updatedAt = Date()
        managedRepositories[index] = repository
        managedRepositories.sort(by: { $0.updatedAt > $1.updatedAt })
        persistManagedRepositories()
    }

    private func upsertManagedRepository(
        rootPath: String,
        source: ManagedGitRepositorySource
    ) -> ManagedGitRepository {
        let normalizedRootPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let branch = Self.gitOutput(repoPath: normalizedRootPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
        let originURL = Self.gitOutput(repoPath: normalizedRootPath, args: ["remote", "get-url", "origin"])
        let name = URL(fileURLWithPath: normalizedRootPath).lastPathComponent
        let now = Date()

        if let index = managedRepositories.firstIndex(where: { $0.rootPath == normalizedRootPath }) {
            var existing = managedRepositories[index]
            existing.name = name
            existing.source = source
            existing.defaultBranch = branch
            existing.originURL = originURL
            existing.isArchived = false
            existing.updatedAt = now
            managedRepositories[index] = existing
            managedRepositories.sort(by: { $0.updatedAt > $1.updatedAt })
            persistManagedRepositories()
            return existing
        }

        let created = ManagedGitRepository(
            name: name,
            rootPath: normalizedRootPath,
            source: source,
            originURL: originURL,
            defaultBranch: branch,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
        managedRepositories.append(created)
        managedRepositories.sort(by: { $0.updatedAt > $1.updatedAt })
        persistManagedRepositories()
        return created
    }

    // MARK: - Session Lifecycle

    func startSession(profileId: UUID) async throws {
        guard isTmuxAvailable else { throw ExternalToolError.tmuxNotAvailable }
        guard let profile = profiles.first(where: { $0.id == profileId }) else {
            throw ExternalToolError.profileNotFound(profileId)
        }

        // Check if already running
        if sessions.contains(where: { $0.profileId == profileId && $0.status != .dead }) {
            throw ExternalToolError.sessionAlreadyRunning(profileId)
        }

        let sessionName = tmuxSessionName(for: profile)

        // Build tmux new-session command
        let fullCommand = ([profile.command] + profile.arguments).joined(separator: " ")
        let tmuxArgs: [String]
        if profile.isRemote, let ssh = profile.sshConfig {
            let sshKeyArgs = ssh.keyPath.map { ["-i", $0] } ?? []
            let remoteCmd = "\(settings.externalToolTmuxPath) new-session -d -s \(sessionName) -c \(profile.workingDirectory) '\(fullCommand)'"
            tmuxArgs = ["ssh"] + sshKeyArgs + ["-p", "\(ssh.port)", "\(ssh.user)@\(ssh.host)", remoteCmd]
        } else {
            tmuxArgs = [settings.externalToolTmuxPath, "new-session", "-d", "-s", sessionName, "-c", profile.workingDirectory, fullCommand]
        }

        let (_, exitCode) = await runProcess(tmuxArgs)
        guard exitCode == 0 else {
            throw ExternalToolError.sessionStartFailed("tmux exit code: \(exitCode)")
        }

        // Remove any dead session for this profile
        sessions.removeAll { $0.profileId == profileId && $0.status == .dead }

        let session = ExternalToolSession(
            profileId: profileId,
            tmuxSessionName: sessionName,
            status: .unknown,
            startedAt: Date()
        )
        sessions.append(session)
        Log.app.info("Started external tool session: \(profile.name) (\(sessionName))")

        // Initial health check
        await checkHealth(sessionId: session.id)
    }

    func stopSession(id: UUID) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let profile = profiles.first(where: { $0.id == session.profileId })

        let killArgs: [String]
        if let profile, profile.isRemote, let ssh = profile.sshConfig {
            let sshKeyArgs = ssh.keyPath.map { ["-i", $0] } ?? []
            let remoteCmd = "\(settings.externalToolTmuxPath) kill-session -t \(session.tmuxSessionName)"
            killArgs = ["ssh"] + sshKeyArgs + ["-p", "\(ssh.port)", "\(ssh.user)@\(ssh.host)", remoteCmd]
        } else {
            killArgs = [settings.externalToolTmuxPath, "kill-session", "-t", session.tmuxSessionName]
        }

        _ = await runProcess(killArgs)
        session.status = .dead
        Log.app.info("Stopped external tool session: \(session.tmuxSessionName)")
    }

    func restartSession(id: UUID) async throws {
        guard let session = sessions.first(where: { $0.id == id }) else {
            throw ExternalToolError.sessionNotFound(id)
        }
        let profileId = session.profileId
        await stopSession(id: id)
        sessions.removeAll { $0.id == id }
        try await startSession(profileId: profileId)
    }

    // MARK: - Work Dispatch

    func sendCommand(sessionId: UUID, command: String) async throws {
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            throw ExternalToolError.sessionNotFound(sessionId)
        }
        let profile = profiles.first(where: { $0.id == session.profileId })

        let sendKeysArgs: [String]
        if let profile, profile.isRemote, let ssh = profile.sshConfig {
            let sshKeyArgs = ssh.keyPath.map { ["-i", $0] } ?? []
            let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
            let remoteCmd = "\(settings.externalToolTmuxPath) send-keys -t \(session.tmuxSessionName) '\(escaped)' Enter"
            sendKeysArgs = ["ssh"] + sshKeyArgs + ["-p", "\(ssh.port)", "\(ssh.user)@\(ssh.host)", remoteCmd]
        } else {
            sendKeysArgs = [settings.externalToolTmuxPath, "send-keys", "-t", session.tmuxSessionName, command, "Enter"]
        }

        let (_, exitCode) = await runProcess(sendKeysArgs)
        if exitCode != 0 {
            Log.app.warning("send-keys failed for session \(session.tmuxSessionName)")
        } else {
            session.status = .busy
            session.lastActivityText = String(command.prefix(80))
            Log.app.info("Sent command to \(session.tmuxSessionName): \(command.prefix(50))")
        }
    }

    // MARK: - Health Check

    func checkHealth(sessionId: UUID) async {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        guard let profile = profiles.first(where: { $0.id == session.profileId }) else { return }

        let lines = settings.externalToolOutputCaptureLines
        let output = await captureOutput(sessionId: sessionId, lines: lines)
        session.lastOutput = output
        session.lastHealthCheckDate = Date()

        if output.isEmpty {
            // Check if tmux session still exists
            let hasSession = await tmuxSessionExists(session.tmuxSessionName, profile: profile)
            session.status = hasSession ? .unknown : .dead
            return
        }

        // Match patterns against the last few lines
        let recentOutput = output.suffix(10).joined(separator: "\n")
        let patterns = profile.healthCheckPatterns

        if matchesPattern(recentOutput, pattern: patterns.errorPattern) {
            session.status = .error
        } else if matchesPattern(recentOutput, pattern: patterns.waitingPattern) {
            session.status = .waiting
        } else if matchesPattern(recentOutput, pattern: patterns.busyPattern) {
            session.status = .busy
        } else if matchesPattern(recentOutput, pattern: patterns.idlePattern) {
            session.status = .idle
        } else {
            session.status = .unknown
        }
    }

    func checkAllHealth() async {
        for session in sessions where session.status != .dead {
            await checkHealth(sessionId: session.id)
        }

        // Auto-restart dead sessions if enabled
        // Collect dead session info first to avoid mutating during iteration
        if settings.externalToolAutoRestart {
            let deadEntries = sessions
                .filter { $0.status == .dead }
                .map { (id: $0.id, profileId: $0.profileId) }

            for entry in deadEntries {
                sessions.removeAll { $0.id == entry.id }
                do {
                    try await startSession(profileId: entry.profileId)
                    Log.app.info("Auto-restarted external tool session for profile \(entry.profileId)")
                } catch {
                    Log.app.warning("Auto-restart failed for profile \(entry.profileId): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Output

    func captureOutput(sessionId: UUID, lines: Int) async -> [String] {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return [] }
        let profile = profiles.first(where: { $0.id == session.profileId })

        let captureArgs: [String]
        if let profile, profile.isRemote, let ssh = profile.sshConfig {
            let sshKeyArgs = ssh.keyPath.map { ["-i", $0] } ?? []
            let remoteCmd = "\(settings.externalToolTmuxPath) capture-pane -t \(session.tmuxSessionName) -p -S -\(lines)"
            captureArgs = ["ssh"] + sshKeyArgs + ["-p", "\(ssh.port)", "\(ssh.user)@\(ssh.host)", remoteCmd]
        } else {
            captureArgs = [settings.externalToolTmuxPath, "capture-pane", "-t", session.tmuxSessionName, "-p", "-S", "-\(lines)"]
        }

        let (output, exitCode) = await runProcess(captureArgs)
        if exitCode != 0 {
            return []
        }
        return output.components(separatedBy: "\n")
    }

    func discoverGitRepositoryInsights(searchPaths: [String]?, limit: Int) async -> [GitRepositoryInsight] {
        let profilePaths = profiles.map(\.workingDirectory)
        let mergedPaths = (searchPaths ?? []) + profilePaths
        let effectiveLimit = max(1, min(200, limit))
        return await Task.detached(priority: .utility) {
            GitRepositoryInsightScanner.discover(
                searchPaths: mergedPaths.isEmpty ? nil : mergedPaths,
                limit: effectiveLimit
            )
        }.value
    }

    func discoverLocalCodingSessions(limit: Int) async -> [DiscoveredCodingSession] {
        let effectiveLimit = max(1, min(200, limit))
        if let localDiscoveryCacheDate,
           Date().timeIntervalSince(localDiscoveryCacheDate) < 10 {
            return Array(localDiscoveryCache.prefix(effectiveLimit))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let claudeRoot = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let discovered = await Task.detached(priority: .utility) {
            Self.discoverLocalCodingSessions(
                codexSessionsRoot: codexRoot,
                claudeProjectsRoot: claudeRoot,
                limit: effectiveLimit,
                now: Date()
            )
        }.value

        localDiscoveryCache = discovered
        localDiscoveryCacheDate = Date()
        return discovered
    }

    nonisolated static func discoverLocalCodingSessions(
        codexSessionsRoot: URL,
        claudeProjectsRoot: URL,
        limit: Int,
        now: Date = Date()
    ) -> [DiscoveredCodingSession] {
        let effectiveLimit = max(1, min(200, limit))
        let codex = discoverCodexSessionFiles(root: codexSessionsRoot, limit: effectiveLimit, now: now)
        let claude = discoverClaudeProjectFiles(root: claudeProjectsRoot, limit: effectiveLimit, now: now)

        var dedup: [String: DiscoveredCodingSession] = [:]
        for item in (codex + claude).sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let key = "\(item.provider)|\(item.sessionId)"
            if dedup[key] == nil {
                dedup[key] = item
            }
        }

        return Array(dedup.values)
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(effectiveLimit)
            .map { $0 }
    }

    // MARK: - Helpers

    func tmuxSessionName(for profile: ExternalToolProfile) -> String {
        let prefix = settings.externalToolSessionPrefix
        let sanitized = profile.name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(prefix)\(sanitized)"
    }

    private func matchesPattern(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private func tmuxSessionExists(_ name: String, profile: ExternalToolProfile) async -> Bool {
        let args: [String]
        if profile.isRemote, let ssh = profile.sshConfig {
            let sshKeyArgs = ssh.keyPath.map { ["-i", $0] } ?? []
            let remoteCmd = "\(settings.externalToolTmuxPath) has-session -t \(name)"
            args = ["ssh"] + sshKeyArgs + ["-p", "\(ssh.port)", "\(ssh.user)@\(ssh.host)", remoteCmd]
        } else {
            args = [settings.externalToolTmuxPath, "has-session", "-t", name]
        }
        let (_, exitCode) = await runProcess(args)
        return exitCode == 0
    }

    private func runProcess(_ arguments: [String]) async -> (output: String, exitCode: Int32) {
        guard !arguments.isEmpty else { return ("", 1) }

        let args = arguments
        return await Task.detached {
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()

                // Read pipe data BEFORE waitUntilExit to avoid deadlock
                // when output exceeds pipe buffer (64KB)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""
                return (output, process.terminationStatus)
            } catch {
                return ("", Int32(1))
            }
        }.value
    }

    nonisolated static func initializeGitRepository(
        atPath path: String,
        defaultBranch: String,
        createReadme: Bool,
        createGitignore: Bool
    ) throws -> String {
        let directoryURL = try validatedDirectoryURL(path: path, createIfMissing: true)
        let branch = defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveBranch = branch.isEmpty ? "main" : branch

        let initResult = runProcessSync(
            ["git", "init", "-b", effectiveBranch],
            currentDirectoryPath: directoryURL.path
        )
        guard initResult.exitCode == 0 else {
            throw ExternalToolError.repositoryOperationFailed(initResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if createReadme {
            let readme = directoryURL.appendingPathComponent("README.md")
            if !FileManager.default.fileExists(atPath: readme.path) {
                let title = "# \(directoryURL.lastPathComponent)\n"
                if let data = title.data(using: .utf8) {
                    try data.write(to: readme, options: .atomic)
                }
            }
        }

        if createGitignore {
            let gitignore = directoryURL.appendingPathComponent(".gitignore")
            if !FileManager.default.fileExists(atPath: gitignore.path) {
                let template = """
                .DS_Store
                .build/
                DerivedData/
                """
                if let data = template.data(using: .utf8) {
                    try data.write(to: gitignore, options: .atomic)
                }
            }
        }

        return directoryURL.standardizedFileURL.path
    }

    nonisolated static func cloneGitRepository(
        remoteURL: String,
        destinationPath: String,
        branch: String?
    ) throws -> String {
        let trimmedRemote = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty else {
            throw ExternalToolError.repositoryOperationFailed("원격 URL이 비어 있습니다.")
        }

        let destinationURL = URL(fileURLWithPath: expandedPath(destinationPath)).standardizedFileURL
        let parentURL = destinationURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ExternalToolError.invalidRepositoryPath(destinationPath)
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw ExternalToolError.repositoryOperationFailed("대상 경로가 이미 존재합니다: \(destinationURL.path)")
        }

        var args = ["git", "clone"]
        if let branch, !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--branch", branch])
        }
        args.append(contentsOf: [trimmedRemote, destinationURL.path])

        let cloneResult = runProcessSync(args, currentDirectoryPath: parentURL.path)
        guard cloneResult.exitCode == 0 else {
            throw ExternalToolError.repositoryOperationFailed(cloneResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return destinationURL.path
    }

    nonisolated static func resolveGitTopLevel(path: String) -> String? {
        let standardized = URL(fileURLWithPath: expandedPath(path)).standardizedFileURL.path
        let output = gitOutput(repoPath: standardized, args: ["rev-parse", "--show-toplevel"])
        return output.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    nonisolated private static func validatedDirectoryURL(path: String, createIfMissing: Bool) throws -> URL {
        let normalized = URL(fileURLWithPath: expandedPath(path)).standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ExternalToolError.invalidRepositoryPath(path)
            }
            return normalized
        }

        guard createIfMissing else {
            throw ExternalToolError.invalidRepositoryPath(path)
        }
        do {
            try FileManager.default.createDirectory(at: normalized, withIntermediateDirectories: true)
            return normalized
        } catch {
            throw ExternalToolError.repositoryOperationFailed(error.localizedDescription)
        }
    }

    nonisolated private static func expandedPath(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + "/" + path.dropFirst(2) }
        return path
    }

    nonisolated private static func gitOutput(repoPath: String, args: [String]) -> String? {
        let result = runProcessSync(["git"] + args, currentDirectoryPath: repoPath)
        guard result.exitCode == 0 else { return nil }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    nonisolated private static func runProcessSync(
        _ arguments: [String],
        currentDirectoryPath: String?
    ) -> (output: String, exitCode: Int32) {
        guard !arguments.isEmpty else { return ("", 1) }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        if let currentDirectoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
        }

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, process.terminationStatus)
        } catch {
            return (error.localizedDescription, 1)
        }
    }

    nonisolated private static func discoverCodexSessionFiles(
        root: URL,
        limit: Int,
        now: Date
    ) -> [DiscoveredCodingSession] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }
            files.append((url: url, modifiedAt: values.contentModificationDate ?? .distantPast))
        }

        let sampleLimit = max(limit * 3, 40)
        let sampled = files
            .sorted(by: { $0.modifiedAt > $1.modifiedAt })
            .prefix(sampleLimit)

        return sampled.map { candidate in
            let meta = parseCodexSessionMeta(fromFirstLine: readFirstLine(of: candidate.url))
            let sessionId = meta?.id ?? candidate.url.deletingPathExtension().lastPathComponent
            let isActive = now.timeIntervalSince(candidate.modifiedAt) <= 60 * 45
            return DiscoveredCodingSession(
                source: .codexSessionFile,
                provider: "codex",
                sessionId: sessionId,
                workingDirectory: meta?.cwd,
                path: candidate.url.path,
                updatedAt: candidate.modifiedAt,
                isActive: isActive
            )
        }
    }

    nonisolated private static func discoverClaudeProjectFiles(
        root: URL,
        limit: Int,
        now: Date
    ) -> [DiscoveredCodingSession] {
        let fm = FileManager.default
        var discovered: [DiscoveredCodingSession] = []

        // 1) Prefer structured session index entries when present.
        if let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let indexURL as URL in enumerator {
                guard indexURL.lastPathComponent == "sessions-index.json",
                      let data = try? Data(contentsOf: indexURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let entries = json["entries"] as? [[String: Any]] else {
                    continue
                }

                for entry in entries {
                    guard let sessionId = entry["sessionId"] as? String, !sessionId.isEmpty else {
                        continue
                    }
                    let projectPath = entry["projectPath"] as? String
                    let fullPath = entry["fullPath"] as? String
                    let modifiedISO = entry["modified"] as? String
                    let fileMtimeMillis = (entry["fileMtime"] as? NSNumber)?.doubleValue
                    let modifiedAt = parseISO8601Date(modifiedISO)
                        ?? fileMtimeMillis.map { Date(timeIntervalSince1970: $0 / 1_000) }
                        ?? .distantPast
                    let isActive = now.timeIntervalSince(modifiedAt) <= 60 * 60 * 12
                    discovered.append(
                        DiscoveredCodingSession(
                            source: .claudeProjectFile,
                            provider: "claude",
                            sessionId: sessionId,
                            workingDirectory: projectPath,
                            path: fullPath ?? indexURL.path,
                            updatedAt: modifiedAt,
                            isActive: isActive
                        )
                    )
                }
            }
        }

        // 2) Fallback: scan project JSONL files directly.
        var files: [(url: URL, modifiedAt: Date)] = []
        if let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                guard !url.lastPathComponent.hasPrefix("agent-") else { continue }
                let path = url.path
                guard !path.contains("/subagents/"),
                      !path.contains("/tool-results/"),
                      !path.contains("/memory/") else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                files.append((url: url, modifiedAt: values.contentModificationDate ?? .distantPast))
            }
        }

        let sampleLimit = max(limit * 4, 60)
        let sampled = files
            .sorted(by: { $0.modifiedAt > $1.modifiedAt })
            .prefix(sampleLimit)

        for candidate in sampled {
            let meta = parseClaudeSessionMeta(fromFirstLine: readFirstLine(of: candidate.url))
            let sessionId = meta?.id ?? candidate.url.deletingPathExtension().lastPathComponent
            let inferredProjectPath = decodeClaudeProjectFolder(candidate.url.deletingLastPathComponent().lastPathComponent)
            let workingDirectory = meta?.cwd ?? inferredProjectPath
            let isActive = now.timeIntervalSince(candidate.modifiedAt) <= 60 * 60 * 12
            discovered.append(
                DiscoveredCodingSession(
                    source: .claudeProjectFile,
                    provider: "claude",
                    sessionId: sessionId,
                    workingDirectory: workingDirectory,
                    path: candidate.url.path,
                    updatedAt: candidate.modifiedAt,
                    isActive: isActive
                )
            )
        }

        var dedup: [String: DiscoveredCodingSession] = [:]
        for item in discovered.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let key = "\(item.provider)|\(item.sessionId)"
            if dedup[key] == nil {
                dedup[key] = item
            }
        }

        return Array(dedup.values)
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(max(limit * 3, 40))
            .map { $0 }
    }

    nonisolated private static func readFirstLine(of fileURL: URL, maxBytes: Int = 512 * 1024) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        var data = Data()
        while data.count < maxBytes {
            guard let chunk = try? fileHandle.read(upToCount: 4096), !chunk.isEmpty else { break }
            if let newline = chunk.firstIndex(of: 0x0A) {
                data.append(chunk.prefix(upTo: newline))
                break
            }
            data.append(chunk)
        }

        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func parseCodexSessionMeta(fromFirstLine line: String?) -> (id: String, cwd: String?)? {
        guard let line,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "session_meta",
              let payload = json["payload"] as? [String: Any],
              let id = payload["id"] as? String else {
            return nil
        }

        let cwd = payload["cwd"] as? String
        return (id: id, cwd: cwd)
    }

    nonisolated private static func parseClaudeSessionMeta(fromFirstLine line: String?) -> (id: String, cwd: String?)? {
        guard let line,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let sessionId = (json["sessionId"] as? String) ?? (json["session_id"] as? String)
        guard let sessionId, !sessionId.isEmpty else { return nil }
        let cwd = json["cwd"] as? String
        return (id: sessionId, cwd: cwd)
    }

    nonisolated private static func parseISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    nonisolated private static func decodeClaudeProjectFolder(_ folderName: String) -> String? {
        guard folderName.hasPrefix("-"), folderName.count > 1 else { return nil }
        return folderName.replacingOccurrences(of: "-", with: "/")
    }
}
