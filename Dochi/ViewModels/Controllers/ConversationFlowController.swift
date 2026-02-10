import Foundation

@MainActor
final class ConversationFlowController {
    func sendLLMRequest(_ vm: DochiViewModel, messages: [Message], toolResults: [ToolResult]?) {
        let provider = vm.settings.llmProvider
        let model = vm.settings.llmModel
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
}

