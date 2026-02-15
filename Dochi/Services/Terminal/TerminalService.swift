import Foundation
import os

/// Process/Pipe 기반 쉘 세션 관리 서비스
@MainActor
@Observable
final class TerminalService: TerminalServiceProtocol {
    // MARK: - State

    private(set) var sessions: [TerminalSession] = []
    var activeSessionId: UUID?
    let maxSessions: Int

    // MARK: - Callbacks

    var onOutputUpdate: ((UUID) -> Void)?
    var onSessionClosed: ((UUID) -> Void)?

    // MARK: - Internal

    private var processes: [UUID: Process] = [:]
    private var inputPipes: [UUID: Pipe] = [:]
    private var readTasks: [UUID: [Task<Void, Never>]] = [:]
    private let maxBufferLines: Int
    private let defaultShellPath: String
    private let commandTimeout: Int

    // MARK: - Init

    init(
        maxSessions: Int = 8,
        maxBufferLines: Int = 10000,
        defaultShellPath: String = "/bin/zsh",
        commandTimeout: Int = 300
    ) {
        self.maxSessions = maxSessions
        self.maxBufferLines = maxBufferLines
        self.defaultShellPath = defaultShellPath
        self.commandTimeout = commandTimeout
        Log.app.info("TerminalService initialized (maxSessions: \(maxSessions))")
    }

    deinit {
        // Processes need to be cleaned up; since this is @MainActor, just mark
        // the intent — actual cleanup happens in closeAllSessions()
    }

    // MARK: - Session Management

    @discardableResult
    func createSession(name: String? = nil, shellPath: String? = nil) -> UUID {
        let currentMax = self.maxSessions
        guard sessions.count < currentMax else {
            Log.app.warning("TerminalService: max sessions reached (\(currentMax))")
            return sessions.last?.id ?? UUID()
        }

        let sessionId = UUID()
        let sessionName = name ?? "터미널 \(sessions.count + 1)"
        let shell = shellPath ?? defaultShellPath
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        var session = TerminalSession(
            id: sessionId,
            name: sessionName,
            currentDirectory: homeDir,
            isRunning: true
        )

        // Welcome message
        let welcomeLine = TerminalOutputLine(
            text: "[\(sessionName)] 쉘 시작됨 — \(shell)",
            type: .system
        )
        session.outputLines.append(welcomeLine)
        sessions.append(session)
        activeSessionId = sessionId

        // Start shell process
        startProcess(sessionId: sessionId, shellPath: shell, workingDirectory: homeDir)

        Log.app.info("Terminal session created: \(sessionId) (\(sessionName))")
        return sessionId
    }

    func closeSession(id: UUID) {
        terminateProcess(id: id)

        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions.remove(at: index)
        }

        if activeSessionId == id {
            activeSessionId = sessions.last?.id
        }

        onSessionClosed?(id)
        Log.app.info("Terminal session closed: \(id)")
    }

    func closeAllSessions() {
        let ids = sessions.map(\.id)
        for id in ids {
            terminateProcess(id: id)
        }
        sessions.removeAll()
        activeSessionId = nil
    }

    // MARK: - Command Execution

    func executeCommand(_ command: String, in sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        guard let inputPipe = inputPipes[sessionId] else { return }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add to history
        sessions[index].commandHistory.append(trimmed)
        sessions[index].historyIndex = nil

        // Write command to stdin
        let commandData = "\(trimmed)\n".data(using: .utf8)!
        inputPipe.fileHandleForWriting.write(commandData)

        Log.app.debug("Terminal command sent to \(sessionId): \(trimmed)")
    }

    func clearOutput(for sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].outputLines.removeAll()
        let clearLine = TerminalOutputLine(text: "출력이 지워졌습니다.", type: .system)
        sessions[index].outputLines.append(clearLine)
        onOutputUpdate?(sessionId)
        Log.app.debug("Terminal output cleared for \(sessionId)")
    }

    func interrupt(sessionId: UUID) {
        guard let process = processes[sessionId], process.isRunning else { return }
        process.interrupt()
        Log.app.debug("Terminal process interrupted for \(sessionId)")
    }

    // MARK: - Process Management

    private func startProcess(sessionId: UUID, shellPath: String, workingDirectory: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l"]  // login shell
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        // Set environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["LANG"] = "ko_KR.UTF-8"
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        processes[sessionId] = process
        inputPipes[sessionId] = stdinPipe

        // Read stdout asynchronously
        let stdoutTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.readOutput(
                from: stdoutPipe.fileHandleForReading,
                sessionId: sessionId,
                type: .stdout
            )
        }

        // Read stderr asynchronously
        let stderrTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.readOutput(
                from: stderrPipe.fileHandleForReading,
                sessionId: sessionId,
                type: .stderr
            )
        }

        readTasks[sessionId] = [stdoutTask, stderrTask]

        // Process termination handler
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleProcessTermination(sessionId: sessionId)
            }
        }

        do {
            try process.run()
            Log.app.info("Terminal process started for \(sessionId)")
        } catch {
            Log.app.error("Failed to start terminal process: \(error.localizedDescription)")
            appendOutputLine(
                sessionId: sessionId,
                text: "쉘 시작 실패: \(error.localizedDescription)",
                type: .system
            )
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[index].isRunning = false
            }
        }
    }

    private nonisolated func readOutput(
        from fileHandle: FileHandle,
        sessionId: UUID,
        type: OutputType
    ) async {
        while !Task.isCancelled {
            let data = fileHandle.availableData
            if data.isEmpty {
                break  // EOF
            }

            if let text = String(data: data, encoding: .utf8) {
                let lines = text.components(separatedBy: "\n")
                for line in lines where !line.isEmpty {
                    await MainActor.run {
                        self.appendOutputLine(sessionId: sessionId, text: line, type: type)
                    }
                }
            }
        }
    }

    private func appendOutputLine(sessionId: UUID, text: String, type: OutputType) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        let line = TerminalOutputLine(text: text, type: type)
        sessions[index].outputLines.append(line)

        // Trim buffer if needed
        if sessions[index].outputLines.count > maxBufferLines {
            let excess = sessions[index].outputLines.count - maxBufferLines
            sessions[index].outputLines.removeFirst(excess)
        }

        onOutputUpdate?(sessionId)
    }

    private func handleProcessTermination(sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        sessions[index].isRunning = false
        let exitLine = TerminalOutputLine(
            text: "[프로세스 종료됨]",
            type: .system
        )
        sessions[index].outputLines.append(exitLine)

        // Clean up
        processes.removeValue(forKey: sessionId)
        inputPipes.removeValue(forKey: sessionId)
        readTasks[sessionId]?.forEach { $0.cancel() }
        readTasks.removeValue(forKey: sessionId)

        onOutputUpdate?(sessionId)
        Log.app.info("Terminal process terminated for \(sessionId)")
    }

    private func terminateProcess(id: UUID) {
        if let process = processes[id], process.isRunning {
            process.terminate()
        }
        processes.removeValue(forKey: id)
        inputPipes.removeValue(forKey: id)
        readTasks[id]?.forEach { $0.cancel() }
        readTasks.removeValue(forKey: id)
    }

    // MARK: - History Navigation

    func navigateHistory(sessionId: UUID, direction: Int) -> String? {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return nil }
        let history = sessions[index].commandHistory
        guard !history.isEmpty else { return nil }

        var currentIndex = sessions[index].historyIndex

        if direction < 0 {
            // Up — go back in history
            if let idx = currentIndex {
                currentIndex = max(0, idx - 1)
            } else {
                currentIndex = history.count - 1
            }
        } else {
            // Down — go forward in history
            if let idx = currentIndex {
                if idx >= history.count - 1 {
                    currentIndex = nil
                    sessions[index].historyIndex = nil
                    return ""
                } else {
                    currentIndex = idx + 1
                }
            } else {
                return nil
            }
        }

        sessions[index].historyIndex = currentIndex
        if let idx = currentIndex, idx < history.count {
            return history[idx]
        }
        return nil
    }

    // MARK: - LLM Command Support

    func executeLLMCommand(_ command: String, in sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        // Show LLM command in output
        let promptLine = TerminalOutputLine(text: "[LLM] \(command)", type: .llmCommand)
        sessions[index].outputLines.append(promptLine)
        onOutputUpdate?(sessionId)

        // Execute via stdin
        executeCommand(command, in: sessionId)
    }

    /// Execute a command in the active session and return the result (for LLM tool use)
    func runCommand(_ command: String, timeout: Int? = nil) async -> (output: String, exitCode: Int32, isError: Bool) {
        let proc = Process()
        let shell = defaultShellPath
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        proc.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            return (output: "실행 실패: \(error.localizedDescription)", exitCode: -1, isError: true)
        }

        let effectiveTimeout = timeout ?? commandTimeout

        return await withCheckedContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(effectiveTimeout))
                if proc.isRunning {
                    proc.terminate()
                }
            }

            Task.detached {
                // Read pipe data BEFORE waitUntilExit to avoid deadlock
                // when output exceeds pipe buffer (64KB)
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                proc.waitUntilExit()
                timeoutTask.cancel()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let output = stdout.isEmpty ? stderr : (stderr.isEmpty ? stdout : stdout + "\n" + stderr)
                let trimmed = String(output.prefix(8000))

                continuation.resume(returning: (
                    output: trimmed,
                    exitCode: proc.terminationStatus,
                    isError: proc.terminationStatus != 0
                ))
            }
        }
    }
}
