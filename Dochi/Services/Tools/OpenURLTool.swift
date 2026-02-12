import AppKit
import Foundation

@MainActor
final class OpenURLTool: BuiltInToolProtocol {
    let name = "open_url"
    let category: ToolCategory = .sensitive
    let description = "URL을 기본 브라우저에서 열거나, 앱을 실행합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "url": ["type": "string", "description": "열 URL 또는 앱 경로 (https://... 또는 /Applications/...)"],
            ],
            "required": ["url"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let urlString = arguments["url"] as? String, !urlString.isEmpty else {
            return ToolResult(toolCallId: "", content: "url 파라미터가 필요합니다.", isError: true)
        }

        // App path
        if urlString.hasSuffix(".app") {
            let appURL = URL(fileURLWithPath: urlString)
            let config = NSWorkspace.OpenConfiguration()
            do {
                try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                return ToolResult(toolCallId: "", content: "앱을 실행했습니다: \(appURL.lastPathComponent)")
            } catch {
                return ToolResult(toolCallId: "", content: "앱 실행 실패: \(error.localizedDescription)", isError: true)
            }
        }

        // URL
        guard let url = URL(string: urlString) else {
            return ToolResult(toolCallId: "", content: "유효하지 않은 URL입니다: \(urlString)", isError: true)
        }

        let opened = NSWorkspace.shared.open(url)
        if opened {
            return ToolResult(toolCallId: "", content: "URL을 열었습니다: \(urlString)")
        } else {
            return ToolResult(toolCallId: "", content: "URL을 열 수 없습니다: \(urlString)", isError: true)
        }
    }
}
