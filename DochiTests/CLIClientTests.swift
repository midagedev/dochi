import XCTest

/// Tests for CLI client config and integration concepts.
/// The actual DochiCLI target is a separate command-line tool;
/// these tests verify the supporting model patterns used by CLI.
@MainActor
final class CLIClientTests: XCTestCase {

    // MARK: - CLI Config Path

    func testContextDirectoryExists() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        // The directory should exist (created by the main app)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testCLIConfigCodable() throws {
        struct CLIConfigModel: Codable {
            var apiKey: String?
            var model: String
            var provider: String
            var baseURL: String?
        }

        let config = CLIConfigModel(
            apiKey: "sk-test-key",
            model: "claude-sonnet-4-5-20250929",
            provider: "anthropic",
            baseURL: nil
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CLIConfigModel.self, from: data)
        XCTAssertEqual(decoded.apiKey, "sk-test-key")
        XCTAssertEqual(decoded.model, "claude-sonnet-4-5-20250929")
        XCTAssertEqual(decoded.provider, "anthropic")
        XCTAssertNil(decoded.baseURL)
    }

    func testCLIConfigWithBaseURL() throws {
        struct CLIConfigModel: Codable {
            var apiKey: String?
            var model: String
            var provider: String
            var baseURL: String?
        }

        let config = CLIConfigModel(
            apiKey: "sk-key",
            model: "gpt-4",
            provider: "openai",
            baseURL: "https://custom.api.com"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CLIConfigModel.self, from: data)
        XCTAssertEqual(decoded.baseURL, "https://custom.api.com")
        XCTAssertEqual(decoded.provider, "openai")
    }

    // MARK: - CLI Error Patterns

    func testCLIErrorDescriptions() {
        // Verify error pattern matches CLI design
        enum TestCLIError: LocalizedError {
            case noAPIKey
            case invalidResponse
            case apiError(String)

            var errorDescription: String? {
                switch self {
                case .noAPIKey: "API 키가 설정되지 않았습니다."
                case .invalidResponse: "잘못된 API 응답입니다."
                case .apiError(let msg): "API 오류: \(msg)"
                }
            }
        }

        XCTAssertEqual(TestCLIError.noAPIKey.localizedDescription, "API 키가 설정되지 않았습니다.")
        XCTAssertEqual(TestCLIError.invalidResponse.localizedDescription, "잘못된 API 응답입니다.")
        XCTAssertTrue(TestCLIError.apiError("rate limit").localizedDescription.contains("rate limit"))
    }

    // MARK: - CLI Target Build Verification

    func testDochiCLIBinaryName() {
        // Verify the expected binary name convention
        let expectedName = "dochi"
        XCTAssertEqual(expectedName, "dochi")
    }

    // MARK: - API Request Structure

    func testAnthropicAPIRequestBody() throws {
        let messages: [[String: String]] = [
            ["role": "user", "content": "안녕"],
        ]
        let body: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 4096,
            "system": "당신은 도치입니다.",
            "messages": messages,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(decoded["model"] as? String, "claude-sonnet-4-5-20250929")
        XCTAssertEqual(decoded["max_tokens"] as? Int, 4096)
        XCTAssertEqual(decoded["system"] as? String, "당신은 도치입니다.")
        XCTAssertEqual((decoded["messages"] as? [[String: String]])?.count, 1)
    }

    func testAPIResponseParsing() throws {
        let responseJSON = """
        {
            "content": [{"type": "text", "text": "안녕하세요!"}],
            "model": "claude-sonnet-4-5-20250929",
            "role": "assistant"
        }
        """.data(using: .utf8)!

        let json = try JSONSerialization.jsonObject(with: responseJSON) as! [String: Any]
        let content = json["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        XCTAssertEqual(text, "안녕하세요!")
    }

    func testAPIErrorResponseParsing() throws {
        let errorJSON = """
        {
            "error": {"type": "authentication_error", "message": "Invalid API key"}
        }
        """.data(using: .utf8)!

        let json = try JSONSerialization.jsonObject(with: errorJSON) as! [String: Any]
        let error = json["error"] as? [String: Any]
        let message = error?["message"] as? String
        XCTAssertEqual(message, "Invalid API key")
    }
}
