import CryptoKit
import Foundation

struct ProjectContext: Codable, Sendable, Identifiable {
    let id: String
    let repoRootPath: String
    var displayName: String
    var defaultBranch: String?
    var lastScannedHeadSHA: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String? = nil,
        repoRootPath: String,
        displayName: String? = nil,
        defaultBranch: String? = nil,
        lastScannedHeadSHA: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let normalizedPath = Self.normalizePath(repoRootPath)
        self.id = id ?? Self.makeID(repoRootPath: normalizedPath)
        self.repoRootPath = normalizedPath
        self.displayName = displayName ?? URL(fileURLWithPath: normalizedPath).lastPathComponent
        self.defaultBranch = defaultBranch
        self.lastScannedHeadSHA = lastScannedHeadSHA
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func normalizePath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    static func makeID(repoRootPath: String) -> String {
        let digest = SHA256.hash(data: Data(repoRootPath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}
