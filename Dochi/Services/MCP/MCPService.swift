import Foundation
import Logging
import MCP
import os

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

// MARK: - Models

struct MCPToolInfo: Sendable {
    let serverName: String
    let name: String
    let description: String
    nonisolated(unsafe) let inputSchema: [String: Any]
}

struct MCPToolResult: Sendable {
    let content: String
    let isError: Bool
}

// MARK: - Errors

enum MCPServiceError: Error, LocalizedError, Sendable {
    case serverNotFound
    case notConnected
    case connectionFailed(String)
    case toolNotFound
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverNotFound:
            "MCP 서버를 찾을 수 없습니다."
        case .notConnected:
            "MCP 서버에 연결되어 있지 않습니다."
        case .connectionFailed(let reason):
            "MCP 서버 연결 실패: \(reason)"
        case .toolNotFound:
            "MCP 도구를 찾을 수 없습니다."
        case .executionFailed(let reason):
            "MCP 도구 실행 실패: \(reason)"
        }
    }
}

// MARK: - Connection State

enum MCPConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Server Connection

/// Holds the active connection state for a single MCP server.
private struct ServerConnection {
    let client: Client
    let process: Process
    var tools: [Tool] = []
    var state: MCPConnectionState = .disconnected
}

// MARK: - Process-based Stdio Transport

/// A Transport adapter that launches a subprocess and communicates via its stdin/stdout pipes.
/// The MCP SDK's StdioTransport reads from raw FileDescriptors, so we create pipes,
/// attach them to the Process, and hand the file descriptors to StdioTransport.
private actor ProcessStdioTransport: Transport {
    let logger: Logging.Logger
    private let process: Process
    private let inner: StdioTransport
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private var cachedStream: AsyncThrowingStream<Data, Swift.Error>?

    init(
        command: String,
        arguments: [String],
        environment: [String: String],
        logger: Logging.Logger? = nil
    ) {
        self.logger = logger ?? Logging.Logger(
            label: "mcp.transport.process",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )

        let proc = Process()
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }

        let executablePath = Self.resolveExecutablePath(command: command, environment: env) ?? command
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        // Suppress stderr to avoid polluting our stdout stream
        proc.standardError = FileHandle.nullDevice

        self.process = proc
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe

        // StdioTransport reads from input and writes to output.
        // From the client's perspective:
        //   - input = read from server's stdout (what the server writes)
        //   - output = write to server's stdin (what we send to server)
        let readFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let writeFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        self.inner = StdioTransport(input: readFD, output: writeFD, logger: self.logger)
    }

    private static func resolveExecutablePath(command: String, environment: [String: String]) -> String? {
        let expanded = NSString(string: command).expandingTildeInPath

        // Absolute path or relative path with slash
        if expanded.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
        }

        let pathEnv = environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathEnv.split(separator: ":") {
            let candidate = String(directory) + "/" + expanded
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        let home = NSHomeDirectory()
        let fallbackDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
        ]
        for directory in fallbackDirectories {
            let candidate = directory + "/" + expanded
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        if let shellResolved = resolveExecutableUsingLoginShell(expanded) {
            return shellResolved
        }

        return nil
    }

    private static func resolveExecutableUsingLoginShell(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(shellEscape(command))"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty else {
            return nil
        }
        return output
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func connect() async throws {
        // Launch the subprocess
        do {
            try process.run()
            logger.info(
                "MCP server process launched",
                metadata: [
                    "pid": "\(process.processIdentifier)",
                    "command": "\(process.executableURL?.path ?? "unknown")",
                ]
            )
        } catch {
            throw MCPError.transportError(error)
        }

        // Connect the inner stdio transport
        try await inner.connect()

        // Cache the receive stream from the inner transport.
        // This is needed because inner.receive() is actor-isolated on a different actor,
        // but our receive() must be synchronous per the Transport protocol.
        cachedStream = await inner.receive()
    }

    func disconnect() async {
        await inner.disconnect()

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            logger.info(
                "MCP server process terminated",
                metadata: ["pid": "\(process.processIdentifier)"]
            )
        }
    }

    func send(_ data: Data) async throws {
        try await inner.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        if let stream = cachedStream {
            return stream
        }
        // Fallback: return an empty stream if connect() was not called
        return AsyncThrowingStream { $0.finish() }
    }

    /// Returns the underlying Process for state tracking.
    var underlyingProcess: Process { process }
}

// MARK: - MCPService

@MainActor
final class MCPService: MCPServiceProtocol {

    // MARK: - Storage

    /// All configured servers (connected or not).
    private var configs: [UUID: MCPServerConfig] = [:]

    /// Active connections keyed by server ID.
    private var connections: [UUID: ServerConnection] = [:]

    /// Last known state per server ID (including disconnected / error states without active connection).
    private var states: [UUID: MCPConnectionState] = [:]

    /// Maps tool name -> server ID for routing callTool requests.
    private var toolServerMap: [String: UUID] = [:]

    /// Background health monitor task.
    private var healthMonitorTask: Task<Void, Never>?

    private let healthCheckIntervalNs: UInt64

    // MARK: - Init

    init(healthCheckIntervalSeconds: UInt64 = 8) {
        self.healthCheckIntervalNs = max(1, healthCheckIntervalSeconds) * 1_000_000_000
        startHealthMonitor()
    }

    deinit {
        healthMonitorTask?.cancel()
    }

    // MARK: - Server Management

    func addServer(config: MCPServerConfig) {
        configs[config.id] = config
        states[config.id] = .disconnected
        Log.mcp.info("Server added: \(config.name) (id: \(config.id))")
    }

    func removeServer(id: UUID) {
        // Disconnect first if connected
        if connections[id] != nil {
            disconnect(serverId: id)
        }
        let name = configs[id]?.name ?? "unknown"
        configs.removeValue(forKey: id)
        states.removeValue(forKey: id)
        Log.mcp.info("Server removed: \(name) (id: \(id))")
    }

    func updateServer(config: MCPServerConfig) async throws {
        let wasConnected = connections[config.id] != nil
        removeServer(id: config.id)
        addServer(config: config)

        if config.isEnabled && wasConnected {
            try await connect(serverId: config.id)
        }
        Log.mcp.info("Server updated: \(config.name) (id: \(config.id))")
    }

    func connect(serverId: UUID) async throws {
        guard let config = configs[serverId] else {
            Log.mcp.error("Connect failed: server not found (id: \(serverId))")
            throw MCPServiceError.serverNotFound
        }

        guard config.isEnabled else {
            Log.mcp.warning("Connect skipped: server '\(config.name)' is disabled")
            throw MCPServiceError.connectionFailed("Server is disabled")
        }

        // If already connected, disconnect first
        if connections[serverId] != nil {
            disconnect(serverId: serverId)
        }

        Log.mcp.info("Connecting to server: \(config.name)")
        updateState(serverId: serverId, state: .connecting)

        do {
            let transport = ProcessStdioTransport(
                command: config.command,
                arguments: config.arguments,
                environment: config.environment
            )

            let client = Client(name: "dochi", version: "1.0")

            // connect() performs initialize automatically in this SDK version
            let initResult = try await client.connect(transport: transport)

            Log.mcp.info(
                "Connected to server: \(config.name), protocol: \(initResult.protocolVersion)"
            )

            let process = await transport.underlyingProcess

            var conn = ServerConnection(
                client: client,
                process: process,
                state: .connected
            )

            // Discover tools
            let discoveredTools = try await discoverTools(client: client)
            conn.tools = discoveredTools

            connections[serverId] = conn
            updateState(serverId: serverId, state: .connected)

            // Register tools in the routing map
            for tool in discoveredTools {
                toolServerMap[tool.name] = serverId
                Log.mcp.debug("Registered tool: \(tool.name) from server: \(config.name)")
            }

            Log.mcp.info(
                "Server '\(config.name)' ready with \(discoveredTools.count) tool(s)"
            )

        } catch let error as MCPServiceError {
            let message = error.errorDescription ?? "Unknown error"
            updateState(serverId: serverId, state: .error(message))
            Log.mcp.error("Connection failed for '\(config.name)': \(message)")
            throw error
        } catch {
            let message = error.localizedDescription
            updateState(serverId: serverId, state: .error(message))
            Log.mcp.error("Connection failed for '\(config.name)': \(message)")
            throw MCPServiceError.connectionFailed(message)
        }
    }

    func disconnect(serverId: UUID) {
        guard let conn = connections[serverId] else { return }

        let name = configs[serverId]?.name ?? "unknown"
        Log.mcp.info("Disconnecting from server: \(name)")

        // Remove tool registrations for this server
        for tool in conn.tools {
            toolServerMap.removeValue(forKey: tool.name)
        }

        // Disconnect the client (fire and forget since disconnect is async on actor)
        Task {
            await conn.client.disconnect()
        }

        connections.removeValue(forKey: serverId)
        updateState(serverId: serverId, state: .disconnected)
        Log.mcp.info("Disconnected from server: \(name)")
    }

    func disconnectAll() {
        let serverIds = Array(connections.keys)
        for serverId in serverIds {
            disconnect(serverId: serverId)
        }
        Log.mcp.info("All MCP servers disconnected")
    }

    // MARK: - Query

    func listServers() -> [MCPServerConfig] {
        return configs.values.sorted { $0.name < $1.name }
    }

    func getServer(id: UUID) -> MCPServerConfig? {
        return configs[id]
    }

    // MARK: - Tools

    func listTools() -> [MCPToolInfo] {
        var result: [MCPToolInfo] = []
        for (serverId, conn) in connections {
            let serverName = configs[serverId]?.name ?? "unknown"
            for tool in conn.tools {
                let info = MCPToolInfo(
                    serverName: serverName,
                    name: tool.name,
                    description: tool.description ?? "",
                    inputSchema: valueToDict(tool.inputSchema)
                )
                result.append(info)
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let serverId = toolServerMap[name] else {
            Log.mcp.error("Tool not found: \(name)")
            throw MCPServiceError.toolNotFound
        }

        let healthy = await ensureServerHealthy(
            serverId: serverId,
            reason: "server unavailable before tool call"
        )
        guard healthy else {
            Log.mcp.error("Server is unavailable for tool: \(name)")
            throw MCPServiceError.notConnected
        }

        guard let conn = connections[serverId] else {
            Log.mcp.error("Server not connected for tool: \(name)")
            throw MCPServiceError.notConnected
        }

        let serverName = configs[serverId]?.name ?? "unknown"
        Log.mcp.info("Calling tool '\(name)' on server '\(serverName)'")

        // Convert [String: Any] arguments to [String: Value]
        let valueArgs = convertToValueDict(arguments)

        do {
            return try await executeToolCall(
                on: conn.client,
                toolName: name,
                arguments: valueArgs
            )
        } catch {
            let shouldRecover = shouldAttemptReconnect(after: error)
                || !(connections[serverId]?.process.isRunning ?? false)

            guard shouldRecover else {
                let message = error.localizedDescription
                Log.mcp.error("Tool execution failed for '\(name)': \(message)")
                throw MCPServiceError.executionFailed(message)
            }

            let recovered = await recoverServerConnection(
                serverId: serverId,
                reason: "tool call transport failure: \(error.localizedDescription)"
            )
            guard recovered, let recoveredConn = connections[serverId] else {
                let message = error.localizedDescription
                Log.mcp.error("Recovery failed for '\(name)': \(message)")
                throw MCPServiceError.executionFailed(message)
            }

            do {
                return try await executeToolCall(
                    on: recoveredConn.client,
                    toolName: name,
                    arguments: valueArgs
                )
            } catch {
                let message = error.localizedDescription
                Log.mcp.error("Tool execution retry failed for '\(name)': \(message)")
                throw MCPServiceError.executionFailed(message)
            }
        }
    }

    // MARK: - Connection State (Internal)

    /// Returns the connection state for a given server.
    func connectionState(for serverId: UUID) -> MCPConnectionState {
        states[serverId] ?? .disconnected
    }

    // MARK: - Private Helpers

    private func updateState(serverId: UUID, state: MCPConnectionState) {
        states[serverId] = state
        if connections[serverId] != nil {
            connections[serverId]?.state = state
        }
        switch state {
        case .disconnected:
            Log.mcp.debug("State -> disconnected (server: \(serverId))")
        case .connecting:
            Log.mcp.debug("State -> connecting (server: \(serverId))")
        case .connected:
            Log.mcp.debug("State -> connected (server: \(serverId))")
        case .error(let msg):
            Log.mcp.debug("State -> error: \(msg) (server: \(serverId))")
        }
    }

    private func executeToolCall(
        on client: Client,
        toolName: String,
        arguments: [String: Value]
    ) async throws -> MCPToolResult {
        let result = try await client.callTool(
            name: toolName,
            arguments: arguments
        )

        let contentText = result.content.map { extractText(from: $0) }.joined(separator: "\n")
        let isError = result.isError ?? false

        if isError {
            Log.mcp.warning("Tool '\(toolName)' returned error: \(contentText)")
        } else {
            Log.mcp.debug("Tool '\(toolName)' completed successfully")
        }

        return MCPToolResult(content: contentText, isError: isError)
    }

    private func startHealthMonitor() {
        guard healthMonitorTask == nil else { return }

        healthMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self.healthCheckIntervalNs)
                } catch {
                    break
                }
                await self.checkConnectionHealth()
            }
        }
    }

    private func checkConnectionHealth() async {
        let disconnectedServerIds = connections
            .filter { !$0.value.process.isRunning }
            .map(\.key)

        for serverId in disconnectedServerIds {
            _ = await recoverServerConnection(
                serverId: serverId,
                reason: "detected dead MCP process"
            )
        }
    }

    private func ensureServerHealthy(serverId: UUID, reason: String) async -> Bool {
        guard let conn = connections[serverId] else {
            return await recoverServerConnection(serverId: serverId, reason: reason)
        }

        guard conn.process.isRunning else {
            return await recoverServerConnection(serverId: serverId, reason: reason)
        }

        return true
    }

    private func recoverServerConnection(serverId: UUID, reason: String) async -> Bool {
        cleanupConnection(serverId: serverId, reason: reason)

        guard let config = configs[serverId] else {
            Log.mcp.warning("Recovery skipped: missing config for server \(serverId)")
            return false
        }
        guard config.isEnabled else {
            Log.mcp.warning("Recovery skipped: server '\(config.name)' is disabled")
            return false
        }

        do {
            try await connect(serverId: serverId)
            Log.mcp.info("Recovered server connection: \(config.name)")
            return true
        } catch {
            Log.mcp.error("Recovery failed for '\(config.name)': \(error.localizedDescription)")
            return false
        }
    }

    private func cleanupConnection(serverId: UUID, reason: String) {
        guard let conn = connections[serverId] else {
            updateState(serverId: serverId, state: .error(reason))
            return
        }

        for tool in conn.tools {
            toolServerMap.removeValue(forKey: tool.name)
        }

        Task {
            await conn.client.disconnect()
        }
        connections.removeValue(forKey: serverId)
        updateState(serverId: serverId, state: .error(reason))
    }

    private func shouldAttemptReconnect(after error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("transport")
            || message.contains("connection")
            || message.contains("disconnected")
            || message.contains("broken pipe")
            || message.contains("connection reset")
    }

    /// Discovers all tools from a connected MCP client, handling pagination.
    private func discoverTools(client: Client) async throws -> [Tool] {
        var allTools: [Tool] = []
        var cursor: String? = nil

        repeat {
            let result = try await client.listTools(cursor: cursor)
            allTools.append(contentsOf: result.tools)
            cursor = result.nextCursor
        } while cursor != nil

        return allTools
    }

    /// Converts MCP SDK Value to a plain [String: Any] dictionary for the inputSchema.
    private func valueToDict(_ value: Value) -> [String: Any] {
        guard let obj = value.objectValue else { return [:] }
        var result: [String: Any] = [:]
        for (key, val) in obj {
            result[key] = valueToAny(val)
        }
        return result
    }

    /// Converts a single Value to its Any representation.
    private func valueToAny(_ value: Value) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .int(let i):
            return i
        case .double(let d):
            return d
        case .string(let s):
            return s
        case .data(_, let d):
            return d
        case .array(let arr):
            return arr.map { valueToAny($0) }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = valueToAny(val)
            }
            return result
        }
    }

    /// Converts [String: Any] to [String: Value] for the MCP SDK.
    private func convertToValueDict(_ dict: [String: Any]) -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, val) in dict {
            result[key] = anyToValue(val)
        }
        return result
    }

    /// Converts a single Any to its Value representation.
    private func anyToValue(_ value: Any) -> Value {
        switch value {
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(i)
        case let d as Double:
            return .double(d)
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(arr.map { anyToValue($0) })
        case let dict as [String: Any]:
            var obj: [String: Value] = [:]
            for (k, v) in dict {
                obj[k] = anyToValue(v)
            }
            return .object(obj)
        case is NSNull:
            return .null
        default:
            // Best-effort: convert to string
            return .string(String(describing: value))
        }
    }

    /// Extracts text content from a Tool.Content value.
    private func extractText(from content: Tool.Content) -> String {
        switch content {
        case .text(let text):
            return text
        case .image(let data, let mimeType, _):
            return "[image: \(mimeType), \(data.count) bytes]"
        case .audio(let data, let mimeType):
            return "[audio: \(mimeType), \(data.count) bytes]"
        case .resource(let uri, let mimeType, let text):
            if let text {
                return text
            }
            return "[resource: \(uri), \(mimeType)]"
        }
    }
}
