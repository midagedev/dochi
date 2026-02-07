import AppKit
import os

/// 이미지 프린트 도구 — 기본 프린터로 즉시 출력
@MainActor
final class PrintImageTool: BuiltInTool {
    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:print_image",
                name: "print_image",
                description: "Print a local image file to the default printer. The image is scaled to fit A4 paper while maintaining aspect ratio. Use this when the user wants to print an image.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "image_path": [
                            "type": "string",
                            "description": "Local file URL of the image to print (file:// format)"
                        ]
                    ],
                    "required": ["image_path"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard name == "print_image" else {
            throw BuiltInToolError.unknownTool(name)
        }
        return try await printImage(arguments: arguments)
    }

    private func printImage(arguments: [String: Any]) async throws -> MCPToolResult {
        guard let imagePath = arguments["image_path"] as? String, !imagePath.isEmpty else {
            throw BuiltInToolError.invalidArguments("image_path is required")
        }

        guard let url = URL(string: imagePath), url.isFileURL else {
            throw BuiltInToolError.invalidArguments("image_path must be a file:// URL")
        }

        guard let image = NSImage(contentsOf: url) else {
            throw BuiltInToolError.invalidArguments("Failed to load image from \(imagePath)")
        }

        Log.tool.info("이미지 프린트 요청: \(imagePath, privacy: .public)")

        // A4 용지 설정 (595.28 × 841.89 pt)
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
        printInfo.topMargin = 20
        printInfo.bottomMargin = 20
        printInfo.leftMargin = 20
        printInfo.rightMargin = 20
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let printableArea = CGRect(
            x: 0, y: 0,
            width: printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin,
            height: printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
        )

        let printView = PrintableImageView(image: image, frame: printableArea)

        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false

        let success = operation.run()

        if success {
            Log.tool.info("이미지 프린트 성공")
            return MCPToolResult(content: "이미지를 기본 프린터로 전송했습니다.", isError: false)
        } else {
            Log.tool.error("이미지 프린트 실패")
            return MCPToolResult(content: "이미지 프린트에 실패했습니다.", isError: true)
        }
    }
}

// MARK: - Printable Image View

private class PrintableImageView: NSView {
    private let image: NSImage

    init(image: NSImage, frame: CGRect) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        // Aspect-fit 계산
        let scaleX = bounds.width / imageSize.width
        let scaleY = bounds.height / imageSize.height
        let scale = min(scaleX, scaleY)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let x = (bounds.width - scaledWidth) / 2
        let y = (bounds.height - scaledHeight) / 2

        let destRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
        image.draw(in: destRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}
