import Foundation

@MainActor
final class IntegrationsController {
    func setupTelegramBindings(_ vm: DochiViewModel) {
        vm.settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak vm] _ in
                guard let vm = vm else { return }
                vm.integrations.updateTelegramService(vm)
            }
            .store(in: &vm.cancellables)
        updateTelegramService(vm)
        vm.telegramService?.onDM = { [weak vm] event in
            Task { @MainActor in
                guard let vm = vm else { return }
                await vm.integrations.processTelegramDM(vm, chatId: event.chatId, username: event.username, text: event.text)
            }
        }
    }

    func updateTelegramService(_ vm: DochiViewModel) {
        guard let tg = vm.telegramService else { return }
        let enabled = vm.settings.telegramEnabled
        let token = vm.settings.telegramBotToken
        if enabled && !token.isEmpty { tg.start(token: token) } else { tg.stop() }
    }

    // MARK: - Telegram flow

    private func loadOrCreateTelegramConversation(_ vm: DochiViewModel, chatId: Int64, username: String?) -> Conversation {
        let userKey = "tg:\(chatId)"
        if let existing = vm.conversationService.list().first(where: { $0.userId == userKey }) { return existing }
        return Conversation(title: "Telegram DM \(username ?? String(chatId))", messages: [], userId: userKey)
    }

    private func sanitizeForTelegram(_ text: String) -> String { text.replacingOccurrences(of: "\u{0000}", with: "") }

    private func streamReply(_ vm: DochiViewModel, to chatId: Int64, initialText: String) async -> Int? {
        guard let telegram = vm.telegramService else { return nil }
        return await telegram.sendMessage(chatId: chatId, text: initialText)
    }

    private func updateReply(_ vm: DochiViewModel, chatId: Int64, messageId: Int, text: String) async {
        await vm.telegramService?.editMessageText(chatId: chatId, messageId: messageId, text: text)
    }

    private func buildSystemPromptForTelegram(_ vm: DochiViewModel) -> String {
        let recent = vm.conversationManager.buildRecentSummaries(for: nil, limit: 5)
        return vm.settings.buildInstructions(currentUserName: nil, currentUserId: nil, recentSummaries: recent)
    }

    func processTelegramDM(_ vm: DochiViewModel, chatId: Int64, username: String?, text: String) async {
        if let supa = vm.supabaseService as? SupabaseService, case .signedIn = vm.supabaseService.authState {
            await supa.ensureTelegramMapping(telegramUserId: chatId, username: username)
        }
        var conversation = loadOrCreateTelegramConversation(vm, chatId: chatId, username: username)
        conversation.messages.append(Message(role: .user, content: text))
        conversation.updatedAt = Date()
        vm.conversationService.save(conversation)
        vm.conversationManager.loadAll()

        let (provider, model) = (vm.settings.llmProvider, vm.settings.llmModel)
        let apiKey = vm.settings.apiKey(for: provider)
        guard !apiKey.isEmpty else {
            let warning = "LLM API 키가 설정되지 않았습니다. 설정에서 키를 추가해주세요."
            _ = await streamReply(vm, to: chatId, initialText: warning)
            return
        }

        let systemPrompt = buildSystemPromptForTelegram(vm)
        let llm = LLMService()
        vm.builtInToolService.configure(tavilyApiKey: vm.settings.tavilyApiKey, falaiApiKey: vm.settings.falaiApiKey)
        let hasProfiles = !vm.contextService.loadProfiles().isEmpty
        vm.builtInToolService.configureUserContext(contextService: hasProfiles ? vm.contextService : nil, currentUserId: nil)

        let builtInSpecs = vm.builtInToolService.availableTools.map { $0.asDictionary }
        let mcpSpecs = vm.mcpService.availableTools.map { $0.asDictionary }
        let toolSpecs = builtInSpecs + mcpSpecs
        var streamedText = ""
        var lastEditTime = Date.distantPast
        let editInterval: TimeInterval = 0.4
        var replyMessageId: Int?

        llm.onSentenceReady = { [weak vm] sentence in
            guard let vm else { return }
            streamedText += sentence
            let now = Date()
            if replyMessageId == nil {
                Task { @MainActor in
                    replyMessageId = await self.streamReply(vm, to: chatId, initialText: self.sanitizeForTelegram(streamedText))
                }
                lastEditTime = now
            } else if now.timeIntervalSince(lastEditTime) >= editInterval, let msgId = replyMessageId {
                lastEditTime = now
                Task { [weak vm] in
                    guard let vm = vm else { return }
                    await self.updateReply(vm, chatId: chatId, messageId: msgId, text: self.sanitizeForTelegram(streamedText))
                }
            }
        }

        var loopMessages = conversation.messages

        llm.onToolCallsReceived = { [weak vm] toolCalls in
            guard let vm else { return }
            Task { @MainActor in
                loopMessages.append(Message(role: .assistant, content: llm.partialResponse, toolCalls: toolCalls))
                var results: [ToolResult] = []
                for toolCall in toolCalls {
                    let argsDict = toolCall.arguments
                    do {
                        let isBuiltIn = vm.builtInToolService.availableTools.contains { $0.name == toolCall.name }
                        let toolResult: MCPToolResult = try await (isBuiltIn ? vm.builtInToolService.callTool(name: toolCall.name, arguments: argsDict) : vm.mcpService.callTool(name: toolCall.name, arguments: argsDict))
                        if let msgId = replyMessageId {
                            let snippet = String(toolResult.content.prefix(400))
                            streamedText += "\n\n🔧 \(toolCall.name): \(snippet)"
                            await self.updateReply(vm, chatId: chatId, messageId: msgId, text: self.sanitizeForTelegram(streamedText))
                        }
                        results.append(ToolResult(toolCallId: toolCall.id, content: toolResult.content, isError: toolResult.isError))
                    } catch {
                        let err = "Error: \(error.localizedDescription)"
                        if let msgId = replyMessageId {
                            streamedText += "\n\n🔧 \(toolCall.name): \(err)"
                            await self.updateReply(vm, chatId: chatId, messageId: msgId, text: self.sanitizeForTelegram(streamedText))
                        }
                        results.append(ToolResult(toolCallId: toolCall.id, content: err, isError: true))
                    }
                }
                for result in results { loopMessages.append(Message(role: .tool, content: result.content, toolCallId: result.toolCallId)) }
                llm.sendMessage(messages: loopMessages, systemPrompt: systemPrompt, provider: provider, model: model, apiKey: apiKey, tools: toolSpecs.isEmpty ? nil : toolSpecs, toolResults: nil)
            }
        }

        llm.onResponseComplete = { [weak vm] finalText in
            guard let vm else { return }
            let clean = self.sanitizeForTelegram(finalText.isEmpty ? streamedText : finalText)
            if let msgId = replyMessageId, !clean.isEmpty {
                Task { await self.updateReply(vm, chatId: chatId, messageId: msgId, text: clean) }
            } else if replyMessageId == nil {
                Task { _ = await self.streamReply(vm, to: chatId, initialText: clean) }
            }
            var conv = conversation
            conv.messages.append(Message(role: .assistant, content: clean))
            conv.updatedAt = Date()
            vm.conversationService.save(conv)
            vm.conversationManager.loadAll()
        }
        llm.sendMessage(messages: loopMessages, systemPrompt: systemPrompt, provider: provider, model: model, apiKey: apiKey, tools: toolSpecs.isEmpty ? nil : toolSpecs, toolResults: nil)
    }
}
