import Foundation
import Darwin

struct LocalControlPlaneMethodResult: @unchecked Sendable {
    let success: Bool
    let result: [String: Any]
    let errorCode: String?
    let errorMessage: String?

    static func ok(_ result: [String: Any] = [:]) -> LocalControlPlaneMethodResult {
        LocalControlPlaneMethodResult(success: true, result: result, errorCode: nil, errorMessage: nil)
    }

    static func failure(code: String, message: String) -> LocalControlPlaneMethodResult {
        LocalControlPlaneMethodResult(success: false, result: [:], errorCode: code, errorMessage: message)
    }
}

typealias LocalControlPlaneMethodHandler = @Sendable (_ method: String, _ params: [String: Any]) async -> LocalControlPlaneMethodResult

final class LocalControlPlaneService {
    private let socketURL: URL
    private let methodHandler: LocalControlPlaneMethodHandler
    private let authTokenProvider: @Sendable () -> String?
    private let unauthenticatedMethods: Set<String>

    private var listenFD: Int32 = -1
    private var acceptWorkItem: DispatchWorkItem?

    init(
        socketURL: URL = LocalControlPlaneService.defaultSocketURL,
        methodHandler: @escaping LocalControlPlaneMethodHandler,
        authTokenProvider: @escaping @Sendable () -> String? = { nil },
        unauthenticatedMethods: Set<String> = []
    ) {
        self.socketURL = socketURL
        self.methodHandler = methodHandler
        self.authTokenProvider = authTokenProvider
        self.unauthenticatedMethods = unauthenticatedMethods
    }

    deinit {
        stop()
    }

    func start() {
        guard listenFD < 0 else { return }

        let runDir = socketURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        } catch {
            Log.app.error("ControlPlane: run 디렉토리 생성 실패: \(error.localizedDescription)")
            return
        }

        unlink(socketURL.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.app.error("ControlPlane: socket 생성 실패")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = socketURL.path.utf8CString
        guard pathBytes.count < maxPathLen else {
            close(fd)
            Log.app.error("ControlPlane: 소켓 경로가 너무 깁니다")
            return
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in pathBytes.enumerated() {
                rawBuffer[index] = UInt8(bitPattern: byte)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(fd)
            Log.app.error("ControlPlane: bind 실패")
            return
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            close(fd)
            Log.app.error("ControlPlane: listen 실패")
            return
        }

        _ = chmod(self.socketURL.path, mode_t(0o600))
        listenFD = fd

        let serverFD = fd
        let handler = methodHandler
        let authProvider = authTokenProvider
        let bypassMethods = unauthenticatedMethods
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem {
            Self.acceptLoop(
                serverFD: serverFD,
                handler: handler,
                authTokenProvider: authProvider,
                unauthenticatedMethods: bypassMethods,
                shouldStop: { workItem?.isCancelled ?? true }
            )
        }
        acceptWorkItem = workItem
        if let workItem {
            DispatchQueue.global(qos: .utility).async(execute: workItem)
        }

        Log.app.info("ControlPlane started at \(self.socketURL.path)")
    }

    func stop() {
        acceptWorkItem?.cancel()
        acceptWorkItem = nil

        if listenFD >= 0 {
            shutdown(listenFD, SHUT_RDWR)
            close(listenFD)
            listenFD = -1
        }

        unlink(self.socketURL.path)
        Log.app.info("ControlPlane stopped")
    }

    private static func acceptLoop(
        serverFD: Int32,
        handler: @escaping LocalControlPlaneMethodHandler,
        authTokenProvider: @escaping @Sendable () -> String?,
        unauthenticatedMethods: Set<String>,
        shouldStop: @escaping () -> Bool
    ) {
        while !shouldStop() {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                if shouldStop() { break }
                continue
            }

            Task {
                await Self.handleClient(
                    fd: clientFD,
                    handler: handler,
                    authTokenProvider: authTokenProvider,
                    unauthenticatedMethods: unauthenticatedMethods
                )
            }
        }
    }

    private static func handleClient(
        fd: Int32,
        handler: @escaping LocalControlPlaneMethodHandler,
        authTokenProvider: @escaping @Sendable () -> String?,
        unauthenticatedMethods: Set<String>
    ) async {
        defer {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }

        guard let requestData = readRequest(fd: fd) else {
            let response = makeErrorResponse(requestId: nil, code: "invalid_request", message: "요청 본문을 읽을 수 없습니다.")
            writeResponse(fd: fd, payload: response)
            return
        }

        guard let requestJSON = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
            let response = makeErrorResponse(requestId: nil, code: "invalid_json", message: "JSON 파싱 실패")
            writeResponse(fd: fd, payload: response)
            return
        }

        let requestId = (requestJSON["request_id"] as? String)
            ?? (requestJSON["id"] as? String)
            ?? UUID().uuidString

        guard let method = requestJSON["method"] as? String, !method.isEmpty else {
            let response = makeErrorResponse(requestId: requestId, code: "missing_method", message: "method가 필요합니다.")
            writeResponse(fd: fd, payload: response)
            return
        }

        if !unauthenticatedMethods.contains(method),
           let requiredToken = authTokenProvider(),
           !requiredToken.isEmpty {
            let providedToken = (requestJSON["auth_token"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isValidToken = providedToken == requiredToken
            if !isValidToken {
                let response = makeErrorResponse(
                    requestId: requestId,
                    code: "unauthorized",
                    message: "로컬 API 인증에 실패했습니다. Dochi 앱 상태를 확인한 뒤 다시 시도하세요."
                )
                writeResponse(fd: fd, payload: response)
                return
            }
        }

        let params = requestJSON["params"] as? [String: Any] ?? [:]
        let result = await handler(method, params)

        let response: [String: Any]
        if result.success {
            response = [
                "request_id": requestId,
                "ok": true,
                "result": result.result,
            ]
        } else {
            response = [
                "request_id": requestId,
                "ok": false,
                "error": [
                    "code": result.errorCode ?? "unknown",
                    "message": result.errorMessage ?? "unknown error",
                ]
            ]
        }

        writeResponse(fd: fd, payload: response)
    }

    private static func readRequest(fd: Int32) -> Data? {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            received.append(buffer, count: count)
            if received.contains(0x0A) { break } // newline-delimited request
            if received.count > 1_048_576 { break }
        }

        guard !received.isEmpty else { return nil }
        if let newlineIndex = received.firstIndex(of: 0x0A) {
            return received.prefix(upTo: newlineIndex)
        }
        return received
    }

    private static func writeResponse(fd: Int32, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }

        var packet = data
        packet.append(0x0A)

        packet.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesWritten = 0
            while bytesWritten < packet.count {
                let pointer = baseAddress.advanced(by: bytesWritten)
                let writeCount = write(fd, pointer, packet.count - bytesWritten)
                if writeCount <= 0 { break }
                bytesWritten += writeCount
            }
        }
    }

    private static func makeErrorResponse(requestId: String?, code: String, message: String) -> [String: Any] {
        [
            "request_id": requestId ?? UUID().uuidString,
            "ok": false,
            "error": [
                "code": code,
                "message": message,
            ]
        ]
    }

    static var defaultSocketURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi/run/dochi.sock")
    }
}
