import SwiftUI
import AppKit

/// LLM 기반 부정 피드백 패턴 분석 시트 (I-4)
struct FeedbackAnalysisSheetView: View {
    var feedbackStore: FeedbackStoreProtocol
    var viewModel: DochiViewModel?

    @State private var analysisResult: String = ""
    @State private var isAnalyzing = false
    @State private var showCopied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("피드백 패턴 분석")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Content
            if isAnalyzing {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("부정 피드백 패턴을 분석하고 있습니다...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if analysisResult.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("AI가 부정 피드백 패턴을 분석하고\n시스템 프롬프트 개선 방안을 제안합니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("분석 시작") {
                        runAnalysis()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(analysisResult)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(analysisResult, forType: .string)
                        withAnimation {
                            showCopied = true
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation {
                                showCopied = false
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            Text(showCopied ? "복사됨" : "복사")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button("다시 분석") {
                        analysisResult = ""
                        runAnalysis()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 440)
    }

    // MARK: - Analysis

    private func runAnalysis() {
        let negativeFeedback = feedbackStore.recentNegative(limit: 20)
        guard !negativeFeedback.isEmpty else {
            analysisResult = "분석할 부정 피드백이 없습니다."
            return
        }

        isAnalyzing = true

        // Build summary of negative feedback for LLM
        let summary = buildFeedbackSummary(negativeFeedback)

        // Use a local analysis without LLM as fallback
        // (If viewModel is not available, do a simple local analysis)
        if viewModel == nil {
            analysisResult = buildLocalAnalysis(negativeFeedback)
            isAnalyzing = false
            return
        }

        Task {
            do {
                let prompt = """
                다음은 AI 어시스턴트의 응답에 대한 사용자 부정 피드백 요약입니다.
                패턴을 분석하고, 시스템 프롬프트 개선 방안을 구체적으로 제안해주세요.

                형식:
                ## 주요 패턴
                - (패턴 1)
                - (패턴 2)

                ## 개선 제안
                1. (제안 1)
                2. (제안 2)

                ## 추가 시스템 프롬프트 문구 제안
                ```
                (추가할 프롬프트 텍스트)
                ```

                ---
                피드백 데이터:
                \(summary)
                """

                let messages = [Message(role: .user, content: prompt)]
                let model = viewModel?.settings.llmModel ?? "gpt-4o-mini"
                let provider = viewModel?.settings.currentProvider ?? .openai
                let apiKey = viewModel?.keychainService.load(account: provider.keychainAccount) ?? ""

                guard !apiKey.isEmpty else {
                    analysisResult = buildLocalAnalysis(negativeFeedback)
                    isAnalyzing = false
                    return
                }

                let llmService = LLMService()
                let response = try await llmService.send(
                    messages: messages,
                    systemPrompt: "당신은 AI 어시스턴트 품질 분석가입니다. 한국어로 답변하세요.",
                    model: model,
                    provider: provider,
                    apiKey: apiKey,
                    tools: nil,
                    onPartial: { _ in }
                )

                switch response {
                case .text(let text):
                    analysisResult = text
                default:
                    analysisResult = buildLocalAnalysis(negativeFeedback)
                }
            } catch {
                Log.app.error("Feedback analysis failed: \(error.localizedDescription)")
                analysisResult = buildLocalAnalysis(negativeFeedback)
            }

            isAnalyzing = false
        }
    }

    private func buildFeedbackSummary(_ entries: [FeedbackEntry]) -> String {
        let categories = feedbackStore.categoryDistribution()
        let models = feedbackStore.modelBreakdown()

        var lines: [String] = []
        lines.append("총 부정 피드백: \(entries.count)건")
        lines.append("")

        if !categories.isEmpty {
            lines.append("카테고리 분포:")
            for cat in categories {
                lines.append("  - \(cat.category.displayName): \(cat.count)건")
            }
            lines.append("")
        }

        if !models.isEmpty {
            lines.append("모델별 만족도:")
            for model in models {
                lines.append("  - \(model.model): \(String(format: "%.0f%%", model.satisfactionRate * 100)) (\(model.totalCount)건)")
            }
            lines.append("")
        }

        lines.append("최근 피드백 코멘트:")
        for entry in entries.prefix(10) {
            let cat = entry.category?.displayName ?? "미지정"
            let comment = entry.comment ?? "(코멘트 없음)"
            lines.append("  [\(cat)] \(comment) — \(entry.model)")
        }

        return lines.joined(separator: "\n")
    }

    private func buildLocalAnalysis(_ entries: [FeedbackEntry]) -> String {
        let categories = feedbackStore.categoryDistribution()
        let models = feedbackStore.modelBreakdown()

        var lines: [String] = []
        lines.append("## 피드백 패턴 요약")
        lines.append("")
        lines.append("총 부정 피드백: \(entries.count)건")
        lines.append("")

        if let topCategory = categories.first {
            lines.append("## 주요 패턴")
            lines.append("- 가장 많은 불만: **\(topCategory.category.displayName)** (\(topCategory.count)건)")
            for cat in categories.dropFirst().prefix(2) {
                lines.append("- \(cat.category.displayName): \(cat.count)건")
            }
            lines.append("")
        }

        let warningModels = models.filter { $0.isWarning }
        if !warningModels.isEmpty {
            lines.append("## 주의 모델")
            for model in warningModels {
                lines.append("- **\(model.model)**: 만족도 \(String(format: "%.0f%%", model.satisfactionRate * 100))")
            }
            lines.append("")
        }

        lines.append("## 개선 제안")
        if categories.contains(where: { $0.category == .tooLong }) {
            lines.append("- 응답 길이를 줄이도록 시스템 프롬프트에 간결한 답변 지시 추가")
        }
        if categories.contains(where: { $0.category == .tooShort }) {
            lines.append("- 충분한 설명을 포함하도록 시스템 프롬프트에 상세 답변 지시 추가")
        }
        if categories.contains(where: { $0.category == .missedContext }) {
            lines.append("- 대화 맥락 참조를 강화하도록 시스템 프롬프트 수정")
        }
        if categories.contains(where: { $0.category == .wrongTone }) {
            lines.append("- 어조/말투 가이드라인을 시스템 프롬프트에 명시")
        }
        if categories.contains(where: { $0.category == .inaccurate }) {
            lines.append("- 불확실한 정보는 명시하고 출처를 밝히도록 지시 추가")
        }
        if lines.last == "## 개선 제안" {
            lines.append("- 부정 피드백 카테고리를 지정하면 더 구체적인 제안을 볼 수 있습니다")
        }

        lines.append("")
        lines.append("*LLM API 키가 설정되면 더 상세한 AI 기반 분석을 사용할 수 있습니다.*")

        return lines.joined(separator: "\n")
    }
}
