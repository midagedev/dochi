import Foundation
import os

/// Manages the agent runtime sidecar process lifecycle.
///
/// Responsibilities:
/// - Launch/terminate the Node.js runtime as a child process
/// - Communicate via JSON-RPC 2.0 over Unix Domain Socket
/// - Health polling every 5 seconds
/// - Exponential backoff restart on crash (1s, 2s, 4s, 8s, max 30s, max 5 retries)
@MainActor
final class RuntimeBridgeService: RuntimeBridgeProtocol {
    // MARK: - State

    private(set) var runtimeState: RuntimeState = .notStarted

    // MARK: - Configuration

    private let socketPath: String
    private let runtimeExecutablePath: String
    private let maxRetries = 5
    private let maxBackoffSeconds: Double = 30.0
    private let healthPollIntervalSeconds: Double = 5.0

    // MARK: - Internal State

    private var process: Process?
    private var connection: RuntimeUDSConnection?
    private var healthPollTask: Task<Void, Never>?
    private var retryCount = 0
    private var nextRequestId = 1

    /// Active session event stream continuations, keyed by sessionId.
    private var sessionContinuations: [String: AsyncThrowingStream<BridgeEvent, Error>.Continuation] = [:]

    /// Handler for tool dispatch requests from the runtime.
    private(set) var toolDispatchHandler: ToolDispatchHandler?

    // MARK: - Init

    init(
        socketPath: String = "/tmp/dochi-runtime.sock",
        runtimeExecutablePath: String? = nil
    ) {
        self.socketPath = socketPath
        // Default: look for runtime in the app bundle's Resources, fallback to repo path
        if let path = runtimeExecutablePath {
            self.runtimeExecutablePath = path
        } else {
            let bundlePath = Bundle.main.resourcePath ?? ""
            let bundleRuntime = "\(bundlePath)/dochi-agent-runtime/dist/index.js"
            if FileManager.default.fileExists(atPath: bundleRuntime) {
                self.runtimeExecutablePath = bundleRuntime
            } else {
                // Development fallback
                self.runtimeExecutablePath = "\(bundlePath)/../../../dochi-agent-runtime/dist/index.js"
            }
        }
    }

    // MARK: - RuntimeBridgeProtocol

    func startRuntime() async throws {
        guard runtimeState == .notStarted || runtimeState == .error else {
            Log.runtime.warning("startRuntime called in state: \(self.runtimeState.rawValue)")
            return
        }

        runtimeState = .starting
        retryCount = 0

        try await launchProcess()
    }

    func stopRuntime() async {
        Log.runtime.info("Stopping runtime...")
        healthPollTask?.cancel()
        healthPollTask = nil

        // Try graceful shutdown via RPC
        if let conn = connection {
            do {
                let request = makeRequest(method: "runtime.shutdown")
                _ = try await conn.send(request)
            } catch {
                Log.runtime.debug("Graceful shutdown RPC failed: \(error.localizedDescription)")
            }
        }

        // Terminate process
        if let proc = process, proc.isRunning {
            proc.terminate()
            // Give it a moment to exit
            try? await Task.sleep(for: .milliseconds(500))
            if proc.isRunning {
                proc.interrupt()
            }
        }

        // Finish all active session streams
        for (_, continuation) in sessionContinuations {
            continuation.finish(throwing: RuntimeBridgeError.connectionClosed)
        }
        sessionContinuations.removeAll()

        connection?.close()
        connection = nil
        process = nil
        runtimeState = .notStarted
        Log.runtime.info("Runtime stopped")
    }

    func health() async throws -> RuntimeHealthResponse {
        guard let conn = connection else {
            throw RuntimeBridgeError.notConnected
        }

        let request = makeRequest(method: "runtime.health")
        let response = try await conn.send(request)

        guard let result = response.result else {
            if let err = response.error {
                throw RuntimeBridgeError.rpcError(code: err.code, message: err.message)
            }
            throw RuntimeBridgeError.invalidResponse
        }

        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(RuntimeHealthResponse.self, from: data)
    }

    // MARK: - Tool Dispatch

    /// Configure the tool dispatch handler with the app's tool service.
    func configureToolDispatch(toolService: any BuiltInToolServiceProtocol) {
        let handler = ToolDispatchHandler(toolService: toolService)
        if let connection {
            handler.setConnection(connection)
        }
        self.toolDispatchHandler = handler
    }

    // MARK: - Session Management

    func openSession(params: SessionOpenParams) async throws -> SessionOpenResult {
        let rpcParams: [String: AnyCodableValue] = [
            "workspaceId": .string(params.workspaceId),
            "agentId": .string(params.agentId),
            "conversationId": .string(params.conversationId),
            "userId": .string(params.userId),
            "deviceId": .string(params.deviceId ?? ""),
            "sdkSessionId": params.sdkSessionId.map { .string($0) } ?? .null,
        ]
        return try await sendRpc(method: "session.open", params: rpcParams)
    }

    func runSession(params: SessionRunParams) -> AsyncThrowingStream<BridgeEvent, Error> {
        let sessionId = params.sessionId
        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                self.sessionContinuations[sessionId] = continuation
                continuation.onTermination = { @Sendable _ in
                    Task { @MainActor [weak self] in
                        self?.sessionContinuations.removeValue(forKey: sessionId)
                    }
                }

                do {
                    let rpcParams: [String: AnyCodableValue] = [
                        "sessionId": .string(params.sessionId),
                        "input": .string(params.input),
                        "contextSnapshotRef": params.contextSnapshotRef.map { .string($0) } ?? .null,
                        "permissionMode": params.permissionMode.map { .string($0) } ?? .null,
                    ]
                    let _: SessionRunResult = try await self.sendRpc(method: "session.run", params: rpcParams)
                    // Ack received — events will arrive via UDS notifications
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func interruptSession(sessionId: String) async throws -> SessionInterruptResult {
        let rpcParams: [String: AnyCodableValue] = [
            "sessionId": .string(sessionId),
        ]
        let result: SessionInterruptResult = try await sendRpc(method: "session.interrupt", params: rpcParams)

        // Finish any active stream for this session
        if let continuation = sessionContinuations.removeValue(forKey: sessionId) {
            continuation.finish()
        }
        return result
    }

    func closeSession(sessionId: String) async throws -> SessionCloseResult {
        let rpcParams: [String: AnyCodableValue] = [
            "sessionId": .string(sessionId),
        ]
        let result: SessionCloseResult = try await sendRpc(method: "session.close", params: rpcParams)

        if let continuation = sessionContinuations.removeValue(forKey: sessionId) {
            continuation.finish()
        }
        return result
    }

    // MARK: - Process Management

    private func launchProcess() async throws {
        Log.runtime.info("Launching runtime process: \(self.runtimeExecutablePath)")

        // Clean up stale socket
        let fm = FileManager.default
        if fm.fileExists(atPath: socketPath) {
            try? fm.removeItem(atPath: socketPath)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/local/bin/node")

        // Try common Node.js paths
        let nodePaths = ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
        for path in nodePaths {
            if fm.fileExists(atPath: path) {
                proc.executableURL = URL(fileURLWithPath: path)
                break
            }
        }

        proc.arguments = [runtimeExecutablePath]
        proc.environment = [
            "DOCHI_RUNTIME_SOCKET": socketPath,
            "NODE_ENV": "production",
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // Monitor stderr for logging
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                Log.runtime.debug("[runtime-stderr] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        // Set up termination handler
        proc.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                self?.handleProcessTermination(exitCode: terminatedProcess.terminationStatus)
            }
        }

        do {
            try proc.run()
        } catch {
            runtimeState = .error
            throw RuntimeBridgeError.launchFailed(error.localizedDescription)
        }

        self.process = proc
        Log.runtime.info("Runtime process launched (PID: \(proc.processIdentifier))")

        // Wait for runtime.ready event on stdout
        try await waitForReady(stdoutPipe: stdoutPipe)

        // Restrict socket file access to current user only (spec §7 보안 경계)
        chmod(socketPath, 0o600)

        // Connect via UDS
        let conn = RuntimeUDSConnection(socketPath: socketPath)
        try await conn.connect()
        self.connection = conn

        // Route incoming notifications to session event streams and tool dispatch
        conn.notificationHandler = { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleNotification(notification)
            }
        }

        // Wire tool dispatch handler to this connection
        toolDispatchHandler?.setConnection(conn)

        // Send initialize
        let initParams: [String: AnyCodableValue] = [
            "runtimeVersion": .string("0.1.0"),
            "configProfile": .string("default"),
        ]
        let initRequest = makeRequest(method: "runtime.initialize", params: initParams)
        let initResponse = try await conn.send(initRequest)

        if let err = initResponse.error {
            throw RuntimeBridgeError.rpcError(code: err.code, message: err.message)
        }

        runtimeState = .ready
        retryCount = 0
        Log.runtime.info("Runtime is ready")

        // Start health polling
        startHealthPolling()
    }

    private func waitForReady(stdoutPipe: Pipe) async throws {
        let guard_ = ReadyGuard()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

                for line in text.components(separatedBy: "\n") {
                    guard !line.isEmpty else { continue }
                    if let jsonData = line.data(using: .utf8),
                       let notification = try? JSONDecoder().decode(JsonRpcNotification.self, from: jsonData),
                       notification.method == "runtime.ready"
                    {
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        if guard_.tryResume() {
                            continuation.resume()
                        }
                        return
                    }
                }
            }

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(for: .seconds(10))
                if guard_.tryResume() {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: RuntimeBridgeError.readyTimeout)
                }
            }
        }
    }

    private func handleProcessTermination(exitCode: Int32) {
        Log.runtime.warning("Runtime process terminated with exit code: \(exitCode)")

        connection?.close()
        connection = nil
        process = nil
        healthPollTask?.cancel()
        healthPollTask = nil

        guard runtimeState != .notStarted else { return }

        if retryCount < maxRetries {
            runtimeState = .recovering
            let delay = backoffDelay(attempt: retryCount)
            retryCount += 1
            Log.runtime.info("Scheduling restart attempt \(self.retryCount)/\(self.maxRetries) in \(delay)s")

            Task {
                try? await Task.sleep(for: .seconds(delay))
                guard self.runtimeState == .recovering else { return }
                do {
                    try await self.launchProcess()
                } catch {
                    Log.runtime.error("Restart failed: \(error.localizedDescription)")
                    self.runtimeState = .error
                }
            }
        } else {
            Log.runtime.error("Max retries (\(self.maxRetries)) exceeded. Runtime in error state.")
            runtimeState = .error
        }
    }

    // MARK: - Health Polling

    private func startHealthPolling() {
        healthPollTask?.cancel()
        healthPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.healthPollIntervalSeconds ?? 5.0))
                guard !Task.isCancelled else { break }

                do {
                    let healthResult = try await self?.health()
                    if healthResult?.alive == true, self?.runtimeState == .degraded {
                        self?.runtimeState = .ready
                        Log.runtime.info("Runtime recovered from degraded state")
                    }
                } catch {
                    if self?.runtimeState == .ready {
                        self?.runtimeState = .degraded
                        Log.runtime.warning("Runtime health check failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Notification Handling

    private func handleNotification(_ notification: JsonRpcNotification) {
        guard notification.method == "bridge.event",
              let params = notification.params else { return }

        // Decode BridgeEvent from notification params
        guard let event = decodeBridgeEvent(from: params) else { return }

        // Route tool.dispatch to the dispatch handler (does not go through session stream)
        if event.eventType == .toolDispatch {
            toolDispatchHandler?.handleDispatch(event: event)
            return
        }

        guard let sessionId = event.sessionId,
              let continuation = sessionContinuations[sessionId] else {
            Log.runtime.debug("Received event for unknown session: \(event.sessionId ?? "nil")")
            return
        }

        continuation.yield(event)

        if event.eventType == .sessionCompleted || event.eventType == .sessionFailed {
            continuation.finish()
            sessionContinuations.removeValue(forKey: sessionId)
        }
    }

    private func decodeBridgeEvent(from params: [String: AnyCodableValue]) -> BridgeEvent? {
        do {
            let data = try JSONEncoder().encode(AnyCodableValue.object(params))
            return try JSONDecoder().decode(BridgeEvent.self, from: data)
        } catch {
            Log.runtime.error("Failed to decode bridge event: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    func backoffDelay(attempt: Int) -> Double {
        min(pow(2.0, Double(attempt)), maxBackoffSeconds)
    }

    private func makeRequest(method: String, params: [String: AnyCodableValue]? = nil) -> JsonRpcRequest {
        let id = nextRequestId
        nextRequestId += 1
        return JsonRpcRequest(id: id, method: method, params: params)
    }

    /// Generic RPC call: send request, decode result as T.
    private func sendRpc<T: Decodable>(method: String, params: [String: AnyCodableValue]? = nil) async throws -> T {
        guard let conn = connection else {
            throw RuntimeBridgeError.notConnected
        }
        let request = makeRequest(method: method, params: params)
        let response = try await conn.send(request)

        guard let result = response.result else {
            if let err = response.error {
                throw RuntimeBridgeError.rpcError(code: err.code, message: err.message)
            }
            throw RuntimeBridgeError.invalidResponse
        }

        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - UDS Connection

/// Manages a Unix Domain Socket connection for JSON-RPC communication.
///
/// Safety invariant for `@unchecked Sendable`:
/// All mutable state (`fileHandle`, `pendingRequests`) is guarded by `lock` (NSLock).
/// `socketPath` is immutable after init. Callers must ensure `send`/`close` are not
/// interleaved without external coordination (currently guaranteed by `@MainActor` on
/// `RuntimeBridgeService`).
/// TODO: Phase 1 — replace with actor to eliminate manual locking.
final class RuntimeUDSConnection: @unchecked Sendable {
    private let socketPath: String
    private var fileHandle: FileHandle?
    private var pendingRequests: [Int: CheckedContinuation<JsonRpcResponse, Error>] = [:]
    private let lock = NSLock()

    /// Called when a JSON-RPC notification (no `id`) arrives from the runtime.
    var notificationHandler: (@Sendable (JsonRpcNotification) -> Void)?

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func connect() async throws {
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw RuntimeBridgeError.connectionFailed("Failed to create socket")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        precondition(pathBytes.count <= maxLen, "Socket path too long")
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, byte) in pathBytes.prefix(maxLen).enumerated() {
                buf[i] = UInt8(bitPattern: byte)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(socket, sockaddrPtr, addrLen)
            }
        }

        guard result == 0 else {
            Darwin.close(socket)
            throw RuntimeBridgeError.connectionFailed("connect() failed: \(errno)")
        }

        let handle = FileHandle(fileDescriptor: socket, closeOnDealloc: true)
        self.fileHandle = handle

        // Start reading responses
        startReading(handle: handle)
    }

    func send(_ request: JsonRpcRequest) async throws -> JsonRpcResponse {
        guard let handle = fileHandle else {
            throw RuntimeBridgeError.notConnected
        }

        let data = try JSONEncoder().encode(request)
        var payload = data
        payload.append(contentsOf: "\n".utf8)

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingRequests[request.id] = continuation
            lock.unlock()

            handle.write(payload)
        }
    }

    func close() {
        fileHandle?.closeFile()
        fileHandle = nil

        lock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()

        for (_, continuation) in pending {
            continuation.resume(throwing: RuntimeBridgeError.connectionClosed)
        }
    }

    private func startReading(handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else {
                self?.close()
                return
            }

            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.components(separatedBy: "\n") {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8)
                else { continue }

                // Try decoding as a response (has `id` field)
                if let response = try? JSONDecoder().decode(JsonRpcResponse.self, from: lineData) {
                    self?.lock.lock()
                    let continuation = self?.pendingRequests.removeValue(forKey: response.id)
                    self?.lock.unlock()
                    continuation?.resume(returning: response)
                    continue
                }

                // Try decoding as a notification (has `method`, no `id`)
                if let notification = try? JSONDecoder().decode(JsonRpcNotification.self, from: lineData) {
                    self?.notificationHandler?(notification)
                }
            }
        }
    }
}

// MARK: - ReadyGuard

/// Thread-safe one-shot guard for continuation resumption.
private final class ReadyGuard: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    /// Returns `true` if this is the first call; subsequent calls return `false`.
    func tryResume() -> Bool {
        state.withLock { resumed in
            if resumed { return false }
            resumed = true
            return true
        }
    }
}

// MARK: - Errors

enum RuntimeBridgeError: LocalizedError {
    case launchFailed(String)
    case readyTimeout
    case connectionFailed(String)
    case notConnected
    case connectionClosed
    case rpcError(code: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): "Runtime launch failed: \(reason)"
        case .readyTimeout: "Runtime did not emit ready event within timeout"
        case .connectionFailed(let reason): "UDS connection failed: \(reason)"
        case .notConnected: "Not connected to runtime"
        case .connectionClosed: "Connection to runtime was closed"
        case .rpcError(let code, let message): "RPC error \(code): \(message)"
        case .invalidResponse: "Invalid response from runtime"
        }
    }
}
