import Foundation
import os

// MARK: - Shadow Sub-Agent Orchestrator

/// Shadow sub-agent planner-only orchestrator.
///
/// 설계 원칙:
/// 1. **Single-agent first**: 기본 실행 권한은 항상 부모 런에 둔다.
/// 2. **Planner-only first**: 서브는 계획 생성만 수행, 실제 tool 호출은 부모가 수행.
/// 3. **Deterministic routing**: 서브 런 생성 조건은 코드 규칙 기반 (LLM 임의 판단 금지).
/// 4. **Bounded complexity**: depth/time/token/call 수를 하드리밋으로 제한.
/// 5. **Trace-first**: parent/sub 공통 trace 스키마 기반.
@MainActor
@Observable
final class ShadowSubAgentOrchestrator: ShadowSubAgentOrchestratorProtocol {

    // MARK: - Properties

    private(set) var config: ShadowSubAgentConfig
    private var stateMachine = ShadowPlannerStateMachine()
    private(set) var recentTraceEnvelopes: [TraceEnvelope] = []
    private(set) var recentDebugBundles: [DebugBundle] = []

    /// 내부 RNG (sampling gate용). 테스트 시 시드 고정 가능.
    var randomSource: () -> Double = { Double.random(in: 0..<1) }

    /// Planner 구현. 기본은 로컬 휴리스틱 planner.
    /// LLM 기반 planner로 교체 가능.
    var plannerImplementation: (@Sendable (ShadowPlannerInput) async -> ShadowPlannerResult)?

    private static let maxTraceEnvelopes = 100
    private static let maxDebugBundles = 100

    // MARK: - Init

    init(config: ShadowSubAgentConfig = .default) {
        self.config = config
    }

    // MARK: - State

    var currentState: ShadowPlannerState {
        stateMachine.state
    }

    // MARK: - shouldSpawn

    func shouldSpawn(context: ShadowTriggerContext) -> (spawn: Bool, triggerCode: ShadowTriggerCode?) {
        // Kill switch
        guard config.shadowSubAgentEnabled else {
            Log.tool.debug("Shadow sub-agent disabled (kill switch)")
            return (false, nil)
        }

        // Depth guard
        guard context.currentDepth < config.maxDepth else {
            Log.tool.debug("Shadow sub-agent depth exceeded: \(context.currentDepth) >= \(self.config.maxDepth)")
            return (false, nil)
        }

        // Turn limit guard
        guard context.subRunsThisTurn < config.maxSubRunsPerTurn else {
            Log.tool.debug("Shadow sub-agent turn limit reached: \(context.subRunsThisTurn) >= \(self.config.maxSubRunsPerTurn)")
            return (false, nil)
        }

        // State guard — 이미 활성 상태이면 spawn하지 않음
        guard !stateMachine.state.isActive else {
            Log.tool.debug("Shadow sub-agent already active: \(self.stateMachine.state.rawValue)")
            return (false, nil)
        }

        // Evaluate trigger rules
        let triggerCode = evaluateTrigger(context: context)
        guard let code = triggerCode else {
            return (false, nil)
        }

        // Sampling gate
        let roll = randomSource()
        guard roll < config.shadowSubAgentSampleRate else {
            Log.tool.debug("Shadow sub-agent sampling gate rejected: \(roll) >= \(self.config.shadowSubAgentSampleRate)")
            return (false, nil)
        }

        Log.tool.info("Shadow sub-agent spawn approved: trigger=\(code.rawValue)")
        return (true, code)
    }

    // MARK: - runPlanner

    func runPlanner(input: ShadowPlannerInput) async -> ShadowPlannerResult {
        // State transition: idle -> triggered -> shadowPlanning
        guard stateMachine.transition(to: .triggered) else {
            Log.tool.warning("Shadow planner invalid transition to triggered from \(self.stateMachine.state.rawValue)")
            return .error("Invalid state transition to triggered")
        }
        guard stateMachine.transition(to: .shadowPlanning) else {
            Log.tool.warning("Shadow planner invalid transition to shadowPlanning from \(self.stateMachine.state.rawValue)")
            return .error("Invalid state transition to shadowPlanning")
        }

        let startTime = Date()
        let wallTimeBudget = config.wallTimeMs

        // Execute planner with timeout
        let result: ShadowPlannerResult
        if let plannerImpl = plannerImplementation {
            result = await executePlannerWithTimeout(
                implementation: plannerImpl,
                input: input,
                wallTimeMs: wallTimeBudget
            )
        } else {
            // Default: 로컬 휴리스틱 planner
            result = executeLocalPlanner(input: input)
        }

        let elapsed = Date().timeIntervalSince(startTime) * 1000.0

        // State transition based on result
        switch result {
        case .success:
            _ = stateMachine.transition(to: .parentDecision)
            Log.tool.info("Shadow planner completed in \(String(format: "%.1f", elapsed))ms")
        case .timeout:
            _ = stateMachine.transition(to: .plannerTimeout)
            Log.tool.warning("Shadow planner timed out after \(String(format: "%.1f", elapsed))ms")
        case .error(let message):
            _ = stateMachine.transition(to: .plannerError)
            Log.tool.warning("Shadow planner error: \(message)")
        }

        return result
    }

    // MARK: - mergeDecision

    func mergeDecision(decision: ShadowDecision, traceEnvelopeId: UUID) -> ShadowMergeResult {
        // 병합 제약 적용
        let limitedAlternatives = Array(decision.alternatives.prefix(config.maxMergeAlternatives))
        let limitedSummary: String
        // 토큰 수 근사: 1 토큰 ~ 4 문자 (영어 기준), 한국어는 더 적지만 보수적으로
        let maxChars = config.maxReasonTokens * 4
        if decision.reasonSummary.count > maxChars {
            limitedSummary = String(decision.reasonSummary.prefix(maxChars))
        } else {
            limitedSummary = decision.reasonSummary
        }

        let accepted = decision.isValid && decision.confidence > 0.3

        // State transition
        if accepted {
            _ = stateMachine.transition(to: .parentExecution)
        } else {
            _ = stateMachine.transition(to: .parentFallback)
        }

        let mergeResult = ShadowMergeResult(
            selectedTool: decision.primaryTool,
            alternatives: limitedAlternatives,
            reasonSummary: limitedSummary,
            accepted: accepted,
            traceEnvelopeId: traceEnvelopeId
        )

        // Close state machine
        _ = stateMachine.transition(to: .closed)

        Log.tool.info("Shadow merge: tool=\(decision.primaryTool) accepted=\(accepted) confidence=\(String(format: "%.2f", decision.confidence))")

        return mergeResult
    }

    // MARK: - Full Pipeline

    /// 전체 파이프라인 실행: shouldSpawn -> runPlanner -> mergeDecision.
    ///
    /// trace envelope 및 debug bundle을 자동으로 생성/기록한다.
    func executePipeline(
        context: ShadowTriggerContext,
        input: ShadowPlannerInput
    ) async -> ShadowMergeResult? {
        let triggerStart = Date()

        // 1. Spawn check
        let (shouldSpawn, triggerCode) = shouldSpawn(context: context)
        guard shouldSpawn, let code = triggerCode else {
            return nil
        }

        let triggerMs = Date().timeIntervalSince(triggerStart) * 1000.0

        // Create trace envelope
        var envelope = TraceEnvelope(
            parentRunId: context.parentRunId,
            conversationId: context.conversationId,
            triggerCode: code
        )

        // 2. Run planner
        let plannerStart = Date()
        let plannerInput = ShadowPlannerInput(
            userMessageSummary: input.userMessageSummary,
            availableTools: input.availableTools,
            recentFailures: input.recentFailures,
            triggerCode: code
        )

        let result = await runPlanner(input: plannerInput)
        let plannerMs = Date().timeIntervalSince(plannerStart) * 1000.0

        // Wall time guardrail check
        if plannerMs > Double(config.wallTimeMs) {
            envelope.guardrailHit = true
            envelope.guardrailEvents.append(GuardrailEvent(
                rule: "wallTime",
                actualValue: String(format: "%.0f", plannerMs),
                limitValue: String(config.wallTimeMs)
            ))
        }

        // 3. Process result
        let mergeStart = Date()
        let mergeResult: ShadowMergeResult
        let parentFinalDecision: String
        let plannerOutputJSON: String?

        switch result {
        case .success(let decision):
            envelope.selectedTool = decision.primaryTool
            plannerOutputJSON = decision.toJSON()

            let merged = mergeDecision(decision: decision, traceEnvelopeId: envelope.id)
            envelope.acceptedByParent = merged.accepted

            if !merged.accepted {
                envelope.failureCode = .parentOverride
            }

            parentFinalDecision = merged.accepted ? "accepted" : "override"
            mergeResult = merged

        case .timeout:
            envelope.failureCode = .plannerTimeout
            envelope.guardrailHit = true
            envelope.guardrailEvents.append(GuardrailEvent(
                rule: "wallTime",
                actualValue: String(format: "%.0f", plannerMs),
                limitValue: String(config.wallTimeMs)
            ))
            plannerOutputJSON = nil
            parentFinalDecision = "fallback_timeout"

            // Transition to closed via fallback path
            _ = stateMachine.transition(to: .parentFallback)
            _ = stateMachine.transition(to: .closed)

            return nil

        case .error(let message):
            envelope.failureCode = .plannerLowConfidence
            plannerOutputJSON = nil
            parentFinalDecision = "fallback_error: \(message)"

            // Transition to closed via fallback path
            _ = stateMachine.transition(to: .parentFallback)
            _ = stateMachine.transition(to: .closed)

            return nil
        }

        let mergeMs = Date().timeIntervalSince(mergeStart) * 1000.0
        let totalMs = Date().timeIntervalSince(triggerStart) * 1000.0

        // Finalize envelope
        envelope.completedAt = Date()
        appendTraceEnvelope(envelope)

        // Create debug bundle
        let debugBundle = DebugBundle(
            traceEnvelopeId: envelope.id,
            inputSummary: sanitizeInput(input.userMessageSummary),
            plannerOutputJSON: plannerOutputJSON,
            parentFinalDecision: parentFinalDecision,
            latencyBreakdown: ShadowLatencyBreakdown(
                triggerEvaluationMs: triggerMs,
                plannerCallMs: plannerMs,
                mergeDecisionMs: mergeMs,
                totalMs: totalMs
            ),
            tokenBreakdown: ShadowTokenBreakdown(),
            guardrailEvents: envelope.guardrailEvents
        )
        appendDebugBundle(debugBundle)

        Log.tool.info("Shadow pipeline completed: \(String(format: "%.1f", totalMs))ms tool=\(mergeResult.selectedTool)")

        return mergeResult
    }

    // MARK: - Config

    func updateConfig(_ newConfig: ShadowSubAgentConfig) {
        config = newConfig
        Log.tool.info("Shadow sub-agent config updated: enabled=\(newConfig.shadowSubAgentEnabled) sampleRate=\(newConfig.shadowSubAgentSampleRate)")
    }

    func resetState() {
        stateMachine.reset()
        Log.tool.info("Shadow sub-agent state reset")
    }

    // MARK: - Private: Trigger Evaluation

    /// Deterministic 트리거 규칙 평가.
    private func evaluateTrigger(context: ShadowTriggerContext) -> ShadowTriggerCode? {
        // Rule 1: 후보 툴 수 >= minCandidateCount, 상위 confidence gap < threshold
        if context.candidateTools.count >= config.minCandidateCount {
            let sortedConfidences = context.candidateConfidences.values.sorted(by: >)
            if sortedConfidences.count >= 2 {
                let gap = sortedConfidences[0] - sortedConfidences[1]
                if gap < config.confidenceGapThreshold {
                    Log.tool.debug("Shadow trigger: AMBIGUOUS_CANDIDATES (gap=\(String(format: "%.3f", gap)))")
                    return .ambiguousCandidates
                }
            }
        }

        // Rule 2: 동일 턴에서 제어 툴 재호출 감지
        let controlCalls = context.toolCallsThisTurn.filter { config.controlToolNames.contains($0) }
        if controlCalls.count >= 2 {
            Log.tool.debug("Shadow trigger: CONTROL_TOOL_REUSE (count=\(controlCalls.count))")
            return .controlToolReuse
        }

        // Rule 3: 최근 N턴 내 failure ratio >= threshold
        let windowResults = context.recentToolResults.suffix(config.failureWindowTurns * 3) // 턴당 평균 3 calls 가정
        if !windowResults.isEmpty {
            let failures = windowResults.filter { !$0.success }.count
            let ratio = Double(failures) / Double(windowResults.count)
            if ratio >= config.failureRatioThreshold {
                Log.tool.debug("Shadow trigger: HIGH_FAILURE_RATIO (ratio=\(String(format: "%.2f", ratio)))")
                return .highFailureRatio
            }
        }

        return nil
    }

    // MARK: - Private: Local Planner

    /// 로컬 휴리스틱 planner (LLM 호출 없이 규칙 기반).
    private func executeLocalPlanner(input: ShadowPlannerInput) -> ShadowPlannerResult {
        guard !input.availableTools.isEmpty else {
            return .error("No available tools")
        }

        // 실패한 도구 제외
        let failedToolNames = Set(input.recentFailures.map(\.toolName))
        let viableTools = input.availableTools.filter { !failedToolNames.contains($0.name) }

        guard let primary = viableTools.first else {
            // 모든 도구가 실패한 경우 첫 번째 도구를 선택
            let fallbackTool = input.availableTools[0]
            return .success(ShadowDecision(
                primaryTool: fallbackTool.name,
                reasonCodes: [.defaultFallback],
                reasonSummary: "모든 후보 도구가 최근 실패. 기본값으로 \(fallbackTool.name) 선택.",
                confidence: 0.2,
                riskLevel: .high
            ))
        }

        let alternatives = viableTools.dropFirst().prefix(ShadowDecision.maxAlternatives).map { tool in
            ToolAlternative(
                name: tool.name,
                confidence: 0.5,
                reason: tool.description
            )
        }

        let reasonCode: ShadowReasonCode
        switch input.triggerCode {
        case .highFailureRatio:
            reasonCode = .failureRecovery
        case .controlToolReuse:
            reasonCode = .contextInference
        case .ambiguousCandidates:
            reasonCode = .bestIntentMatch
        }

        return .success(ShadowDecision(
            primaryTool: primary.name,
            alternatives: Array(alternatives),
            reasonCodes: [reasonCode],
            reasonSummary: "로컬 휴리스틱: \(primary.name) 선택 (트리거: \(input.triggerCode.rawValue))",
            confidence: 0.7,
            riskLevel: failedToolNames.isEmpty ? .low : .medium
        ))
    }

    // MARK: - Private: Planner with Timeout

    /// 외부 planner를 wall time 제한 내에서 실행한다.
    private func executePlannerWithTimeout(
        implementation: @escaping @Sendable (ShadowPlannerInput) async -> ShadowPlannerResult,
        input: ShadowPlannerInput,
        wallTimeMs: Int
    ) async -> ShadowPlannerResult {
        let deadline = UInt64(wallTimeMs) * 1_000_000 // ns

        return await withTaskGroup(of: ShadowPlannerResult.self) { group in
            group.addTask {
                await implementation(input)
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: deadline)
                return .timeout
            }

            // 먼저 완료된 결과를 취한다
            if let first = await group.next() {
                group.cancelAll()
                return first
            }

            return .timeout
        }
    }

    // MARK: - Private: Storage

    private func appendTraceEnvelope(_ envelope: TraceEnvelope) {
        recentTraceEnvelopes.append(envelope)
        if recentTraceEnvelopes.count > Self.maxTraceEnvelopes {
            recentTraceEnvelopes.removeFirst(recentTraceEnvelopes.count - Self.maxTraceEnvelopes)
        }
    }

    private func appendDebugBundle(_ bundle: DebugBundle) {
        recentDebugBundles.append(bundle)
        if recentDebugBundles.count > Self.maxDebugBundles {
            recentDebugBundles.removeFirst(recentDebugBundles.count - Self.maxDebugBundles)
        }
    }

    // MARK: - Private: Sanitization

    /// 입력 요약을 sanitize한다 (PII 등 민감 정보 제거).
    private func sanitizeInput(_ input: String) -> String {
        let maxLength = 200
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength)) + "..."
        }
        return trimmed
    }
}
