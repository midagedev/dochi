import Foundation

/// 장기 컨텍스트 파일 관리 서비스
/// ~/Library/Application Support/Dochi/context.md 파일을 관리
enum ContextService {
    private static var contextFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dochi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("context.md")
    }

    /// 현재 컨텍스트 내용 읽기
    static func load() -> String {
        (try? String(contentsOf: contextFileURL, encoding: .utf8)) ?? ""
    }

    /// 컨텍스트 전체 덮어쓰기
    static func save(_ content: String) {
        try? content.write(to: contextFileURL, atomically: true, encoding: .utf8)
    }

    /// 컨텍스트에 내용 추가 (줄바꿈 후 append)
    static func append(_ content: String) {
        var current = load()
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        save(current)
    }

    /// 컨텍스트 파일 존재 여부
    static var exists: Bool {
        FileManager.default.fileExists(atPath: contextFileURL.path)
    }

    /// 컨텍스트 파일 경로
    static var path: String {
        contextFileURL.path
    }

    /// 컨텍스트 파일 크기 (바이트)
    static var size: Int {
        (try? FileManager.default.attributesOfItem(atPath: contextFileURL.path)[.size] as? Int) ?? 0
    }
}
