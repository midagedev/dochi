import Foundation
import SwiftUI

// MARK: - Chat Message Model

struct MobileChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: MobileChatRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MobileChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum MobileChatRole: String, Sendable {
    case user
    case assistant
}

// MARK: - Chat ViewModel

@MainActor
final class MobileChatViewModel: ObservableObject {
    @Published var messages: [MobileChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false

    private var conversationHistory: [[String: String]] = []

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let userMessage = MobileChatMessage(role: .user, content: text)
        messages.append(userMessage)
        conversationHistory.append(["role": "user", "content": text])
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await callAPI(messages: conversationHistory)
                let assistantMessage = MobileChatMessage(role: .assistant, content: response)
                messages.append(assistantMessage)
                conversationHistory.append(["role": "assistant", "content": response])
            } catch {
                let errorMessage = MobileChatMessage(
                    role: .assistant,
                    content: "오류: \(error.localizedDescription)"
                )
                messages.append(errorMessage)
            }
            isLoading = false
        }
    }

    func clearMessages() {
        messages.removeAll()
        conversationHistory.removeAll()
    }

    // MARK: - API

    private func callAPI(messages: [[String: String]]) async throws -> String {
        let apiKey = UserDefaults.standard.string(forKey: "mobile_api_key") ?? ""
        let model = UserDefaults.standard.string(forKey: "mobile_model") ?? "claude-sonnet-4-5-20250929"

        guard !apiKey.isEmpty else {
            throw MobileAPIError.noAPIKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": "당신은 도치라는 이름의 AI 어시스턴트입니다. 간결하고 친절하게 답변합니다.",
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let msg = error["message"] as? String {
                throw MobileAPIError.apiError(msg)
            }
            throw MobileAPIError.invalidResponse
        }
        return text
    }
}

// MARK: - Errors

enum MobileAPIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "설정에서 API 키를 입력해주세요."
        case .invalidResponse: "잘못된 응답입니다."
        case .apiError(let msg): "API 오류: \(msg)"
        }
    }
}
