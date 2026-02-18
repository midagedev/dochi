import Foundation
import Darwin

final class ControlPlaneTokenManager: @unchecked Sendable {
    private let tokenFileURL: URL
    private let lock = NSLock()
    private var token: String

    init(tokenFileURL: URL = ControlPlaneTokenManager.defaultTokenURL) {
        self.tokenFileURL = tokenFileURL
        self.token = Self.generateToken()
        _ = rotate()
    }

    var tokenFilePath: String {
        tokenFileURL.path
    }

    func currentToken() -> String {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    @discardableResult
    func rotate() -> String {
        let newToken = Self.generateToken()
        lock.lock()
        token = newToken
        lock.unlock()

        do {
            try persist(token: newToken)
        } catch {
            Log.app.error("ControlPlane: 토큰 저장 실패: \(error.localizedDescription)")
        }
        return newToken
    }

    func validate(_ candidate: String?) -> Bool {
        guard let candidate, !candidate.isEmpty else { return false }
        return candidate == currentToken()
    }

    private func persist(token: String) throws {
        let directory = tokenFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(token.utf8).write(to: tokenFileURL, options: .atomic)
        _ = chmod(tokenFileURL.path, mode_t(0o600))
    }

    private static func generateToken() -> String {
        let lhs = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let rhs = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "\(lhs)\(rhs)"
    }

    static var defaultTokenURL: URL {
        LocalControlPlaneService.defaultSocketURL
            .deletingLastPathComponent()
            .appendingPathComponent("control-plane.token")
    }
}
