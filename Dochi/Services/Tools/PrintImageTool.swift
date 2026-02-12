import Foundation
import os

@MainActor
final class PrintImageTool: BuiltInToolProtocol {
    let name = "print_image"
    let category: ToolCategory = .safe
    let description = "이미지를 채팅에 표시합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "image_path": ["type": "string", "description": "표시할 이미지 파일 경로"]
            ],
            "required": ["image_path"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let imagePath = arguments["image_path"] as? String, !imagePath.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: image_path는 필수입니다.", isError: true)
        }

        let expandedPath = (imagePath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return ToolResult(toolCallId: "", content: "오류: 파일을 찾을 수 없습니다: \(imagePath)", isError: true)
        }

        let validExtensions = Set(["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"])
        let ext = (expandedPath as NSString).pathExtension.lowercased()
        guard validExtensions.contains(ext) else {
            return ToolResult(toolCallId: "", content: "오류: 지원하지 않는 이미지 형식입니다. 지원 형식: \(validExtensions.sorted().joined(separator: ", "))", isError: true)
        }

        Log.tool.info("Print image: \(expandedPath)")
        // Actual display is handled by the UI layer when it processes this result
        return ToolResult(toolCallId: "", content: "![image](\(expandedPath))")
    }
}
