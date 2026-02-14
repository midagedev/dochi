import Foundation

// MARK: - Path Validation

private func validatePath(_ path: String) -> (expandedPath: String, error: ToolResult?) {
    guard !path.isEmpty else {
        return ("", ToolResult(toolCallId: "", content: "path 파라미터가 필요합니다.", isError: true))
    }

    let expanded = NSString(string: path).expandingTildeInPath

    // Resolve symlinks and ".." to get the real path for security check
    let resolved = (expanded as NSString).resolvingSymlinksInPath
    let home = NSHomeDirectory()

    guard resolved.hasPrefix(home) || resolved == home else {
        return ("", ToolResult(toolCallId: "", content: "홈 디렉토리 밖의 경로에는 접근할 수 없습니다: \(path)", isError: true))
    }

    return (expanded, nil)
}

private let maxReadSize = 100_000 // 100KB text limit

// MARK: - file.read

@MainActor
final class FileReadTool: BuiltInToolProtocol {
    let name = "file.read"
    let category: ToolCategory = .safe
    let description = "텍스트 파일을 읽어옵니다. 바이너리 파일은 메타데이터만 반환합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "파일 경로"],
            ] as [String: Any],
            "required": ["path"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(toolCallId: "", content: "path 파라미터가 필요합니다.", isError: true)
        }

        let (expanded, error) = validatePath(path)
        if let error { return error }

        let fm = FileManager.default
        guard fm.fileExists(atPath: expanded) else {
            return ToolResult(toolCallId: "", content: "파일을 찾을 수 없습니다: \(path)", isError: true)
        }

        do {
            let attrs = try fm.attributesOfItem(atPath: expanded)
            let size = attrs[.size] as? Int64 ?? 0

            // Check if it's a text file by trying to read as UTF-8
            let data = try Data(contentsOf: URL(fileURLWithPath: expanded))

            guard let text = String(data: data.prefix(maxReadSize), encoding: .utf8) else {
                // Binary file — return metadata only
                let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                let ext = (expanded as NSString).pathExtension
                return ToolResult(toolCallId: "", content: "바이너리 파일입니다.\n경로: \(expanded)\n크기: \(sizeStr)\n확장자: \(ext)")
            }

            let truncated = data.count > maxReadSize
            let suffix = truncated ? "\n…(파일이 \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))로 잘렸습니다)" : ""

            Log.tool.info("Read file: \(expanded) (\(size) bytes)")
            return ToolResult(toolCallId: "", content: "\(text)\(suffix)")
        } catch {
            return ToolResult(toolCallId: "", content: "파일 읽기 실패: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - file.write

@MainActor
final class FileWriteTool: BuiltInToolProtocol {
    let name = "file.write"
    let category: ToolCategory = .sensitive
    let description = "텍스트를 파일에 씁니다. 기존 파일은 덮어씁니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "파일 경로"],
                "content": ["type": "string", "description": "파일에 쓸 내용"],
            ] as [String: Any],
            "required": ["path", "content"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(toolCallId: "", content: "path 파라미터가 필요합니다.", isError: true)
        }
        guard let content = arguments["content"] as? String else {
            return ToolResult(toolCallId: "", content: "content 파라미터가 필요합니다.", isError: true)
        }

        let (expanded, error) = validatePath(path)
        if let error { return error }

        do {
            // Create parent directory if needed
            let parentDir = (expanded as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

            try content.write(toFile: expanded, atomically: true, encoding: .utf8)
            Log.tool.info("Wrote file: \(expanded) (\(content.count) chars)")
            return ToolResult(toolCallId: "", content: "파일을 저장했습니다: \(path) (\(content.count)자)")
        } catch {
            return ToolResult(toolCallId: "", content: "파일 쓰기 실패: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - file.list

@MainActor
final class FileListTool: BuiltInToolProtocol {
    let name = "file.list"
    let category: ToolCategory = .safe
    let description = "디렉토리 내용을 나열합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "디렉토리 경로"],
                "show_hidden": ["type": "boolean", "description": "숨김 파일 포함 여부 (기본: false)"],
            ] as [String: Any],
            "required": ["path"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(toolCallId: "", content: "path 파라미터가 필요합니다.", isError: true)
        }

        let (expanded, error) = validatePath(path)
        if let error { return error }

        let showHidden = arguments["show_hidden"] as? Bool ?? false
        let fm = FileManager.default

        guard fm.fileExists(atPath: expanded) else {
            return ToolResult(toolCallId: "", content: "경로를 찾을 수 없습니다: \(path)", isError: true)
        }

        do {
            var items = try fm.contentsOfDirectory(atPath: expanded)
            if !showHidden {
                items = items.filter { !$0.hasPrefix(".") }
            }
            items.sort()

            var lines: [String] = []
            for item in items.prefix(200) {
                let fullPath = (expanded as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                let suffix = isDir.boolValue ? "/" : ""
                lines.append("\(item)\(suffix)")
            }

            let result = lines.joined(separator: "\n")
            let extra = items.count > 200 ? "\n…(\(items.count - 200)개 더)" : ""
            Log.tool.info("Listed directory: \(expanded), \(items.count) items")
            return ToolResult(toolCallId: "", content: "\(expanded) (\(items.count)개):\n\(result)\(extra)")
        } catch {
            return ToolResult(toolCallId: "", content: "디렉토리 나열 실패: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - file.search

@MainActor
final class FileSearchTool: BuiltInToolProtocol {
    let name = "file.search"
    let category: ToolCategory = .safe
    let description = "glob 패턴으로 파일을 검색합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "검색 시작 디렉토리"],
                "pattern": ["type": "string", "description": "파일명 패턴 (예: *.txt, report*)"],
            ] as [String: Any],
            "required": ["path", "pattern"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(toolCallId: "", content: "path 파라미터가 필요합니다.", isError: true)
        }
        guard let pattern = arguments["pattern"] as? String, !pattern.isEmpty else {
            return ToolResult(toolCallId: "", content: "pattern 파라미터가 필요합니다.", isError: true)
        }

        let (expanded, error) = validatePath(path)
        if let error { return error }

        let fm = FileManager.default
        guard fm.fileExists(atPath: expanded) else {
            return ToolResult(toolCallId: "", content: "경로를 찾을 수 없습니다: \(path)", isError: true)
        }

        guard let enumerator = fm.enumerator(atPath: expanded) else {
            return ToolResult(toolCallId: "", content: "디렉토리 탐색 실패: \(path)", isError: true)
        }

        var matches: [String] = []
        let maxResults = 100

        while let item = enumerator.nextObject() as? String {
            let fileName = (item as NSString).lastPathComponent
            if fnmatch(pattern, fileName, 0) == 0 {
                matches.append(item)
                if matches.count >= maxResults { break }
            }
        }

        if matches.isEmpty {
            return ToolResult(toolCallId: "", content: "'\(pattern)' 패턴과 일치하는 파일이 없습니다.")
        }

        let result = matches.joined(separator: "\n")
        let suffix = matches.count >= maxResults ? "\n…(최대 \(maxResults)개)" : ""
        Log.tool.info("File search in \(expanded): \(matches.count) matches for '\(pattern)'")
        return ToolResult(toolCallId: "", content: "검색 결과 (\(matches.count)개):\n\(result)\(suffix)")
    }
}

// MARK: - file.move

@MainActor
final class FileMoveTool: BuiltInToolProtocol {
    let name = "file.move"
    let category: ToolCategory = .sensitive
    let description = "파일 또는 폴더를 이동(이름 변경)합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "source": ["type": "string", "description": "원본 경로"],
                "destination": ["type": "string", "description": "대상 경로"],
            ] as [String: Any],
            "required": ["source", "destination"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let source = arguments["source"] as? String else {
            return ToolResult(toolCallId: "", content: "source 파라미터가 필요합니다.", isError: true)
        }
        guard let destination = arguments["destination"] as? String else {
            return ToolResult(toolCallId: "", content: "destination 파라미터가 필요합니다.", isError: true)
        }

        let (srcExpanded, srcError) = validatePath(source)
        if let srcError { return srcError }
        let (dstExpanded, dstError) = validatePath(destination)
        if let dstError { return dstError }

        let fm = FileManager.default
        guard fm.fileExists(atPath: srcExpanded) else {
            return ToolResult(toolCallId: "", content: "원본을 찾을 수 없습니다: \(source)", isError: true)
        }

        do {
            let parentDir = (dstExpanded as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            try fm.moveItem(atPath: srcExpanded, toPath: dstExpanded)
            Log.tool.info("Moved: \(srcExpanded) → \(dstExpanded)")
            return ToolResult(toolCallId: "", content: "이동 완료: \(source) → \(destination)")
        } catch {
            return ToolResult(toolCallId: "", content: "이동 실패: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - file.copy

@MainActor
final class FileCopyTool: BuiltInToolProtocol {
    let name = "file.copy"
    let category: ToolCategory = .sensitive
    let description = "파일 또는 폴더를 복사합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "source": ["type": "string", "description": "원본 경로"],
                "destination": ["type": "string", "description": "대상 경로"],
            ] as [String: Any],
            "required": ["source", "destination"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let source = arguments["source"] as? String else {
            return ToolResult(toolCallId: "", content: "source 파라미터가 필요합니다.", isError: true)
        }
        guard let destination = arguments["destination"] as? String else {
            return ToolResult(toolCallId: "", content: "destination 파라미터가 필요합니다.", isError: true)
        }

        let (srcExpanded, srcError) = validatePath(source)
        if let srcError { return srcError }
        let (dstExpanded, dstError) = validatePath(destination)
        if let dstError { return dstError }

        let fm = FileManager.default
        guard fm.fileExists(atPath: srcExpanded) else {
            return ToolResult(toolCallId: "", content: "원본을 찾을 수 없습니다: \(source)", isError: true)
        }

        do {
            let parentDir = (dstExpanded as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            try fm.copyItem(atPath: srcExpanded, toPath: dstExpanded)
            Log.tool.info("Copied: \(srcExpanded) → \(dstExpanded)")
            return ToolResult(toolCallId: "", content: "복사 완료: \(source) → \(destination)")
        } catch {
            return ToolResult(toolCallId: "", content: "복사 실패: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - file.delete

@MainActor
final class FileDeleteTool: BuiltInToolProtocol {
    let name = "file.delete"
    let category: ToolCategory = .restricted
    let description = "파일 또는 폴더를 삭제합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "삭제할 파일 또는 폴더 경로"],
            ] as [String: Any],
            "required": ["path"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(toolCallId: "", content: "path 파라미터가 필요합니다.", isError: true)
        }

        let (expanded, error) = validatePath(path)
        if let error { return error }

        let fm = FileManager.default
        guard fm.fileExists(atPath: expanded) else {
            return ToolResult(toolCallId: "", content: "파일을 찾을 수 없습니다: \(path)", isError: true)
        }

        // Safety: prevent deleting home directory itself
        if expanded == NSHomeDirectory() {
            return ToolResult(toolCallId: "", content: "홈 디렉토리는 삭제할 수 없습니다.", isError: true)
        }

        do {
            try fm.removeItem(atPath: expanded)
            Log.tool.info("Deleted: \(expanded)")
            return ToolResult(toolCallId: "", content: "삭제 완료: \(path)")
        } catch {
            return ToolResult(toolCallId: "", content: "삭제 실패: \(error.localizedDescription)", isError: true)
        }
    }
}
