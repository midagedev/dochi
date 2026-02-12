import Foundation
import os

@MainActor
final class GenerateImageTool: BuiltInToolProtocol {
    let name = "generate_image"
    let category: ToolCategory = .safe
    let description = "fal.ai를 사용하여 이미지를 생성합니다."
    let isBaseline = true

    private let keychainService: KeychainServiceProtocol

    private static let validSizes: Set<String> = [
        "square_hd", "square", "landscape_4_3", "landscape_16_9", "portrait_4_3", "portrait_16_9"
    ]

    init(keychainService: KeychainServiceProtocol) {
        self.keychainService = keychainService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "prompt": ["type": "string", "description": "이미지 생성 프롬프트"],
                "image_size": [
                    "type": "string",
                    "enum": ["square_hd", "square", "landscape_4_3", "landscape_16_9", "portrait_4_3", "portrait_16_9"],
                    "description": "이미지 크기 (기본: landscape_4_3)"
                ]
            ],
            "required": ["prompt"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let prompt = arguments["prompt"] as? String, !prompt.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: prompt는 필수입니다.", isError: true)
        }

        guard let apiKey = keychainService.load(account: "fal_api_key"), !apiKey.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: fal.ai API 키가 설정되지 않았습니다. 설정에서 API 키를 등록해주세요.", isError: true)
        }

        let imageSize = arguments["image_size"] as? String ?? "landscape_4_3"
        guard Self.validSizes.contains(imageSize) else {
            return ToolResult(toolCallId: "", content: "오류: 지원하지 않는 이미지 크기입니다. 사용 가능: \(Self.validSizes.sorted().joined(separator: ", "))", isError: true)
        }

        let url = URL(string: "https://queue.fal.run/fal-ai/flux/schnell")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "prompt": prompt,
            "image_size": imageSize,
            "num_images": 1
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return ToolResult(toolCallId: "", content: "오류: 요청 생성 실패.", isError: true)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ToolResult(toolCallId: "", content: "오류: 서버 응답을 받을 수 없습니다.", isError: true)
            }

            guard httpResponse.statusCode == 200 else {
                Log.tool.error("fal.ai API error: status \(httpResponse.statusCode)")
                return ToolResult(toolCallId: "", content: "오류: 이미지 생성 API 오류 (HTTP \(httpResponse.statusCode)). API 키를 확인해주세요.", isError: true)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let images = json["images"] as? [[String: Any]],
                  let firstImage = images.first,
                  let imageUrl = firstImage["url"] as? String else {
                return ToolResult(toolCallId: "", content: "오류: 이미지 생성 응답 파싱 실패.", isError: true)
            }

            // Download the image to a temp file
            guard let downloadUrl = URL(string: imageUrl) else {
                return ToolResult(toolCallId: "", content: "이미지 생성 완료. URL: \(imageUrl)")
            }

            let (imageData, _) = try await URLSession.shared.data(from: downloadUrl)
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "dochi_image_\(UUID().uuidString).png"
            let filePath = tempDir.appendingPathComponent(fileName)
            try imageData.write(to: filePath)

            Log.tool.info("Image generated: \(filePath.path)")
            return ToolResult(toolCallId: "", content: "이미지를 생성했습니다. 경로: \(filePath.path)")
        } catch {
            Log.tool.error("Image generation failed: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 이미지 생성 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}
