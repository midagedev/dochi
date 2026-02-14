import Foundation

@MainActor
final class ScreenshotCaptureTool: BuiltInToolProtocol {
    let name = "screenshot.capture"
    let category: ToolCategory = .sensitive
    let description = "macOS 화면을 캡처하여 이미지 파일로 저장합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "region": [
                    "type": "string",
                    "description": "캡처 영역: fullscreen (기본), window",
                    "enum": ["fullscreen", "window"],
                ],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let region = arguments["region"] as? String ?? "fullscreen"

        // Ensure save directory exists
        let saveDir = saveDirURL()
        do {
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        } catch {
            return ToolResult(toolCallId: "", content: "저장 디렉토리 생성 실패: \(error.localizedDescription)", isError: true)
        }

        // Generate filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filePath = saveDir.appendingPathComponent("screenshot_\(timestamp).png").path

        // Build screencapture command
        var args = ["-x"] // -x: no sound
        if region == "window" {
            args.append("-w") // -w: interactive window selection
        }
        args.append(filePath)

        do {
            try await runScreencapture(args: args)
        } catch {
            return ToolResult(toolCallId: "", content: "스크린샷 캡처 실패: \(error.localizedDescription)", isError: true)
        }

        // Verify file was created
        guard FileManager.default.fileExists(atPath: filePath) else {
            return ToolResult(toolCallId: "", content: "스크린샷 파일이 생성되지 않았습니다.", isError: true)
        }

        Log.tool.info("Screenshot captured: \(filePath)")
        return ToolResult(toolCallId: "", content: "스크린샷을 저장했습니다.\n경로: \(filePath)")
    }

    func saveDirURL() -> URL {
        let picturesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures")
            .appendingPathComponent("Dochi")
        return picturesDir
    }

    private func runScreencapture(args: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args

            let errPipe = Pipe()
            process.standardError = errPipe

            let timeoutItem = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeoutItem)

            do {
                try process.run()
                process.waitUntilExit()
                timeoutItem.cancel()

                if process.terminationStatus != 0 {
                    let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    throw NSError(domain: "ScreenshotTool", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: "screencapture exit \(process.terminationStatus): \(stderr)"])
                }
                continuation.resume()
            } catch {
                timeoutItem.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}
