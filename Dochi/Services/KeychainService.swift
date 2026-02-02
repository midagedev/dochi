import Foundation

/// API 키 저장소
/// 개발 중에는 Application Support에 파일로 저장.
/// 배포 시에는 Keychain으로 전환 권장.
enum KeychainService {
    private static var storageDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dochi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(account: String) -> URL {
        storageDir.appendingPathComponent("key_\(account)")
    }

    static func save(account: String, value: String) {
        let url = fileURL(account: account)
        try? value.write(to: url, atomically: true, encoding: .utf8)
    }

    static func load(account: String) -> String? {
        let url = fileURL(account: account)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func delete(account: String) {
        let url = fileURL(account: account)
        try? FileManager.default.removeItem(at: url)
    }
}
