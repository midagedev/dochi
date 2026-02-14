import Foundation

/// LLM adapter for Ollama (OpenAI-compatible API at localhost:11434).
/// Ollama doesn't require an API key and uses the same SSE format as OpenAI.
struct OllamaAdapter: LLMProviderAdapter {
    let provider: LLMProvider = .ollama

    private let base = OpenAIAdapter()

    /// Custom base URL from settings (defaults to http://localhost:11434).
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
        // Ollama doesn't require Authorization header, but include if provided
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
        // Ollama uses OpenAI-compatible SSE format
        base.parseSSELine(line, accumulated: &accumulated)
    }
}

// MARK: - Ollama Model Discovery

/// Utility for fetching available models from a running Ollama instance.
enum OllamaModelFetcher {
    struct ModelListResponse: Decodable {
        let models: [ModelInfo]
    }

    struct ModelInfo: Decodable {
        let name: String
        let size: Int64?
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
        }
    }

    /// Fetch available models from Ollama API.
    static func fetchModels(baseURL: URL = URL(string: "http://localhost:11434")!) async -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
            return response.models.map(\.name)
        } catch {
            Log.llm.debug("Ollama model fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Check if Ollama is running.
    static func isAvailable(baseURL: URL = URL(string: "http://localhost:11434")!) async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
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
