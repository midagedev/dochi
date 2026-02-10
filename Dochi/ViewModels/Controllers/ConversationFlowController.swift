import Foundation

@MainActor
final class ConversationFlowController {
    func sendLLMRequest(_ vm: DochiViewModel, messages: [Message], toolResults: [ToolResult]?) {
        let provider = vm.settings.llmProvider
        let model = selectModel(vm: vm, messages: messages)
        let apiKey = vm.settings.apiKey(for: provider)

        let hasProfiles = !vm.contextService.loadProfiles().isEmpty
        vm.builtInToolService.configureUserContext(
            contextService: hasProfiles ? vm.contextService : nil,
            currentUserId: vm.currentUserId
        )

        let recentSummaries = vm.conversationManager.buildRecentSummaries(for: vm.currentUserId, limit: 5)
        let systemPrompt = vm.settings.buildInstructions(
            currentUserName: vm.currentUserName,
            currentUserId: vm.currentUserId,
            recentSummaries: recentSummaries
        )

        vm.builtInToolService.configure(tavilyApiKey: vm.settings.tavilyApiKey, falaiApiKey: vm.settings.falaiApiKey)

        let tools: [[String: Any]]? = {
            var allTools: [MCPToolInfo] = []
            allTools.append(contentsOf: vm.builtInToolService.availableTools)
            allTools.append(contentsOf: vm.mcpService.availableTools)
            return allTools.isEmpty ? nil : allTools.map { $0.asDictionary }
        }()

        vm.llmService.sendMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            provider: provider,
            model: model,
            apiKey: apiKey,
            tools: tools,
            toolResults: toolResults
        )
    }

    private func selectModel(vm: DochiViewModel, messages: [Message]) -> String {
        // Agent-specific default model override
        let agentName = vm.settings.activeAgentName
        if let wsId = vm.settings.currentWorkspaceId, let cfg = vm.contextService.loadAgentConfig(workspaceId: wsId, agentName: agentName), let m = cfg.defaultModel, !m.isEmpty {
            return m
        } else if let cfg = vm.contextService.loadAgentConfig(agentName: agentName), let m = cfg.defaultModel, !m.isEmpty {
            return m
        }

        guard vm.settings.autoModelRoutingEnabled else { return vm.settings.llmModel }
        let provider = vm.settings.llmProvider
        let models = provider.models
        // Heuristics: short chat without tools → lightweight; otherwise default/heavier
        let lastUser = messages.last(where: { $0.role == .user })
        let length = lastUser?.content.count ?? 0
        let wantsLightweight = length < 120 && (vm.builtInToolService.availableTools.isEmpty) // tool specs empty in body leads to pure chat

        switch provider {
        case .openai:
            if wantsLightweight {
                if let mini = models.first(where: { $0.contains("mini") }) { return mini }
            }
            // prefer highest-capability listed first
            return models.first ?? vm.settings.llmModel
        case .anthropic:
            if wantsLightweight {
                if let haiku = models.first(where: { $0.lowercased().contains("haiku") }) { return haiku }
            }
            // prefer sonnet/opus if present
            if let sonnet = models.first(where: { $0.lowercased().contains("sonnet") }) { return sonnet }
            if let opus = models.first(where: { $0.lowercased().contains("opus") }) { return opus }
            return models.first ?? vm.settings.llmModel
        case .zai:
            return models.first ?? vm.settings.llmModel
        }
    }
}
