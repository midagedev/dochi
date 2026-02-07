import Foundation
import os

/// API 키 저장소
/// 개발 중에는 Application Support에 파일로 저장.
/// 배포 시에는 Keychain으로 전환 권장.
final class KeychainService: KeychainServiceProtocol {
    private let fileManager: FileManager
    private let storageDir: URL

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.storageDir = baseDirectory
        } else {
            let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dochi", isDirectory: true)
            self.storageDir = dir
        }
        try? fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    private func fileURL(account: String) -> URL {
        storageDir.appendingPathComponent("key_\(account)")
    }

    func save(account: String, value: String) {
        let url = fileURL(account: account)
        do {
            try value.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("키 저장 실패 \(account, privacy: .public): \(error, privacy: .public)")
        }
    }

    func load(account: String) -> String? {
        let url = fileURL(account: account)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func delete(account: String) {
        let url = fileURL(account: account)
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Log.storage.error("키 삭제 실패 \(account, privacy: .public): \(error, privacy: .public)")
        }
    }
}
