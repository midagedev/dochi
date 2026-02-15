import Foundation

/// LLM adapter for LM Studio (OpenAI-compatible API at localhost:1234).
/// LM Studio doesn't require an API key and uses the same SSE format as OpenAI.
struct LMStudioAdapter: LLMProviderAdapter {
    let provider: LLMProvider = .lmStudio

    private let base = OpenAIAdapter()

    /// Custom base URL from settings (defaults to http://localhost:1234/v1/chat/completions).
    var baseURL: URL?

    func buildRequest(
        messages: [Message],
        systemPrompt: String,
        model: String,
        tools: [[String: Any]]?,
        apiKey: String
    ) throws -> URLRequest {
        let url = baseURL ?? provider.apiURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // LM Studio doesn't require Authorization header, but include if provided
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
        ]

        var apiMessages: [[String: Any]] = []

        if !systemPrompt.isEmpty {
            apiMessages.append([
                "role": "system",
                "content": systemPrompt,
            ])
        }

        for msg in messages {
            apiMessages.append(OpenAIAdapter.convertMessage(msg))
        }

        body["messages"] = apiMessages

        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func parseSSELine(_ line: String, accumulated: inout StreamAccumulator) -> LLMStreamEvent? {
        // LM Studio uses OpenAI-compatible SSE format
        base.parseSSELine(line, accumulated: &accumulated)
    }
}

// MARK: - LM Studio Model Discovery

/// Utility for fetching available models from a running LM Studio instance.
enum LMStudioModelFetcher {
    struct ModelListResponse: Decodable {
        let data: [ModelInfo]
    }

    struct ModelInfo: Decodable {
        let id: String
        let object: String?

        enum CodingKeys: String, CodingKey {
            case id, object
        }
    }

    /// Fetch available models from LM Studio's OpenAI-compatible API.
    static func fetchModels(baseURL: URL = URL(string: "http://localhost:1234")!) async -> [String] {
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
            return response.data.map(\.id)
        } catch {
            Log.llm.debug("LM Studio model fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch available models with detailed info from LM Studio.
    static func fetchModelInfos(baseURL: URL = URL(string: "http://localhost:1234")!) async -> [LocalModelInfo] {
        let models = await fetchModels(baseURL: baseURL)
        return models.map { modelId in
            LocalModelInfo(
                name: modelId,
                size: 0, // LM Studio /v1/models doesn't expose file size
                parameterSize: nil,
                quantization: nil,
                family: nil,
                supportsTools: false // Conservative default; no reliable detection method
            )
        }
    }

    /// Check if LM Studio is running.
    static func isAvailable(baseURL: URL = URL(string: "http://localhost:1234")!) async -> Bool {
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
