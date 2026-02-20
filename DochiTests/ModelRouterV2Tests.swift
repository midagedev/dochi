import XCTest
@testable import Dochi

@MainActor
final class ModelRouterV2Tests: XCTestCase {
    func testSelectsTaskComplexityRouteForHeavyInput() async {
        let settings = makeSettings()
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"
        settings.taskRoutingEnabled = true
        settings.heavyModelProvider = LLMProvider.openai.rawValue
        settings.heavyModelName = "gpt-4o-mini"

        let router = ModelRouterV2(
            settings: settings,
            readinessProbe: { _ in true },
            supportsProvider: { _ in true }
        )

        let decision = await router.decide(input: ModelRoutingInput(
            userInput: "이 코드를 분석하고 리팩토링해줘",
            channel: .chat,
            includesImages: false
        ))

        XCTAssertEqual(decision.complexity, .heavy)
        XCTAssertEqual(decision.selectedTarget?.provider, .openai)
        XCTAssertEqual(decision.selectedTarget?.model, "gpt-4o-mini")
        XCTAssertEqual(decision.selectedTarget?.source, .taskComplexity)
    }

    func testSkipsUnhealthyPrimaryAndUsesConfiguredFallback() async {
        let settings = makeSettings()
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"
        settings.fallbackLLMProvider = LLMProvider.openai.rawValue
        settings.fallbackLLMModel = "gpt-4o-mini"

        let router = ModelRouterV2(
            settings: settings,
            readinessProbe: { provider in
                provider != .anthropic
            },
            supportsProvider: { _ in true }
        )

        let decision = await router.decide(input: ModelRoutingInput(
            userInput: "일정을 알려줘",
            channel: .chat,
            includesImages: false
        ))

        XCTAssertEqual(decision.selectedTarget?.provider, .openai)
        XCTAssertEqual(decision.selectedTarget?.source, .configuredFallback)

        let primaryEvaluation = decision.evaluations.first { $0.target.provider == .anthropic }
        XCTAssertEqual(primaryEvaluation?.status, .skippedProviderUnhealthy)
    }

    func testVoiceChannelPrefersLocalRealtimeCandidate() async {
        let settings = makeSettings()
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"
        settings.offlineFallbackEnabled = true
        settings.offlineFallbackProvider = LLMProvider.ollama.rawValue
        settings.offlineFallbackModel = "llama3.2"

        let router = ModelRouterV2(
            settings: settings,
            readinessProbe: { _ in true },
            supportsProvider: { _ in true }
        )

        let decision = await router.decide(input: ModelRoutingInput(
            userInput: "안녕",
            channel: .voice,
            includesImages: false
        ))

        XCTAssertEqual(decision.selectedTarget?.provider, .ollama)
        XCTAssertEqual(decision.selectedTarget?.source, .realtimeLocalPreference)
    }

    func testCircuitBreakerSkipsProviderUntilWindowExpires() async {
        let settings = makeSettings()
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"
        settings.fallbackLLMProvider = LLMProvider.openai.rawValue
        settings.fallbackLLMModel = "gpt-4o-mini"

        let router = ModelRouterV2(
            settings: settings,
            readinessProbe: { _ in true },
            supportsProvider: { _ in true },
            circuitPolicy: .init(failureThreshold: 2, openDuration: 60)
        )

        let now = Date(timeIntervalSince1970: 1_000)
        router.recordAttempt(provider: .anthropic, success: false, now: now)
        XCTAssertFalse(router.isCircuitOpen(for: .anthropic, now: now))

        router.recordAttempt(provider: .anthropic, success: false, now: now)
        XCTAssertTrue(router.isCircuitOpen(for: .anthropic, now: now.addingTimeInterval(1)))

        let duringOpen = await router.decide(
            input: ModelRoutingInput(userInput: "안녕", channel: .chat, includesImages: false),
            now: now.addingTimeInterval(1)
        )
        XCTAssertEqual(duringOpen.selectedTarget?.provider, .openai)
        let openEvaluation = duringOpen.evaluations.first { $0.target.provider == .anthropic }
        XCTAssertEqual(openEvaluation?.status, .skippedCircuitOpen)

        let afterWindow = await router.decide(
            input: ModelRoutingInput(userInput: "안녕", channel: .chat, includesImages: false),
            now: now.addingTimeInterval(61)
        )
        XCTAssertEqual(afterWindow.selectedTarget?.provider, .anthropic)
    }

    private func makeSettings() -> AppSettings {
        let settings = AppSettings()
        settings.taskRoutingEnabled = false
        settings.lightModelProvider = ""
        settings.lightModelName = ""
        settings.heavyModelProvider = ""
        settings.heavyModelName = ""
        settings.fallbackLLMProvider = ""
        settings.fallbackLLMModel = ""
        settings.offlineFallbackEnabled = false
        settings.offlineFallbackProvider = LLMProvider.ollama.rawValue
        settings.offlineFallbackModel = ""
        return settings
    }
}
