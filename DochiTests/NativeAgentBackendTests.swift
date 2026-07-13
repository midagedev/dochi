import AgentRuntimeCore
import AgentRuntimeTestKit
import XCTest
@testable import Dochi

@MainActor
final class NativeAgentBackendTests: XCTestCase {
    func testPreRunHookCompletesBeforeProviderRequest() async throws {
        let provider = ScriptedModelProvider(
            identifier: "native-test",
            scripts: [[.textDelta("완료"), .finish(.stop)]]
        )
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(providers: [provider]),
            tools: try AgentToolRegistry()
        )
        var didPrepareMemory = false
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: AgentDefinition(
                id: "dochi-native",
                providerID: "native-test",
                model: "test",
                instructions: "테스트"
            ),
            preRunHook: {
                didPrepareMemory = true
            }
        )
        backend.connect()

        _ = try await collect(backend.send(
            text: "질문",
            conversationId: "conversation",
            user: "user"
        ))

        XCTAssertTrue(didPrepareMemory)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testMapsRuntimeEventsAndKeepsConversationHistory() async throws {
        let provider = ScriptedModelProvider(
            identifier: "native-test",
            scripts: [
                [.textDelta("첫 답변"), .finish(.stop)],
                [.textDelta("둘째 답변"), .finish(.stop)],
            ]
        )
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(providers: [provider]),
            tools: try AgentToolRegistry()
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: AgentDefinition(
                id: "dochi-native",
                providerID: "native-test",
                model: "test",
                instructions: "테스트"
            )
        )
        backend.connect()

        let first = try await collect(backend.send(
            text: "첫 질문",
            conversationId: "conversation",
            user: "user"
        ))
        let second = try await collect(backend.send(
            text: "둘째 질문",
            conversationId: "conversation",
            user: "user"
        ))

        XCTAssertEqual(first.compactMap(\.doneText), ["첫 답변"])
        XCTAssertEqual(second.compactMap(\.doneText), ["둘째 답변"])
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[1].messages.contains { $0.role == .assistant && $0.text == "첫 답변" })
        XCTAssertTrue(requests[1].messages.contains { $0.role == .user && $0.text == "둘째 질문" })
    }

    func testDisconnectedBackendFailsWithoutCallingProvider() async throws {
        let provider = ScriptedModelProvider(identifier: "native-test", scripts: [])
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(providers: [provider]),
            tools: try AgentToolRegistry()
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: AgentDefinition(
                id: "dochi-native",
                providerID: "native-test",
                model: "test",
                instructions: "테스트"
            )
        )

        do {
            _ = try await collect(backend.send(text: "질문", conversationId: "c", user: nil))
            XCTFail("Expected not-connected error")
        } catch is NativeAgentBackendError {
            // Expected.
        }
        let requestCount = await provider.requests.count
        XCTAssertEqual(requestCount, 0)
    }

    func testEmptyModelFailsBeforeCallingProvider() async throws {
        let provider = ScriptedModelProvider(identifier: "native-test", scripts: [])
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(providers: [provider]),
            tools: try AgentToolRegistry()
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: AgentDefinition(
                id: "dochi-native",
                providerID: "native-test",
                model: "   ",
                instructions: "테스트"
            )
        )
        backend.connect()

        do {
            _ = try await collect(backend.send(text: "질문", conversationId: "c", user: nil))
            XCTFail("Expected missing-model error")
        } catch let error as NativeAgentBackendError {
            XCTAssertEqual(error.errorDescription, NativeAgentBackendError.missingModel.errorDescription)
        }
        let requestCount = await provider.requests.count
        XCTAssertEqual(requestCount, 0)
    }

    func testPreparedHistoryIsIncludedInFirstRequest() async throws {
        let provider = ScriptedModelProvider(
            identifier: "native-test",
            scripts: [[.textDelta("이어진 답변"), .finish(.stop)]]
        )
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(providers: [provider]),
            tools: try AgentToolRegistry()
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: AgentDefinition(
                id: "dochi-native",
                providerID: "native-test",
                model: "test",
                instructions: "테스트"
            )
        )
        backend.replaceConversationHistory(
            [
                DochiAgentHistoryMessage(role: .user, text: "저장된 질문"),
                DochiAgentHistoryMessage(role: .assistant, text: "저장된 답변"),
            ],
            conversationId: "restored",
            user: nil
        )
        backend.connect()

        _ = try await collect(backend.send(
            text: "후속 질문",
            conversationId: "restored",
            user: nil
        ))

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].messages.contains {
            $0.role == .assistant && $0.text == "저장된 답변"
        })
        XCTAssertEqual(requests[0].messages.last?.text, "후속 질문")
    }

    func testMatchingProtectedCheckpointRestoresProviderContinuation() async throws {
        let provider = ScriptedModelProvider(
            identifier: "native-test",
            scripts: [[.textDelta("이어진 답변"), .finish(.stop)]]
        )
        let checkpointStore = InMemoryAgentCheckpointStore()
        let providerContinuation = ProviderContinuation(
            providerIdentifier: "native-test",
            format: "test-continuation",
            payload: .object(["opaque": .string("signed-payload")])
        )
        await checkpointStore.save(makeCheckpoint(
            messages: [
                AgentMessage(role: .user, text: "저장된 질문"),
                AgentMessage(
                    role: .assistant,
                    content: [.text("저장된 답변")],
                    providerContinuation: providerContinuation
                ),
            ]
        ))
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(providers: [provider]),
            tools: try AgentToolRegistry()
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: makeAgent(),
            checkpointStore: checkpointStore
        )
        backend.replaceConversationHistory(
            [
                DochiAgentHistoryMessage(role: .user, text: "저장된 질문"),
                DochiAgentHistoryMessage(role: .assistant, text: "저장된 답변"),
            ],
            conversationId: "restored",
            user: "user"
        )
        backend.connect()

        _ = try await collect(backend.send(
            text: "후속 질문",
            conversationId: "restored",
            user: "user"
        ))

        let requests = await provider.requests
        let restoredAssistant = try XCTUnwrap(requests[0].messages.first {
            $0.role == .assistant && $0.text == "저장된 답변"
        })
        XCTAssertEqual(restoredAssistant.providerContinuation, providerContinuation)
    }

    func testCheckpointTranscriptMismatchDoesNotRestoreProviderContinuation() async throws {
        let provider = ScriptedModelProvider(
            identifier: "native-test",
            scripts: [[.textDelta("새 답변"), .finish(.stop)]]
        )
        let checkpointStore = InMemoryAgentCheckpointStore()
        await checkpointStore.save(makeCheckpoint(
            messages: [
                AgentMessage(role: .user, text: "저장된 질문"),
                AgentMessage(
                    role: .assistant,
                    content: [.text("이전 답변")],
                    providerContinuation: ProviderContinuation(
                        providerIdentifier: "native-test",
                        format: "test-continuation",
                        payload: .string("must-not-leak")
                    )
                ),
            ]
        ))
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(providers: [provider]),
            tools: try AgentToolRegistry()
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: makeAgent(),
            checkpointStore: checkpointStore
        )
        backend.replaceConversationHistory(
            [
                DochiAgentHistoryMessage(role: .user, text: "저장된 질문"),
                DochiAgentHistoryMessage(role: .assistant, text: "수정된 답변"),
            ],
            conversationId: "restored",
            user: "user"
        )
        backend.connect()

        _ = try await collect(backend.send(
            text: "후속 질문",
            conversationId: "restored",
            user: "user"
        ))

        let requests = await provider.requests
        let visibleAssistant = try XCTUnwrap(requests[0].messages.first {
            $0.role == .assistant && $0.text == "수정된 답변"
        })
        XCTAssertNil(visibleAssistant.providerContinuation)
        XCTAssertFalse(requests[0].messages.contains { $0.text == "이전 답변" })
    }

    func testInterruptedToolCheckpointIsNotUsedAsCompletedConversationHistory() async throws {
        let provider = ScriptedModelProvider(
            identifier: "native-test",
            scripts: [[.textDelta("새 답변"), .finish(.stop)]]
        )
        let checkpointStore = InMemoryAgentCheckpointStore()
        await checkpointStore.save(makeCheckpoint(
            messages: [
                AgentMessage(role: .user, text: "저장된 질문"),
                AgentMessage(
                    role: .assistant,
                    content: [.text("저장된 답변")],
                    providerContinuation: ProviderContinuation(
                        providerIdentifier: "native-test",
                        format: "test-continuation",
                        payload: .string("must-not-resume")
                    )
                ),
                AgentMessage(
                    role: .assistant,
                    content: [.toolCall(AgentToolCall(
                        id: "unfinished-call",
                        name: "current_time",
                        arguments: .object([:])
                    ))]
                ),
            ]
        ))
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(providers: [provider]),
            tools: try AgentToolRegistry()
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: makeAgent(),
            checkpointStore: checkpointStore
        )
        backend.replaceConversationHistory(
            [
                DochiAgentHistoryMessage(role: .user, text: "저장된 질문"),
                DochiAgentHistoryMessage(role: .assistant, text: "저장된 답변"),
            ],
            conversationId: "restored",
            user: "user"
        )
        backend.connect()

        _ = try await collect(backend.send(
            text: "후속 질문",
            conversationId: "restored",
            user: "user"
        ))

        let requests = await provider.requests
        let restoredAssistant = try XCTUnwrap(requests[0].messages.first {
            $0.role == .assistant && $0.text == "저장된 답변"
        })
        XCTAssertNil(restoredAssistant.providerContinuation)
        XCTAssertFalse(requests[0].messages.contains { !$0.toolCalls.isEmpty })
    }

    func testRemovingConversationDeletesAllCheckpointsForThatIdentity() async throws {
        let checkpointStore = InMemoryAgentCheckpointStore()
        let first = makeCheckpoint(createdAt: .now.addingTimeInterval(-1))
        let second = makeCheckpoint(createdAt: .now)
        let otherUser = makeCheckpoint(userID: "other-user")
        await checkpointStore.save(first)
        await checkpointStore.save(second)
        await checkpointStore.save(otherUser)
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(),
            tools: try AgentToolRegistry()
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            agent: makeAgent(),
            checkpointStore: checkpointStore
        )

        backend.removeConversationHistory(conversationId: "restored", user: "user")

        for _ in 0..<100 {
            if await checkpointStore.latest(
                appID: "com.hckim.dochi",
                userID: "user",
                sessionID: "restored",
                agentID: "dochi-native"
            ) == nil {
                break
            }
            await Task.yield()
        }
        let deleted = await checkpointStore.latest(
            appID: "com.hckim.dochi",
            userID: "user",
            sessionID: "restored",
            agentID: "dochi-native"
        )
        let retained = await checkpointStore.latest(
            appID: "com.hckim.dochi",
            userID: "other-user",
            sessionID: "restored",
            agentID: "dochi-native"
        )
        XCTAssertNil(deleted)
        XCTAssertEqual(retained?.id, otherUser.id)
    }

    func testDisconnectWinsOverSlowConfigurationReload() async throws {
        let runtime = AgentRuntime(
            providers: ModelProviderRegistry(),
            tools: try AgentToolRegistry()
        )
        let agent = AgentDefinition(
            id: "dochi-native",
            providerID: "native-test",
            model: "test",
            instructions: "테스트"
        )
        let backend = NativeAgentBackend(
            runtime: runtime,
            definitionProvider: { agent },
            configurationReloader: {
                try await Task.sleep(for: .milliseconds(100))
            }
        )

        backend.connect()
        backend.disconnect()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(backend.connectionState, .disconnected)
    }

    private func collect(
        _ stream: AsyncThrowingStream<DochiAgentEvent, Error>
    ) async throws -> [DochiAgentEvent] {
        var events: [DochiAgentEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private func makeAgent() -> AgentDefinition {
        AgentDefinition(
            id: "dochi-native",
            providerID: "native-test",
            model: "test",
            instructions: "테스트"
        )
    }

    private func makeCheckpoint(
        userID: String = "user",
        messages: [AgentMessage] = [
            AgentMessage(role: .user, text: "저장된 질문"),
            AgentMessage(role: .assistant, text: "저장된 답변"),
        ],
        createdAt: Date = .now
    ) -> AgentRunCheckpoint {
        AgentRunCheckpoint(
            runID: UUID(),
            sessionID: "restored",
            appID: "com.hckim.dochi",
            userID: userID,
            agentID: "dochi-native",
            providerID: "native-test",
            model: "test",
            messages: messages,
            stepCount: 1,
            toolCallCount: 0,
            usage: AgentTokenUsage(),
            createdAt: createdAt
        )
    }
}

private extension DochiAgentEvent {
    var doneText: String? {
        guard case .done(let text, _) = self else { return nil }
        return text
    }
}
