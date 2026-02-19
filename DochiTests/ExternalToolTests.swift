import XCTest
@testable import Dochi

// MARK: - ExternalToolModels Tests

final class ExternalToolModelsTests: XCTestCase {

    func testExternalToolStatusRawValues() {
        XCTAssertEqual(ExternalToolStatus.idle.rawValue, "idle")
        XCTAssertEqual(ExternalToolStatus.busy.rawValue, "busy")
        XCTAssertEqual(ExternalToolStatus.waiting.rawValue, "waiting")
        XCTAssertEqual(ExternalToolStatus.error.rawValue, "error")
        XCTAssertEqual(ExternalToolStatus.dead.rawValue, "dead")
        XCTAssertEqual(ExternalToolStatus.unknown.rawValue, "unknown")
    }

    func testExternalTerminalAppRawValues() {
        XCTAssertEqual(ExternalTerminalApp.auto.rawValue, "auto")
        XCTAssertEqual(ExternalTerminalApp.terminal.rawValue, "terminal")
        XCTAssertEqual(ExternalTerminalApp.ghostty.rawValue, "ghostty")
    }

    func testHealthCheckPatternsPresets() {
        let claudeCode = HealthCheckPatterns.claudeCode
        XCTAssertFalse(claudeCode.idlePattern.isEmpty)
        XCTAssertFalse(claudeCode.busyPattern.isEmpty)
        XCTAssertFalse(claudeCode.waitingPattern.isEmpty)
        XCTAssertFalse(claudeCode.errorPattern.isEmpty)

        let codexCLI = HealthCheckPatterns.codexCLI
        XCTAssertFalse(codexCLI.idlePattern.isEmpty)

        let aider = HealthCheckPatterns.aider
        XCTAssertFalse(aider.idlePattern.isEmpty)
    }

    func testHealthCheckPatternsEquatable() {
        XCTAssertEqual(HealthCheckPatterns.claudeCode, HealthCheckPatterns.claudeCode)
        XCTAssertNotEqual(HealthCheckPatterns.claudeCode, HealthCheckPatterns.codexCLI)
    }

    func testSSHConfigDefaults() {
        let config = SSHConfig(host: "example.com", user: "user")
        XCTAssertEqual(config.port, 22)
        XCTAssertNil(config.keyPath)
    }

    func testSSHConfigCustomValues() {
        let config = SSHConfig(host: "server.local", port: 2222, user: "admin", keyPath: "/home/admin/.ssh/id_rsa")
        XCTAssertEqual(config.host, "server.local")
        XCTAssertEqual(config.port, 2222)
        XCTAssertEqual(config.user, "admin")
        XCTAssertEqual(config.keyPath, "/home/admin/.ssh/id_rsa")
    }

    func testExternalToolProfileDefaults() {
        let profile = ExternalToolProfile(name: "Test", command: "test")
        XCTAssertEqual(profile.name, "Test")
        XCTAssertEqual(profile.command, "test")
        XCTAssertEqual(profile.icon, "terminal.fill")
        XCTAssertEqual(profile.arguments, [])
        XCTAssertEqual(profile.workingDirectory, "~")
        XCTAssertNil(profile.sshConfig)
        XCTAssertEqual(profile.healthCheckPatterns, .claudeCode)
        XCTAssertFalse(profile.isRemote)
    }

    func testExternalToolProfileRemote() {
        let profile = ExternalToolProfile(
            name: "Remote",
            command: "claude",
            sshConfig: SSHConfig(host: "remote.host", user: "user")
        )
        XCTAssertTrue(profile.isRemote)
    }

    func testExternalToolProfileCodable() throws {
        let profile = ExternalToolProfile(
            name: "Claude Code",
            command: "claude",
            arguments: ["--model", "opus"],
            workingDirectory: "/home/user"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExternalToolProfile.self, from: data)
        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, profile.name)
        XCTAssertEqual(decoded.command, profile.command)
        XCTAssertEqual(decoded.arguments, profile.arguments)
        XCTAssertEqual(decoded.workingDirectory, profile.workingDirectory)
    }

    func testExternalToolPresets() {
        for preset in ExternalToolPreset.allCases {
            let profile = preset.profile
            XCTAssertFalse(profile.name.isEmpty)
            XCTAssertFalse(profile.command.isEmpty)
        }
        XCTAssertEqual(ExternalToolPreset.claudeCode.profile.command, "claude")
        XCTAssertEqual(ExternalToolPreset.codexCLI.profile.command, "codex")
        XCTAssertEqual(ExternalToolPreset.aider.profile.command, "aider")
    }

    @MainActor
    func testExternalToolSession() {
        let profileId = UUID()
        let session = ExternalToolSession(
            profileId: profileId,
            tmuxSessionName: "dochi-test",
            status: .idle
        )
        XCTAssertEqual(session.profileId, profileId)
        XCTAssertEqual(session.tmuxSessionName, "dochi-test")
        XCTAssertEqual(session.status, .idle)
        XCTAssertNotNil(session.startedAt)
        XCTAssertTrue(session.lastOutput.isEmpty)
    }
}

// MARK: - MockExternalToolSessionManager Tests

final class ExternalToolManagerTests: XCTestCase {

    @MainActor
    func testProfileCRUD() async {
        let manager = MockExternalToolSessionManager()

        let profile = ExternalToolProfile(name: "Test Tool", command: "test-cmd")
        manager.saveProfile(profile)
        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.saveProfileCallCount, 1)
        XCTAssertEqual(manager.lastSavedProfile?.name, "Test Tool")

        // Update
        var updated = profile
        updated.name = "Updated Tool"
        manager.saveProfile(updated)
        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.profiles.first?.name, "Updated Tool")

        // Delete
        manager.deleteProfile(id: profile.id)
        XCTAssertTrue(manager.profiles.isEmpty)
        XCTAssertEqual(manager.deleteProfileCallCount, 1)
    }

    @MainActor
    func testSessionStartStop() async throws {
        let manager = MockExternalToolSessionManager()

        let profile = ExternalToolProfile(name: "Claude", command: "claude")
        manager.saveProfile(profile)

        try await manager.startSession(profileId: profile.id)
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions.first?.status, .idle)
        XCTAssertEqual(manager.startSessionCallCount, 1)

        let sessionId = manager.sessions.first!.id
        await manager.stopSession(id: sessionId)
        XCTAssertEqual(manager.sessions.first?.status, .dead)
        XCTAssertEqual(manager.stopSessionCallCount, 1)
    }

    @MainActor
    func testActiveSessionReturnsRunningSessionForProfile() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(name: "Codex", command: "codex")
        manager.saveProfile(profile)

        try await manager.startSession(profileId: profile.id)

        let active = manager.activeSession(for: profile.id)
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.profileId, profile.id)
        XCTAssertEqual(active?.status, .idle)
    }

    @MainActor
    func testActiveSessionIgnoresDeadSession() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(name: "Codex", command: "codex")
        manager.saveProfile(profile)

        try await manager.startSession(profileId: profile.id)
        guard let sessionId = manager.sessions.first?.id else {
            XCTFail("Expected created session")
            return
        }
        await manager.stopSession(id: sessionId)

        XCTAssertNil(manager.activeSession(for: profile.id))
    }

    @MainActor
    func testSessionStartFailsWithUnknownProfile() async {
        let manager = MockExternalToolSessionManager()

        do {
            try await manager.startSession(profileId: UUID())
            XCTFail("Should throw profileNotFound")
        } catch let error as ExternalToolError {
            if case .profileNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testSendCommand() async throws {
        let manager = MockExternalToolSessionManager()

        let profile = ExternalToolProfile(name: "aider", command: "aider")
        manager.saveProfile(profile)
        try await manager.startSession(profileId: profile.id)

        let sessionId = manager.sessions.first!.id
        try await manager.sendCommand(sessionId: sessionId, command: "fix bug #123")
        XCTAssertEqual(manager.sendCommandCallCount, 1)
        XCTAssertEqual(manager.lastSentCommand, "fix bug #123")
    }

    @MainActor
    func testSendCommandFailsWithUnknownSession() async {
        let manager = MockExternalToolSessionManager()

        do {
            try await manager.sendCommand(sessionId: UUID(), command: "hello")
            XCTFail("Should throw sessionNotFound")
        } catch let error as ExternalToolError {
            if case .sessionNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testHealthCheck() async {
        let manager = MockExternalToolSessionManager()
        await manager.checkAllHealth()
        XCTAssertEqual(manager.checkAllHealthCallCount, 1)
    }

    @MainActor
    func testCaptureOutput() async throws {
        let manager = MockExternalToolSessionManager()
        manager.mockOutputLines = ["line1", "line2", "line3"]

        let profile = ExternalToolProfile(name: "test", command: "test")
        manager.saveProfile(profile)
        try await manager.startSession(profileId: profile.id)

        let sessionId = manager.sessions.first!.id
        let output = await manager.captureOutput(sessionId: sessionId, lines: 2)
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output, ["line1", "line2"])
    }

    @MainActor
    func testRestartSession() async throws {
        let manager = MockExternalToolSessionManager()

        let profile = ExternalToolProfile(name: "test", command: "test")
        manager.saveProfile(profile)
        try await manager.startSession(profileId: profile.id)

        let sessionId = manager.sessions.first!.id
        try await manager.restartSession(id: sessionId)

        XCTAssertEqual(manager.restartSessionCallCount, 1)
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions.first?.status, .idle)
    }

    @MainActor
    func testOpenInTerminal() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(name: "test", command: "codex")
        manager.saveProfile(profile)
        try await manager.startSession(profileId: profile.id)
        guard let sessionId = manager.sessions.first?.id else {
            return XCTFail("Expected created session")
        }

        try await manager.openInTerminal(sessionId: sessionId)

        XCTAssertEqual(manager.openInTerminalCallCount, 1)
    }

    @MainActor
    func testOpenInTerminalFailsWithUnknownSession() async {
        let manager = MockExternalToolSessionManager()

        do {
            try await manager.openInTerminal(sessionId: UUID())
            XCTFail("Should throw sessionNotFound")
        } catch let error as ExternalToolError {
            if case .sessionNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - ExternalTool Working Directory Resolution Tests

final class ExternalToolWorkingDirectoryResolutionTests: XCTestCase {

    func testResolveLocalWorkingDirectoryExpandsTilde() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let resolved = try ExternalToolSessionManager.resolveLocalWorkingDirectory(
            "~",
            homeDirectoryPath: tempHome.path
        )

        XCTAssertEqual(resolved, tempHome.standardizedFileURL.path)
    }

    func testResolveLocalWorkingDirectoryExpandsNestedTildePath() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let child = tempHome.appendingPathComponent("workspace/project")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let resolved = try ExternalToolSessionManager.resolveLocalWorkingDirectory(
            "~/workspace/project",
            homeDirectoryPath: tempHome.path
        )

        XCTAssertEqual(resolved, child.standardizedFileURL.path)
    }

    func testResolveLocalWorkingDirectoryThrowsForMissingDirectory() {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        XCTAssertThrowsError(
            try ExternalToolSessionManager.resolveLocalWorkingDirectory(
                "~/not-existing",
                homeDirectoryPath: tempHome.path
            )
        ) { error in
            guard case ExternalToolError.sessionStartFailed(let reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("작업 디렉터리를 찾을 수 없습니다"))
        }
    }

    func testResolveLocalWorkingDirectoryThrowsWhenPathIsFile() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        let fileURL = tempHome.appendingPathComponent("note.txt")
        try Data("test".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        XCTAssertThrowsError(
            try ExternalToolSessionManager.resolveLocalWorkingDirectory(
                fileURL.path,
                homeDirectoryPath: tempHome.path
            )
        ) { error in
            guard case ExternalToolError.sessionStartFailed(let reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("작업 디렉터리를 찾을 수 없습니다"))
        }
    }
}

// MARK: - ExternalTool Session Reuse Tests

@MainActor
final class ExternalToolSessionReuseTests: XCTestCase {

    func testReuseOrCreateSessionEntryCreatesNewSession() {
        var sessions: [ExternalToolSession] = []
        let profileId = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let created = ExternalToolSessionManager.reuseOrCreateSessionEntry(
            sessions: &sessions,
            profileId: profileId,
            tmuxSessionName: "dochi-test",
            now: now
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, created.id)
        XCTAssertEqual(created.status, .unknown)
        XCTAssertEqual(created.startedAt, now)
    }

    func testReuseOrCreateSessionEntryReusesExistingSession() {
        let profileId = UUID()
        let existing = ExternalToolSession(
            profileId: profileId,
            tmuxSessionName: "dochi-test",
            status: .busy,
            startedAt: nil
        )
        var sessions = [existing]
        let now = Date(timeIntervalSince1970: 1_700_000_100)

        let reused = ExternalToolSessionManager.reuseOrCreateSessionEntry(
            sessions: &sessions,
            profileId: profileId,
            tmuxSessionName: "dochi-test",
            now: now
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(reused.id, existing.id)
        XCTAssertEqual(reused.status, .unknown)
        XCTAssertEqual(reused.startedAt, now)
    }

    func testReuseOrCreateSessionEntryRemovesDeadThenCreates() {
        let profileId = UUID()
        let dead = ExternalToolSession(
            profileId: profileId,
            tmuxSessionName: "dochi-test",
            status: .dead
        )
        var sessions = [dead]

        let created = ExternalToolSessionManager.reuseOrCreateSessionEntry(
            sessions: &sessions,
            profileId: profileId,
            tmuxSessionName: "dochi-test"
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotEqual(created.id, dead.id)
        XCTAssertEqual(created.status, .unknown)
    }
}

// MARK: - ExternalTool Attach Command Tests

final class ExternalToolAttachCommandTests: XCTestCase {

    @MainActor
    func testTmuxSessionNameSanitizesProfileName() {
        let settings = AppSettings()
        settings.externalToolSessionPrefix = "dochi-"
        let manager = ExternalToolSessionManager(settings: settings)
        let profile = ExternalToolProfile(name: "Claude Code #1!", command: "claude")

        let sessionName = manager.tmuxSessionName(for: profile)

        XCTAssertEqual(sessionName, "dochi-claude-code-1")
    }

    func testBuildAttachShellCommandForLocalProfile() {
        let profile = ExternalToolProfile(name: "Local Codex", command: "codex")

        let command = ExternalToolSessionManager.buildAttachShellCommand(
            tmuxPath: "/opt/homebrew/bin/tmux",
            sessionName: "dochi-local",
            profile: profile
        )

        XCTAssertEqual(command, "'/opt/homebrew/bin/tmux' attach -t 'dochi-local'")
    }

    func testBuildAttachShellCommandForRemoteProfile() {
        let profile = ExternalToolProfile(
            name: "Remote Codex",
            command: "codex",
            sshConfig: SSHConfig(host: "example.com", port: 2222, user: "ubuntu", keyPath: "~/.ssh/id_ed25519")
        )

        let command = ExternalToolSessionManager.buildAttachShellCommand(
            tmuxPath: "/opt/homebrew/bin/tmux",
            sessionName: "dochi-remote",
            profile: profile
        )

        XCTAssertTrue(command.hasPrefix("ssh -p 2222 -i '~/.ssh/id_ed25519' ubuntu@example.com "))
        XCTAssertTrue(command.contains("/opt/homebrew/bin/tmux"))
        XCTAssertTrue(command.contains("attach -t"))
        XCTAssertTrue(command.contains("dochi-remote"))
    }

    func testEscapeAppleScriptString() {
        let escaped = ExternalToolSessionManager.escapeAppleScriptString("echo \"hi\" && cd \\tmp")
        XCTAssertEqual(escaped, "echo \\\"hi\\\" && cd \\\\tmp")
    }

    func testResolveExternalTerminalAppAutoPrefersGhosttyWhenInstalled() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ghosttyPath = tempHome.appendingPathComponent("Applications/Ghostty.app")
        try FileManager.default.createDirectory(at: ghosttyPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let resolved = ExternalToolSessionManager.resolveExternalTerminalApp(
            preference: .auto,
            homeDirectoryPath: tempHome.path,
            systemApplicationsPath: tempHome.appendingPathComponent("SystemApps").path
        )

        XCTAssertEqual(resolved, .ghostty)
    }

    func testResolveExternalTerminalAppAutoFallsBackToTerminal() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let resolved = ExternalToolSessionManager.resolveExternalTerminalApp(
            preference: .auto,
            homeDirectoryPath: tempHome.path,
            systemApplicationsPath: tempHome.appendingPathComponent("SystemApps").path
        )

        XCTAssertEqual(resolved, .terminal)
    }

    func testResolveExternalTerminalAppHonorsExplicitPreference() {
        XCTAssertEqual(
            ExternalToolSessionManager.resolveExternalTerminalApp(preference: .terminal),
            .terminal
        )
        XCTAssertEqual(
            ExternalToolSessionManager.resolveExternalTerminalApp(preference: .ghostty),
            .ghostty
        )
    }

    func testShellQuoteEscapesSingleQuotes() {
        let quoted = ExternalToolSessionManager.shellQuote("hello 'quoted' world")
        XCTAssertEqual(quoted, "'hello '\"'\"'quoted'\"'\"' world'")
    }

    func testBuildTerminalAppleScriptArguments() {
        let args = ExternalToolSessionManager.buildTerminalAppleScriptArguments(command: "echo \"hi\"")

        XCTAssertEqual(args.first, "/usr/bin/osascript")
        XCTAssertTrue(args.joined(separator: " ").contains("tell application \"Terminal\" to activate"))
        XCTAssertTrue(args.joined(separator: " ").contains("do script"))
    }

    func testBuildGhosttyOpenArguments() {
        let args = ExternalToolSessionManager.buildGhosttyOpenArguments(
            command: "'/usr/bin/tmux' attach -t 'dochi-test'",
            shellPath: "/bin/zsh"
        )

        XCTAssertEqual(
            args,
            [
                "/usr/bin/open",
                "-na", "Ghostty.app",
                "--args",
                "-e", "/bin/zsh",
                "-lc", "'/usr/bin/tmux' attach -t 'dochi-test'"
            ]
        )
    }
}

// MARK: - ExternalToolSettings Tests

final class ExternalToolSettingsTests: XCTestCase {

    @MainActor
    func testDefaultSettings() {
        let defaults = UserDefaults.standard
        let keys = [
            "externalToolEnabled",
            "externalToolHealthCheckIntervalSeconds",
            "externalToolOutputCaptureLines",
            "externalToolAutoRestart",
            "externalToolTmuxPath",
            "externalToolSessionPrefix",
            "externalToolTerminalApp"
        ]
        let previous = keys.reduce(into: [String: Any?]()) { dict, key in
            dict[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        defer {
            for key in keys {
                if let value = previous[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let settings = AppSettings()
        XCTAssertTrue(settings.externalToolEnabled)
        XCTAssertEqual(settings.externalToolHealthCheckIntervalSeconds, 30)
        XCTAssertEqual(settings.externalToolOutputCaptureLines, 100)
        XCTAssertFalse(settings.externalToolAutoRestart)
        XCTAssertEqual(settings.externalToolTmuxPath, "/usr/bin/tmux")
        XCTAssertEqual(settings.externalToolSessionPrefix, "dochi-")
        XCTAssertEqual(settings.externalToolTerminalApp, ExternalTerminalApp.auto.rawValue)
    }
}

// MARK: - ExternalToolSettingsSection Tests

final class ExternalToolSettingsSectionTests: XCTestCase {

    func testExternalToolSectionExists() {
        let section = SettingsSection.externalTool
        XCTAssertEqual(section.rawValue, "external-tool")
        XCTAssertEqual(section.title, "외부 도구")
        XCTAssertEqual(section.icon, "hammer")
        XCTAssertEqual(section.group, .development)
    }

    func testExternalToolSearchKeywords() {
        let section = SettingsSection.externalTool
        XCTAssertTrue(section.matches(query: "tmux"))
        XCTAssertTrue(section.matches(query: "Claude Code"))
        XCTAssertTrue(section.matches(query: "aider"))
        XCTAssertTrue(section.matches(query: "외부"))
    }

    func testDevelopmentGroupContainsExternalTool() {
        let devSections = SettingsSectionGroup.development.sections
        XCTAssertTrue(devSections.contains(.terminal))
        XCTAssertTrue(devSections.contains(.externalTool))
        XCTAssertEqual(devSections.count, 2)
    }
}

// MARK: - CommandPalette ExternalTool Items Tests

final class CommandPaletteExternalToolTests: XCTestCase {

    func testExternalToolPaletteItemsExist() {
        let items = CommandPaletteRegistry.staticItems
        XCTAssertNotNil(items.first { $0.id == "external-tool-dashboard" })
        XCTAssertNotNil(items.first { $0.id == "external-tool-healthcheck" })
        XCTAssertNotNil(items.first { $0.id == "settings.open.external-tool" })
    }

    func testExternalToolDashboardItem() {
        let item = CommandPaletteRegistry.staticItems.first { $0.id == "external-tool-dashboard" }
        XCTAssertEqual(item?.title, "외부 도구 대시보드")
        XCTAssertEqual(item?.category, .tool)
    }
}
