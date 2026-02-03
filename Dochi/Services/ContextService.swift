import Foundation

/// 프롬프트 파일 관리 서비스
/// ~/Library/Application Support/Dochi/ 디렉토리의 md 파일들을 관리
/// - system.md: 페르소나 + 행동 지침 (수동 편집)
/// - memory.md: 사용자 기억 (자동 누적)
enum ContextService {
    private static var baseDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dochi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var systemFileURL: URL {
        baseDir.appendingPathComponent("system.md")
    }

    private static var memoryFileURL: URL {
        baseDir.appendingPathComponent("memory.md")
    }

    // MARK: - System (페르소나 + 행동 지침)

    static func loadSystem() -> String {
        (try? String(contentsOf: systemFileURL, encoding: .utf8)) ?? ""
    }

    static func saveSystem(_ content: String) {
        try? content.write(to: systemFileURL, atomically: true, encoding: .utf8)
    }

    static var systemPath: String {
        systemFileURL.path
    }

    // MARK: - Memory (사용자 기억)

    static func loadMemory() -> String {
        (try? String(contentsOf: memoryFileURL, encoding: .utf8)) ?? ""
    }

    static func saveMemory(_ content: String) {
        try? content.write(to: memoryFileURL, atomically: true, encoding: .utf8)
    }

    static func appendMemory(_ content: String) {
        var current = loadMemory()
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveMemory(current)
    }

    static var memoryPath: String {
        memoryFileURL.path
    }

    static var memorySize: Int {
        (try? FileManager.default.attributesOfItem(atPath: memoryFileURL.path)[.size] as? Int) ?? 0
    }

    // MARK: - Legacy (마이그레이션용)

    /// 기존 context.md → memory.md 마이그레이션
    static func migrateIfNeeded() {
        let oldContextURL = baseDir.appendingPathComponent("context.md")
        let fm = FileManager.default

        // 기존 context.md가 있고 memory.md가 없으면 이동
        if fm.fileExists(atPath: oldContextURL.path) && !fm.fileExists(atPath: memoryFileURL.path) {
            try? fm.moveItem(at: oldContextURL, to: memoryFileURL)
            print("[Dochi] context.md → memory.md 마이그레이션 완료")
        }
    }
}
