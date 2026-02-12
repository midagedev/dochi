import AppKit
import Foundation
import os

// MARK: - Reveal in Finder

@MainActor
final class FinderRevealTool: BuiltInToolProtocol {
    let name = "finder.reveal"
    let category: ToolCategory = .safe
    let description = "Finder에서 파일 또는 폴더를 표시합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "파일 또는 폴더 경로"],
            ] as [String: Any],
            "required": ["path"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            return ToolResult(toolCallId: "", content: "path 파라미터가 필요합니다.", isError: true)
        }

        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return ToolResult(toolCallId: "", content: "경로를 찾을 수 없습니다: \(path)", isError: true)
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        Log.tool.info("Revealed in Finder: \(path)")
        return ToolResult(toolCallId: "", content: "Finder에서 표시: \(url.lastPathComponent)")
    }
}

// MARK: - Get Finder Selection

@MainActor
final class FinderGetSelectionTool: BuiltInToolProtocol {
    let name = "finder.get_selection"
    let category: ToolCategory = .safe
    let description = "Finder에서 현재 선택된 파일들의 경로를 가져옵니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [:] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let script = """
        tell application "Finder"
            set selectedItems to selection
            if (count of selectedItems) is 0 then
                return "EMPTY"
            end if
            set output to ""
            repeat with item_ in selectedItems
                set output to output & (POSIX path of (item_ as alias)) & linefeed
            end repeat
            return output
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "EMPTY" || trimmed.isEmpty {
                return ToolResult(toolCallId: "", content: "Finder에서 선택된 파일이 없습니다.")
            }
            let paths = trimmed.split(separator: "\n").map(String.init)
            Log.tool.info("Got Finder selection: \(paths.count) items")
            return ToolResult(toolCallId: "", content: "Finder 선택 (\(paths.count)개):\n\(trimmed)")
        case .failure(let error):
            Log.tool.error("Failed to get Finder selection: \(error.message)")
            return ToolResult(toolCallId: "", content: "Finder 선택 조회 실패: \(error.message)", isError: true)
        }
    }
}

// MARK: - List Directory

@MainActor
final class FinderListDirectoryTool: BuiltInToolProtocol {
    let name = "finder.list_dir"
    let category: ToolCategory = .safe
    let description = "디렉토리 내용을 나열합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "디렉토리 경로 (기본: 홈 디렉토리)"],
                "show_hidden": ["type": "boolean", "description": "숨김 파일 포함 여부 (기본: false)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let path = arguments["path"] as? String ?? NSHomeDirectory()
        let showHidden = arguments["show_hidden"] as? Bool ?? false
        let expandedPath = NSString(string: path).expandingTildeInPath

        let fm = FileManager.default
        guard fm.fileExists(atPath: expandedPath) else {
            return ToolResult(toolCallId: "", content: "경로를 찾을 수 없습니다: \(path)", isError: true)
        }

        do {
            var items = try fm.contentsOfDirectory(atPath: expandedPath)
            if !showHidden {
                items = items.filter { !$0.hasPrefix(".") }
            }
            items.sort()

            var lines: [String] = []
            for item in items.prefix(100) {
                let fullPath = (expandedPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                let icon = isDir.boolValue ? "📁" : "📄"
                lines.append("\(icon) \(item)")
            }

            let result = lines.joined(separator: "\n")
            let suffix = items.count > 100 ? "\n…(\(items.count - 100)개 더)" : ""
            Log.tool.info("Listed directory: \(expandedPath), \(items.count) items")
            return ToolResult(toolCallId: "", content: "\(expandedPath) (\(items.count)개):\n\(result)\(suffix)")
        } catch {
            return ToolResult(toolCallId: "", content: "디렉토리 나열 실패: \(error.localizedDescription)", isError: true)
        }
    }
}
