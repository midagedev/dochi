import Foundation
import os

/// 대화 히스토리 CRUD 및 요약 관리
@MainActor
final class ConversationManager {
    private weak var vm: DochiViewModel?
    private let conversationService: ConversationServiceProtocol

    init(viewModel: DochiViewModel, conversationService: ConversationServiceProtocol) {
        self.vm = viewModel
        self.conversationService = conversationService
    }

    func loadAll() {
        guard let vm else { return }
        vm.conversations = conversationService.list()
    }

    func load(_ conversation: Conversation) {
        guard let vm else { return }
        if !vm.messages.isEmpty {
            let sessionMessages = vm.messages
            let sessionUserId = vm.currentUserId
            Task {
                await vm.contextAnalyzer.saveAndAnalyzeConversation(sessionMessages, userId: sessionUserId)
            }
        }

        vm.currentConversationId = conversation.id
        vm.messages = conversation.messages
    }

    func delete(id: UUID) {
        guard let vm else { return }
        conversationService.delete(id: id)
        vm.conversations.removeAll { $0.id == id }

        if vm.currentConversationId == id {
            vm.currentConversationId = nil
            vm.messages.removeAll()
        }
    }

    func save(title: String, summary: String?, userId: UUID?, messages: [Message]) {
        guard let vm else { return }
        let id = vm.currentConversationId ?? UUID()
        let now = Date()

        let conversation = Conversation(
            id: id,
            title: title,
            messages: messages,
            createdAt: vm.conversations.first(where: { $0.id == id })?.createdAt ?? now,
            updatedAt: now,
            userId: userId?.uuidString,
            summary: summary
        )

        conversationService.save(conversation)
        loadAll()
        Log.app.info("대화 저장됨: \(title)")
    }

    func buildRecentSummaries(for userId: UUID?, limit: Int) -> String? {
        let allConversations = conversationService.list()
        let userIdString = userId?.uuidString

        let relevant: [Conversation]
        if let userIdString {
            relevant = allConversations.filter { $0.userId == userIdString && $0.summary != nil }
        } else {
            relevant = allConversations.filter { $0.summary != nil }
        }

        let recent = relevant.prefix(limit)
        guard !recent.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"

        return recent.map { conv in
            let date = formatter.string(from: conv.updatedAt)
            return "- [\(date)] \(conv.summary ?? conv.title)"
        }.joined(separator: "\n")
    }
}
