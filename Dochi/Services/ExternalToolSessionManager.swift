import Foundation
import os

// MARK: - Protocol

@MainActor
protocol ExternalToolSessionManagerProtocol: AnyObject, Sendable {
    var profiles: [ExternalToolProfile] { get }
    var sessions: [ExternalToolSession] { get }
    var isTmuxAvailable: Bool { get }

    // Profile CRUD
    func loadProfiles()
    func saveProfile(_ profile: ExternalToolProfile)
    func deleteProfile(id: UUID)

    // Session lifecycle
    func startSession(profileId: UUID) async throws
    func stopSession(id: UUID) async
    func restartSession(id: UUID) async throws
    func activeSession(for profileId: UUID) -> ExternalToolSession?
    func openInTerminal(sessionId: UUID) async throws

    // Work dispatch
    func sendCommand(sessionId: UUID, command: String) async throws

    // Health check
    func checkHealth(sessionId: UUID) async
    func checkAllHealth() async

    // Output
    func captureOutput(sessionId: UUID, lines: Int) async -> [String]

    // Repository insights
    func discoverGitRepositoryInsights(searchPaths: [String]?, limit: Int) async -> [GitRepositoryInsight]
}

// MARK: - Errors

enum ExternalToolError: LocalizedError {
    case tmuxNotAvailable
    case profileNotFound(UUID)
    case sessionNotFound(UUID)
    case sessionAlreadyRunning(UUID)
    case sessionStartFailed(String)
    case commandDispatchFailed(String)
    case externalTerminalLaunchFailed(String)

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
        case .commandDispatchFailed(let reason):
            return "명령 전송 실패: \(reason)"
        case .externalTerminalLaunchFailed(let reason):
            return "터미널 열기 실패: \(reason)"
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

    private let settings: AppSettings
    private let profilesDir: URL
    private var healthMonitorTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        self.profilesDir = appSupport.appendingPathComponent("external-tools/profiles")

        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        checkTmuxAvailability()
        loadProfiles()
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

        // If tmux session already exists (e.g. app restart), attach instead of failing.
        if await tmuxSessionExists(sessionName, profile: profile) {
            let session = Self.reuseOrCreateSessionEntry(
                sessions: &sessions,
                profileId: profileId,
                tmuxSessionName: sessionName
            )
            Log.app.info("Attached to existing external tool session: \(profile.name) (\(sessionName))")
            await checkHealth(sessionId: session.id)
            return
        }

        // Build tmux new-session command
        let fullCommand = ([profile.command] + profile.arguments).joined(separator: " ")
        let tmuxArgs: [String]
        if profile.isRemote, let ssh = profile.sshConfig {
            let sshKeyArgs = ssh.keyPath.map { ["-i", $0] } ?? []
            let remoteCmd = "\(settings.externalToolTmuxPath) new-session -d -s \(sessionName) -c \(profile.workingDirectory) '\(fullCommand)'"
            tmuxArgs = ["ssh"] + sshKeyArgs + ["-p", "\(ssh.port)", "\(ssh.user)@\(ssh.host)", remoteCmd]
        } else {
            let localWorkingDirectory = try Self.resolveLocalWorkingDirectory(profile.workingDirectory)
            tmuxArgs = [settings.externalToolTmuxPath, "new-session", "-d", "-s", sessionName, "-c", localWorkingDirectory, fullCommand]
        }

        let (output, exitCode) = await runProcess(tmuxArgs)
        guard exitCode == 0 else {
            let reason = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.localizedCaseInsensitiveContains("duplicate session") {
                let session = Self.reuseOrCreateSessionEntry(
                    sessions: &sessions,
                    profileId: profileId,
                    tmuxSessionName: sessionName
                )
                Log.app.info("Reused existing external tool session after duplicate error: \(profile.name) (\(sessionName))")
                await checkHealth(sessionId: session.id)
                return
            }
            if reason.isEmpty {
                throw ExternalToolError.sessionStartFailed("tmux exit code: \(exitCode)")
            }
            throw ExternalToolError.sessionStartFailed(reason)
        }

        let session = Self.reuseOrCreateSessionEntry(
            sessions: &sessions,
            profileId: profileId,
            tmuxSessionName: sessionName
        )
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

    func activeSession(for profileId: UUID) -> ExternalToolSession? {
        sessions.first { $0.profileId == profileId && $0.status != .dead }
    }

    func openInTerminal(sessionId: UUID) async throws {
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            throw ExternalToolError.sessionNotFound(sessionId)
        }
        guard let profile = profiles.first(where: { $0.id == session.profileId }) else {
            throw ExternalToolError.profileNotFound(session.profileId)
        }

        let command = Self.buildAttachShellCommand(
            tmuxPath: settings.externalToolTmuxPath,
            sessionName: session.tmuxSessionName,
            profile: profile
        )
        let preference = ExternalTerminalApp(rawValue: settings.externalToolTerminalApp) ?? .auto
        let terminalApp = Self.resolveExternalTerminalApp(preference: preference)

        let args: [String]
        switch terminalApp {
        case .terminal:
            args = Self.buildTerminalAppleScriptArguments(command: command)
        case .ghostty:
            if !Self.ghosttyAppExists() {
                throw ExternalToolError.externalTerminalLaunchFailed("Ghostty 앱을 찾을 수 없습니다. /Applications 또는 ~/Applications에 설치하세요.")
            }
            args = Self.buildGhosttyOpenArguments(
                command: command,
                shellPath: settings.terminalShellPath
            )
        case .auto:
            args = Self.buildTerminalAppleScriptArguments(command: command)
        }

        let (output, exitCode) = await runProcess(args)
        guard exitCode == 0 else {
            let reason = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                throw ExternalToolError.externalTerminalLaunchFailed("외장 터미널 실행 실패 (exit code: \(exitCode))")
            }
            throw ExternalToolError.externalTerminalLaunchFailed(reason)
        }
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

        let (output, exitCode) = await runProcess(sendKeysArgs)
        if exitCode != 0 {
            Log.app.warning("send-keys failed for session \(session.tmuxSessionName)")
            let reason = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                throw ExternalToolError.commandDispatchFailed("send-keys exit code: \(exitCode)")
            }
            throw ExternalToolError.commandDispatchFailed(reason)
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

    // MARK: - Helpers

    func tmuxSessionName(for profile: ExternalToolProfile) -> String {
        let prefix = settings.externalToolSessionPrefix
        let sanitized = profile.name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(prefix)\(sanitized)"
    }

    nonisolated static func resolveLocalWorkingDirectory(
        _ rawPath: String,
        homeDirectoryPath: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "~" : trimmed

        let resolvedPath: String
        if candidate == "~" {
            resolvedPath = homeDirectoryPath
        } else if candidate.hasPrefix("~/") {
            resolvedPath = URL(fileURLWithPath: homeDirectoryPath)
                .appendingPathComponent(String(candidate.dropFirst(2)))
                .path
        } else {
            resolvedPath = candidate
        }

        let standardizedPath = URL(fileURLWithPath: resolvedPath).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExternalToolError.sessionStartFailed("작업 디렉터리를 찾을 수 없습니다: \(standardizedPath)")
        }
        return standardizedPath
    }

    nonisolated static func buildAttachShellCommand(
        tmuxPath: String,
        sessionName: String,
        profile: ExternalToolProfile
    ) -> String {
        let quotedTmux = shellQuote(tmuxPath)
        let quotedSession = shellQuote(sessionName)

        if profile.isRemote, let ssh = profile.sshConfig {
            let remoteAttach = "\(quotedTmux) attach -t \(quotedSession)"
            var parts: [String] = ["ssh", "-p", "\(ssh.port)"]
            if let keyPath = ssh.keyPath, !keyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("-i")
                parts.append(shellQuote(keyPath))
            }
            parts.append("\(ssh.user)@\(ssh.host)")
            parts.append(shellQuote(remoteAttach))
            return parts.joined(separator: " ")
        }

        return "\(quotedTmux) attach -t \(quotedSession)"
    }

    nonisolated static func resolveExternalTerminalApp(
        preference: ExternalTerminalApp,
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        systemApplicationsPath: String = "/Applications"
    ) -> ExternalTerminalApp {
        switch preference {
        case .terminal, .ghostty:
            return preference
        case .auto:
            return ghosttyAppExists(
                fileManager: fileManager,
                homeDirectoryPath: homeDirectoryPath,
                systemApplicationsPath: systemApplicationsPath
            ) ? .ghostty : .terminal
        }
    }

    nonisolated static func ghosttyAppExists(
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        systemApplicationsPath: String = "/Applications"
    ) -> Bool {
        let candidates = [
            URL(fileURLWithPath: systemApplicationsPath).appendingPathComponent("Ghostty.app").path,
            URL(fileURLWithPath: homeDirectoryPath).appendingPathComponent("Applications/Ghostty.app").path
        ]
        return candidates.contains { fileManager.fileExists(atPath: $0) }
    }

    nonisolated static func buildTerminalAppleScriptArguments(command: String) -> [String] {
        let escaped = escapeAppleScriptString(command)
        return [
            "/usr/bin/osascript",
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(escaped)\""
        ]
    }

    nonisolated static func buildGhosttyOpenArguments(command: String, shellPath: String) -> [String] {
        [
            "/usr/bin/open",
            "-na", "Ghostty.app",
            "--args",
            "-e", shellPath,
            "-lc", command
        ]
    }

    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    nonisolated static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @MainActor
    static func reuseOrCreateSessionEntry(
        sessions: inout [ExternalToolSession],
        profileId: UUID,
        tmuxSessionName: String,
        now: Date = Date()
    ) -> ExternalToolSession {
        sessions.removeAll { $0.profileId == profileId && $0.status == .dead }

        if let existing = sessions.first(where: { $0.profileId == profileId && $0.tmuxSessionName == tmuxSessionName }) {
            existing.status = .unknown
            if existing.startedAt == nil {
                existing.startedAt = now
            }
            return existing
        }

        let session = ExternalToolSession(
            profileId: profileId,
            tmuxSessionName: tmuxSessionName,
            status: .unknown,
            startedAt: now
        )
        sessions.append(session)
        return session
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
}
