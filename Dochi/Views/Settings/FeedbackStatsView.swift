import SwiftUI

/// 피드백 통계 뷰 — Settings > AI > 피드백 통계 (I-4)
struct FeedbackStatsView: View {
    var feedbackStore: FeedbackStoreProtocol
    var settings: AppSettings
    var viewModel: DochiViewModel?

    @State private var showAnalysisSheet = false

    private var totalCount: Int { feedbackStore.entries.count }
    private var positiveCount: Int { feedbackStore.entries.filter { $0.rating == .positive }.count }
    private var negativeCount: Int { feedbackStore.entries.filter { $0.rating == .negative }.count }
    private var overallSatisfaction: Double { feedbackStore.satisfactionRate(model: nil, agent: nil) }

    var body: some View {
        Form {
            // MARK: - Settings

            Section {
                Toggle("피드백 버튼 활성화", isOn: Binding(
                    get: { settings.feedbackEnabled },
                    set: { settings.feedbackEnabled = $0 }
                ))

                if settings.feedbackEnabled {
                    Toggle("호버 시 표시", isOn: Binding(
                        get: { settings.feedbackShowOnHover },
                        set: { settings.feedbackShowOnHover = $0 }
                    ))

                    Text("어시스턴트 메시지에 마우스를 올리면 피드백 버튼이 표시됩니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SettingsSectionHeader(
                    title: "피드백 설정",
                    helpContent: "응답 메시지에 좋아요/싫어요 피드백 버튼을 표시합니다. 수집된 피드백으로 응답 품질을 분석할 수 있습니다."
                )
            }

            // MARK: - Summary Cards

            Section {
                if totalCount == 0 {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("아직 피드백이 없습니다")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("대화 메시지에서 좋아요/싫어요로 피드백을 남겨보세요")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    HStack(spacing: 16) {
                        summaryCard(
                            title: "전체",
                            value: "\(totalCount)",
                            icon: "chart.bar.fill",
                            color: .blue
                        )
                        summaryCard(
                            title: "만족도",
                            value: String(format: "%.0f%%", overallSatisfaction * 100),
                            icon: "face.smiling",
                            color: overallSatisfaction >= 0.6 ? .green : .orange
                        )
                        summaryCard(
                            title: "부정",
                            value: "\(negativeCount)",
                            icon: "hand.thumbsdown.fill",
                            color: negativeCount > 0 ? .red : .secondary
                        )
                    }
                }
            } header: {
                Text("요약")
            }

            if totalCount > 0 {
                // MARK: - Model Breakdown

                Section {
                    let models = feedbackStore.modelBreakdown()
                    if models.isEmpty {
                        Text("데이터 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(models) { model in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(model.model)
                                            .font(.system(size: 12))
                                            .lineLimit(1)

                                        if model.isWarning {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.orange)
                                                .help("만족도 60% 미만")
                                        }
                                    }

                                    Text("\(model.provider) · \(model.totalCount)건")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                satisfactionBar(rate: model.satisfactionRate, width: 80)

                                Text(String(format: "%.0f%%", model.satisfactionRate * 100))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(model.isWarning ? .orange : .secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("모델별 만족도")
                }

                // MARK: - Agent Breakdown

                Section {
                    let agents = feedbackStore.agentBreakdown()
                    if agents.isEmpty {
                        Text("데이터 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(agents) { agent in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.agentName)
                                        .font(.system(size: 12))
                                    Text("\(agent.totalCount)건")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                satisfactionBar(rate: agent.satisfactionRate, width: 80)

                                Text(String(format: "%.0f%%", agent.satisfactionRate * 100))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("에이전트별 만족도")
                }

                // MARK: - Category Distribution

                Section {
                    let categories = feedbackStore.categoryDistribution()
                    if categories.isEmpty {
                        Text("부정 피드백에 카테고리가 지정된 항목이 없습니다")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        let maxCount = categories.map(\.count).max() ?? 1
                        ForEach(categories) { item in
                            HStack(spacing: 8) {
                                Text(item.category.displayName)
                                    .font(.system(size: 12))
                                    .frame(width: 120, alignment: .leading)

                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.red.opacity(0.6))
                                        .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(maxCount))
                                }
                                .frame(height: 14)

                                Text("\(item.count)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("부정 피드백 카테고리")
                }

                // MARK: - Recent Negative

                Section {
                    let recent = feedbackStore.recentNegative(limit: 10)
                    if recent.isEmpty {
                        Text("부정 피드백이 없습니다")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recent) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    if let category = entry.category {
                                        Text(category.displayName)
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.1))
                                            .clipShape(Capsule())
                                    }

                                    Text(entry.model)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)

                                    Spacer()

                                    Text(entry.timestamp, style: .relative)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }

                                if let comment = entry.comment, !comment.isEmpty {
                                    Text(comment)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("최근 부정 피드백")
                }

                // MARK: - Analysis Button

                Section {
                    Button {
                        showAnalysisSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("시스템 프롬프트 개선 제안")
                        }
                    }
                    .disabled(negativeCount < 3)

                    if negativeCount < 3 {
                        Text("분석을 위해 최소 3개의 부정 피드백이 필요합니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showAnalysisSheet) {
            FeedbackAnalysisSheetView(
                feedbackStore: feedbackStore,
                viewModel: viewModel
            )
        }
    }

    // MARK: - Summary Card

    @ViewBuilder
    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Satisfaction Bar

    @ViewBuilder
    private func satisfactionBar(rate: Double, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: width, height: 8)

            RoundedRectangle(cornerRadius: 3)
                .fill(rate >= 0.6 ? Color.green : Color.orange)
                .frame(width: width * CGFloat(rate), height: 8)
        }
    }
}
