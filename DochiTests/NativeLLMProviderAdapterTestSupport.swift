import Foundation
@testable import Dochi

actor MockNativeLLMHTTPClient: NativeLLMHTTPClient {
    private let statusCode: Int
    private let headers: [String: String]
    private let body: Data
    private let stubbedError: Error?
    private let streamLines: [String]?
    private let streamLineDelayNanoseconds: UInt64
    private(set) var lastRequest: URLRequest?
    private(set) var streamCancelled = false
    private(set) var sendCallCount = 0
    private(set) var sendStreamingCallCount = 0

    init(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        stubbedError: Error? = nil,
        streamLines: [String]? = nil,
        streamLineDelayNanoseconds: UInt64 = 0
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.stubbedError = stubbedError
        self.streamLines = streamLines
        self.streamLineDelayNanoseconds = streamLineDelayNanoseconds
    }

    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        sendCallCount += 1
        lastRequest = request
        if let stubbedError {
            throw stubbedError
        }

        let response = try makeResponse(for: request)
        return (body, response)
    }

    func sendStreaming(_ request: URLRequest) async throws -> (lineStream: AsyncThrowingStream<String, Error>, response: HTTPURLResponse) {
        sendStreamingCallCount += 1
        lastRequest = request
        if let stubbedError {
            throw stubbedError
        }

        let response = try makeResponse(for: request)
        let payload = String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
        let resolvedLines = streamLines ?? payload
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        let lineDelay = streamLineDelayNanoseconds

        let lineStream = AsyncThrowingStream<String, Error> { continuation in
            let producer = Task {
                do {
                    for line in resolvedLines {
                        try Task.checkCancellation()
                        if lineDelay > 0 {
                            try await Task.sleep(nanoseconds: lineDelay)
                        }
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { termination in
                producer.cancel()
                guard case .cancelled = termination else { return }
                Task { await self.markStreamCancelled() }
            }
        }

        return (lineStream, response)
    }

    func capturedRequest() -> URLRequest? {
        lastRequest
    }

    func didCancelStream() -> Bool {
        streamCancelled
    }

    private func makeResponse(for request: URLRequest) throws -> HTTPURLResponse {
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
        return response
    }

    private func markStreamCancelled() {
        streamCancelled = true
    }
}
