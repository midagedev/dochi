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
}

// MARK: - ExternalToolSettings Tests

final class ExternalToolSettingsTests: XCTestCase {

    @MainActor
    func testDefaultSettings() {
        let settings = AppSettings()
        XCTAssertTrue(settings.externalToolEnabled)
        XCTAssertEqual(settings.externalToolHealthCheckIntervalSeconds, 30)
        XCTAssertEqual(settings.externalToolOutputCaptureLines, 100)
        XCTAssertFalse(settings.externalToolAutoRestart)
        XCTAssertEqual(settings.externalToolTmuxPath, "/usr/bin/tmux")
        XCTAssertEqual(settings.externalToolSessionPrefix, "dochi-")
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
