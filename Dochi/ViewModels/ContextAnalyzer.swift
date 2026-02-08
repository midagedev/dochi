import Foundation
import os

/// 대화 분석, 메모리 관리, 컨텍스트 압축
@MainActor
final class ContextAnalyzer {
    private weak var vm: DochiViewModel?

    init(viewModel: DochiViewModel) {
        self.vm = viewModel
    }

    // MARK: - Session Context Analysis

    func saveAndAnalyzeConversation(_ sessionMessages: [Message], userId: UUID? = nil) async {
        guard let vm else { return }
        guard sessionMessages.count >= 2 else { return }

        let hasProfiles = !vm.contextService.loadProfiles().isEmpty
        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !vm.settings.apiKey(for: $0).isEmpty }) else {
            let defaultTitle = Self.generateDefaultTitle(from: sessionMessages)
            await MainActor.run {
                vm.saveConversationWithTitle(defaultTitle, summary: nil, userId: userId, messages: sessionMessages)
            }
            return
        }

        let apiKey = vm.settings.apiKey(for: provider)

        let conversationText = sessionMessages.compactMap { msg -> String? in
            guard msg.role == .user || msg.role == .assistant else { return nil }
            let role = msg.role == .user ? "사용자" : "어시스턴트"
            return "[\(role)] \(msg.content)"
        }.joined(separator: "\n")

        let prompt: String
        if hasProfiles {
            let familyMemory = vm.contextService.loadFamilyMemory()
            let personalMemory = userId.map { vm.contextService.loadUserMemory(userId: $0) } ?? ""

            prompt = """
            다음은 방금 끝난 대화입니다:

            \(conversationText)

            ---

            현재 가족 공유 기억:
            \(familyMemory.isEmpty ? "(없음)" : familyMemory)

            현재 개인 기억:
            \(personalMemory.isEmpty ? "(없음)" : personalMemory)

            ---

            JSON으로 출력해주세요:
            1. "title": 대화를 3~10자로 요약한 제목 (한글)
            2. "summary": 대화 내용 1~2문장 요약
            3. "memory": 대화 중 save_memory 도구로 저장되지 않았을 수 있는 보완 기억
               - "family": 가족 전체에 해당하는 새 정보 (없으면 null)
               - "personal": 개인에 해당하는 새 정보 (없으면 null)
               - 이미 기억에 있는 내용이나 대화 중 save_memory로 저장된 내용은 제외

            반드시 아래 형식만 출력:
            {"title": "...", "summary": "...", "memory": {"family": "- 항목" 또는 null, "personal": "- 항목" 또는 null}}
            """
        } else {
            let currentContext = vm.contextService.loadMemory()

            prompt = """
            다음은 방금 끝난 대화입니다:

            \(conversationText)

            ---

            현재 저장된 사용자 컨텍스트:
            \(currentContext.isEmpty ? "(없음)" : currentContext)

            ---

            JSON으로 출력해주세요:
            1. "title": 이 대화를 3~10자로 요약한 제목 (한글)
            2. "summary": 대화 내용 1~2문장 요약
            3. "memory": 이 대화에서 새로 알게 된 사실 추출
               - 기존 컨텍스트에 이미 있는 내용은 제외
               - 새로 알게 된 사실이 전혀 없으면 null

            반드시 아래 형식만 출력:
            {"title": "...", "summary": "...", "memory": "- 항목1\\n- 항목2" 또는 null}
            """
        }

        do {
            let response = try await callLLMSimple(provider: provider, apiKey: apiKey, prompt: prompt)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if let jsonData = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                let title = json["title"] as? String ?? Self.generateDefaultTitle(from: sessionMessages)
                let summary = json["summary"] as? String

                await MainActor.run {
                    vm.saveConversationWithTitle(title, summary: summary, userId: userId, messages: sessionMessages)
                }

                if hasProfiles {
                    if let memoryObj = json["memory"] as? [String: Any] {
                        if let familyMemory = memoryObj["family"] as? String, !familyMemory.isEmpty {
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            vm.contextService.appendFamilyMemory("\n<!-- \(timestamp) -->\n\(familyMemory)")
                            Log.app.info("가족 기억 보완: \(familyMemory.prefix(50))...")
                        }
                        if let personalMemory = memoryObj["personal"] as? String, !personalMemory.isEmpty, let uid = userId {
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            vm.contextService.appendUserMemory(userId: uid, content: "\n<!-- \(timestamp) -->\n\(personalMemory)")
                            Log.app.info("개인 기억 보완: \(personalMemory.prefix(50))...")
                        }
                    }
                } else {
                    if let memory = json["memory"] as? String, !memory.isEmpty {
                        let timestamp = ISO8601DateFormatter().string(from: Date())
                        let entry = "\n\n<!-- \(timestamp) -->\n\(memory)"
                        vm.contextService.appendMemory(entry)
                        Log.app.info("컨텍스트 추가됨: \(memory.prefix(50))...")

                        await compressContextIfNeeded()
                    }
                }
            } else {
                let defaultTitle = Self.generateDefaultTitle(from: sessionMessages)
                await MainActor.run {
                    vm.saveConversationWithTitle(defaultTitle, summary: nil, userId: userId, messages: sessionMessages)
                }
            }
        } catch {
            Log.app.error("컨텍스트 분석 실패: \(error.localizedDescription, privacy: .public)")
            let defaultTitle = Self.generateDefaultTitle(from: sessionMessages)
            await MainActor.run {
                vm.saveConversationWithTitle(defaultTitle, summary: nil, userId: userId, messages: sessionMessages)
            }
        }
    }

    // MARK: - Context Compression

    private func compressContextIfNeeded() async {
        guard let vm else { return }
        guard vm.settings.contextAutoCompress else { return }

        let currentSize = vm.contextService.memorySize
        let maxSize = vm.settings.contextMaxSize
        guard currentSize > maxSize else { return }

        Log.app.info("컨텍스트 압축 시작 (현재: \(currentSize) bytes, 제한: \(maxSize) bytes)")

        let providers: [LLMProvider] = [.openai, .anthropic, .zai]
        guard let provider = providers.first(where: { !vm.settings.apiKey(for: $0).isEmpty }) else {
            Log.app.warning("컨텍스트 압축 불가: API 키 없음")
            return
        }

        let apiKey = vm.settings.apiKey(for: provider)
        let currentContext = vm.contextService.loadMemory()

        let prompt = """
        다음은 사용자에 대해 기억하고 있는 정보입니다:

        \(currentContext)

        ---

        위 정보를 다음 기준으로 정리해주세요:
        - 중요도 순으로 정렬
        - 중복되거나 비슷한 내용은 하나로 통합
        - 오래되거나 불필요해 보이는 정보는 제거
        - 타임스탬프 주석(<!-- ... -->)은 제거
        - 결과물은 현재 크기의 절반 이하로
        - 마크다운 형식 유지
        - 절대 인사말이나 설명 없이 정리된 내용만 출력
        """

        do {
            let response = try await callLLMSimple(provider: provider, apiKey: apiKey, prompt: prompt)
            let compressed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if !compressed.isEmpty && compressed.count < currentContext.count {
                vm.contextService.saveMemory(compressed)
                let newSize = vm.contextService.memorySize
                Log.app.info("컨텍스트 압축 완료 (\(currentSize) → \(newSize) bytes)")
            }
        } catch {
            Log.app.error("컨텍스트 압축 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - LLM Simple Call

    private func callLLMSimple(provider: LLMProvider, apiKey: String, prompt: String) async throws -> String {
        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        switch provider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": Constants.LLM.openaiSimpleModel,
                "messages": [["role": "user", "content": prompt]],
                "max_tokens": Constants.LLM.simpleAnalysisMaxTokens,
            ]
        case .zai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": Constants.LLM.zaiSimpleModel,
                "messages": [["role": "user", "content": prompt]],
                "max_tokens": Constants.LLM.simpleAnalysisMaxTokens,
                "enable_thinking": false,
            ] as [String: Any]
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(Constants.LLM.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
            body = [
                "model": Constants.LLM.simpleAnalysisModel,
                "messages": [["role": "user", "content": prompt]],
                "max_tokens": Constants.LLM.simpleAnalysisMaxTokens,
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }

        switch provider {
        case .openai, .zai:
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        case .anthropic:
            if let content = json["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                return text
            }
        }
        return ""
    }

    // MARK: - Helpers

    static func generateDefaultTitle(from messages: [Message]) -> String {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.count <= 10 {
                return content
            } else {
                return String(content.prefix(10)) + "..."
            }
        }
        return "대화"
    }
}
