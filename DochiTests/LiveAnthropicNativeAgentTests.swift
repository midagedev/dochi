import AgentRuntimeCore
import AgentRuntimeTestKit
import XCTest
@testable import Dochi

/// Opt-in smoke test for the exact macOS app assembly path.
///
/// Run only with both environment variables present:
/// `DOCHI_LIVE_ANTHROPIC=1 ANTHROPIC_API_KEY=... xcodebuild test ...`
/// The credential is placed in an ephemeral `AgentSecretStore` under the same
/// namespace/account mapping as the app Keychain. The assembly, provider,
/// runtime, backend, tool and streaming paths are otherwise identical to the
/// shipped app. No secret is printed or interpolated into failures.
@MainActor
final class LiveAnthropicNativeAgentTests: XCTestCase {
    func testNativeAssemblyStreamsAnthropicToolRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DOCHI_LIVE_ANTHROPIC"] == "1",
              let apiKey = environment["ANTHROPIC_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("Set DOCHI_LIVE_ANTHROPIC=1 and ANTHROPIC_API_KEY to run the live smoke test.")
        }

        let defaults = UserDefaults.standard
        let keys = [
            "nativeProviderKind",
            "nativeModel",
            "nativeModel.anthropic",
            "nativeMemoryEnabled",
            "nativeAgentInstructions",
        ]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = saved[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(NativeModelProviderKind.anthropic.rawValue, forKey: "nativeProviderKind")
        defaults.set("claude-sonnet-5", forKey: "nativeModel")
        defaults.set("claude-sonnet-5", forKey: "nativeModel.anthropic")
        defaults.set(false, forKey: "nativeMemoryEnabled")
        defaults.set(
            "Use the current_time tool exactly once when requested, then answer concisely.",
            forKey: "nativeAgentInstructions"
        )

        let settings = AppSettings()
        let secretStore = InMemorySecretStore()
        await secretStore.saveSecret(
            apiKey,
            namespace: DochiNativeAgentAssembly.providerSecretNamespace,
            account: NativeModelProviderKind.anthropic.keychainAccount
        )
        let backend = try DochiNativeAgentAssembly.make(
            settings: settings,
            approvalBroker: AgentToolApprovalBroker(),
            secretStore: secretStore
        )
        backend.connect()
        try await waitUntilConnected(backend)

        let conversationID = "live-anthropic-\(UUID().uuidString.lowercased())"
        defer {
            backend.removeConversationHistory(
                conversationId: conversationID,
                user: "live-smoke-test"
            )
            backend.disconnect()
        }

        var deltaText = ""
        var startedCurrentTime = false
        var finishedCurrentTime = false
        var finalText = ""
        for try await event in backend.send(
            text: "Call current_time exactly once. After its result, include DOCHI_LIVE_OK in the final answer.",
            conversationId: conversationID,
            user: "live-smoke-test"
        ) {
            switch event {
            case .delta(let text):
                deltaText += text
            case .toolStarted(let name, _):
                if name == "current_time" { startedCurrentTime = true }
            case .toolFinished(let name, let isError, _):
                if name == "current_time" {
                    XCTAssertFalse(isError)
                    finishedCurrentTime = true
                }
            case .done(let text, _):
                finalText = text
            }
        }

        XCTAssertFalse(deltaText.isEmpty, "Expected at least one streamed text delta")
        XCTAssertTrue(startedCurrentTime, "Expected current_time tool start event")
        XCTAssertTrue(finishedCurrentTime, "Expected current_time tool completion event")
        XCTAssertTrue(finalText.contains("DOCHI_LIVE_OK"), "Expected live completion marker")
    }

    private func waitUntilConnected(_ backend: NativeAgentBackend) async throws {
        for _ in 0..<600 {
            switch backend.connectionState {
            case .connected:
                return
            case .failed(let message):
                throw LiveAnthropicSmokeError.connectionFailed(message)
            case .connecting, .disconnected:
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        throw LiveAnthropicSmokeError.connectionTimedOut
    }
}

private enum LiveAnthropicSmokeError: LocalizedError {
    case connectionFailed(String)
    case connectionTimedOut

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            "Native assembly failed to connect: \(message)"
        case .connectionTimedOut:
            "Native assembly did not connect within thirty seconds"
        }
    }
}
