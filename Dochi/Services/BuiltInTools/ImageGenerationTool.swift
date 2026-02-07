import Foundation

/// 이미지 생성 도구 (fal.ai FLUX)
@MainActor
final class ImageGenerationTool: BuiltInTool {
    var apiKey: String = ""

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:generate_image",
                name: "generate_image",
                description: "Generate an image from a text description using AI. Returns the image as a markdown image tag. Use this when the user asks to create, draw, or generate an image.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "prompt": [
                            "type": "string",
                            "description": "Text description of the image to generate (in English for best results)"
                        ],
                        "image_size": [
                            "type": "string",
                            "description": "Image size. Options: square_hd, square, landscape_4_3, landscape_16_9, portrait_4_3, portrait_16_9. Default: square_hd. Optional."
                        ]
                    ],
                    "required": ["prompt"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard name == "generate_image" else {
            throw BuiltInToolError.unknownTool(name)
        }
        return try await generateImage(arguments: arguments)
    }

    private func generateImage(arguments: [String: Any]) async throws -> MCPToolResult {
        guard !apiKey.isEmpty else {
            throw BuiltInToolError.missingApiKey("Fal.ai")
        }

        guard let prompt = arguments["prompt"] as? String, !prompt.isEmpty else {
            throw BuiltInToolError.invalidArguments("prompt is required")
        }

        let imageSize = arguments["image_size"] as? String ?? "square_hd"

        // fal.ai FLUX schnell API
        let url = URL(string: "https://fal.run/fal-ai/flux/schnell")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "prompt": prompt,
            "image_size": imageSize,
            "num_images": 1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BuiltInToolError.apiError("Fal.ai API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [[String: Any]],
              let firstImage = images.first,
              let imageURLStr = firstImage["url"] as? String else {
            throw BuiltInToolError.invalidResponse("Failed to parse fal.ai response")
        }

        // 이미지를 로컬에 저장
        let localURL = try await downloadImage(from: imageURLStr)

        return MCPToolResult(
            content: "이미지 생성 완료:\n\n![image](\(localURL.absoluteString))",
            isError: false
        )
    }

    private func downloadImage(from urlString: String) async throws -> URL {
        guard let remoteURL = URL(string: urlString) else {
            throw BuiltInToolError.invalidResponse("Invalid image URL")
        }

        let (data, _) = try await URLSession.shared.data(from: remoteURL)

        // ~/Library/Application Support/Dochi/images/ 에 저장
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let imagesDir = appSupport.appendingPathComponent("Dochi/images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).jpg"
        let localURL = imagesDir.appendingPathComponent(filename)
        try data.write(to: localURL)

        print("[ImageGen] Saved image: \(localURL.path)")
        return localURL
    }
}
