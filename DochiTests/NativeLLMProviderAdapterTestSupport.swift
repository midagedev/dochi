import Foundation
@testable import Dochi

actor MockNativeLLMHTTPClient: NativeLLMHTTPClient {
    private let statusCode: Int
    private let headers: [String: String]
    private let body: Data
    private let stubbedError: Error?
    private(set) var lastRequest: URLRequest?

    init(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        stubbedError: Error? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.stubbedError = stubbedError
    }

    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        lastRequest = request
        if let stubbedError {
            throw stubbedError
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
              ) else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Failed to build HTTPURLResponse in test",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }
        return (body, response)
    }

    func capturedRequest() -> URLRequest? {
        lastRequest
    }
}
