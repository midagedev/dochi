import Foundation
import os

/// 도구 실행 루프 관리
@MainActor
final class ToolExecutor {
    private weak var vm: DochiViewModel?

    let maxToolIterations = 10

    init(viewModel: DochiViewModel) {
        self.vm = viewModel
    }

    func executeToolLoop(toolCalls: [ToolCall]) async {
        guard let vm else { return }
        var iteration = 0
        var currentToolCalls = toolCalls
        var collectedImageURLs: [URL] = []

        while !currentToolCalls.isEmpty && iteration < maxToolIterations {
            iteration += 1
            Log.tool.info("Tool loop iteration \(iteration), \(currentToolCalls.count) tools to execute")

            let assistantMessage = Message(
                role: .assistant,
                content: vm.llmService.partialResponse,
                toolCalls: currentToolCalls
            )
            vm.toolLoopMessages.append(assistantMessage)

            var results: [ToolResult] = []
            for toolCall in currentToolCalls {
                vm.currentToolExecution = toolCall.name
                vm.state = .executingTool(toolCall.name)
                Log.tool.info("Executing tool: \(toolCall.name)")

                do {
                    let isBuiltIn = vm.builtInToolService.availableTools.contains { $0.name == toolCall.name }
                    let toolResult: MCPToolResult

                    if isBuiltIn {
                        toolResult = try await vm.builtInToolService.callTool(
                            name: toolCall.name,
                            arguments: toolCall.arguments
                        )
                    } else {
                        toolResult = try await vm.mcpService.callTool(
                            name: toolCall.name,
                            arguments: toolCall.arguments
                        )
                    }

                    collectedImageURLs.append(contentsOf: Self.extractImageURLs(from: toolResult.content))

                    results.append(ToolResult(
                        toolCallId: toolCall.id,
                        content: toolResult.content,
                        isError: toolResult.isError
                    ))
                    Log.tool.info("Tool \(toolCall.name) completed")
                } catch {
                    results.append(ToolResult(
                        toolCallId: toolCall.id,
                        content: "Error: \(error.localizedDescription)",
                        isError: true
                    ))
                    Log.tool.error("Tool \(toolCall.name, privacy: .public) failed: \(error, privacy: .public)")
                }
            }

            vm.currentToolExecution = nil
            vm.state = .processing

            for result in results {
                vm.toolLoopMessages.append(Message(
                    role: .tool,
                    content: result.content,
                    toolCallId: result.toolCallId
                ))
            }

            let imageURLs = collectedImageURLs
            currentToolCalls = await withCheckedContinuation { continuation in
                var completed = false

                vm.llmService.onToolCallsReceived = { [weak vm] toolCalls in
                    guard vm != nil, !completed else { return }
                    completed = true
                    continuation.resume(returning: toolCalls)
                }

                vm.llmService.onResponseComplete = { [weak vm] response in
                    guard let vm, !completed else { return }
                    completed = true
                    vm.messages = vm.toolLoopMessages
                    vm.messages.append(Message(
                        role: .assistant,
                        content: response,
                        imageURLs: imageURLs.isEmpty ? nil : imageURLs
                    ))
                    continuation.resume(returning: [])
                }

                vm.sendLLMRequest(messages: vm.toolLoopMessages, toolResults: nil)
            }
        }

        if iteration >= maxToolIterations {
            Log.tool.error("Tool loop reached max iterations (\(self.maxToolIterations))")
            vm.errorMessage = "도구 실행 횟수가 최대치(\(maxToolIterations))에 도달했습니다."
        }

        vm.setupLLMCallbacks()
    }

    // MARK: - Helpers

    static func extractImageURLs(from content: String) -> [URL] {
        let pattern = #"!\[.*?\]\((.*?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Log.app.error("이미지 URL 정규식 컴파일 실패")
            return []
        }
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)
        return matches.compactMap { match in
            guard let urlRange = Range(match.range(at: 1), in: content) else { return nil }
            return URL(string: String(content[urlRange]))
        }
    }
}
