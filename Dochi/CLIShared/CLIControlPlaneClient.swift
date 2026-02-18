import Foundation
import Darwin

enum CLIControlPlaneError: LocalizedError {
    case socketPathTooLong
    case connectFailed(String)
    case requestEncodeFailed
    case responseDecodeFailed
    case responseReadFailed
    case remoteError(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .socketPathTooLong:
            return "Control Plane 소켓 경로가 너무 깁니다."
        case .connectFailed(let reason):
            return "Control Plane 연결 실패: \(reason)"
        case .requestEncodeFailed:
            return "Control Plane 요청 인코딩 실패"
        case .responseDecodeFailed:
            return "Control Plane 응답 디코딩 실패"
        case .responseReadFailed:
            return "Control Plane 응답 읽기 실패"
        case .remoteError(let code, let message):
            return "\(code): \(message)"
        }
    }
}

struct CLIControlPlaneClient {
    let socketURL: URL
    let timeoutSeconds: Int

    init(
        socketURL: URL = CLIControlPlaneClient.defaultSocketURL,
        timeoutSeconds: Int = 3
    ) {
        self.socketURL = socketURL
        self.timeoutSeconds = max(1, timeoutSeconds)
    }

    func call(method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLIControlPlaneError.connectFailed("socket 생성 실패")
        }
        defer {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }

        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        withUnsafePointer(to: &tv) { pointer in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = socketURL.path.utf8CString
        guard pathBytes.count < maxPathLen else {
            throw CLIControlPlaneError.socketPathTooLong
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in pathBytes.enumerated() {
                rawBuffer[index] = UInt8(bitPattern: byte)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw CLIControlPlaneError.connectFailed(String(cString: strerror(errno)))
        }

        let payload: [String: Any] = [
            "request_id": UUID().uuidString,
            "method": method,
            "params": params,
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            throw CLIControlPlaneError.requestEncodeFailed
        }

        var packet = requestData
        packet.append(0x0A)

        try packet.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw CLIControlPlaneError.requestEncodeFailed
            }
            var written = 0
            while written < packet.count {
                let pointer = baseAddress.advanced(by: written)
                let count = write(fd, pointer, packet.count - written)
                if count <= 0 {
                    throw CLIControlPlaneError.connectFailed(String(cString: strerror(errno)))
                }
                written += count
            }
        }

        shutdown(fd, SHUT_WR)

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 {
                throw CLIControlPlaneError.responseReadFailed
            }
            if count == 0 { break }
            received.append(buffer, count: count)
            if received.contains(0x0A) { break }
        }

        guard !received.isEmpty else {
            throw CLIControlPlaneError.responseReadFailed
        }

        let responseData: Data
        if let newlineIndex = received.firstIndex(of: 0x0A) {
            responseData = Data(received.prefix(upTo: newlineIndex))
        } else {
            responseData = received
        }

        guard let responseJSON = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw CLIControlPlaneError.responseDecodeFailed
        }

        let ok = responseJSON["ok"] as? Bool ?? false
        if ok {
            return responseJSON["result"] as? [String: Any] ?? [:]
        }

        let error = responseJSON["error"] as? [String: Any]
        let code = error?["code"] as? String ?? "unknown_error"
        let message = error?["message"] as? String ?? "unknown"
        throw CLIControlPlaneError.remoteError(code: code, message: message)
    }

    static var defaultSocketURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi/run/dochi.sock")
    }
}
