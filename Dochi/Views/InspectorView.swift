import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @State private var tab: Tab = .context

    enum Tab: String, CaseIterable { case context = "Context", tools = "Tools", sources = "Sources", vars = "Vars" }

    var body: some View {
        VStack(spacing: 0) {
            // Tabs
            HStack(spacing: AppSpacing.s) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        Text(t.rawValue)
                            .compact(AppFont.caption)
                            .padding(.horizontal, AppSpacing.s)
                            .padding(.vertical, AppSpacing.xs)
                            .background(tab == t ? AppColor.surface : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.background)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    switch tab {
                    case .context: ContextPanel(viewModel: viewModel)
                    case .tools: ToolsPanel(viewModel: viewModel)
                    case .sources: SourcesPanel()
                    case .vars: VarsPanel(viewModel: viewModel)
                    }
                }
                .padding(AppSpacing.s)
            }
        }
    }
}

private struct ContextPanel: View {
    let viewModel: DochiViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader("시스템 프롬프트")
            Text(viewModel.settings.buildInstructions())
                .compact(AppFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(10)

            SectionHeader("대화 메타")
            HStack {
                Text("메시지 수").compact(AppFont.caption)
                Spacer()
                Text("\(viewModel.messages.count)").compact(AppFont.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct ToolsPanel: View {
    let viewModel: DochiViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader("도구 상태")
            if let name = viewModel.currentToolExecution {
                HStack(spacing: AppSpacing.s) {
                    Image(systemName: "hammer")
                        .foregroundStyle(.cyan)
                    Text("\(name) 실행 중...")
                        .compact(AppFont.caption)
                }
            } else {
                Text("최근 실행 중인 도구 없음")
                    .compact(AppFont.caption)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.mcpService.availableTools.isEmpty {
                SectionHeader("사용 가능한 도구")
                ForEach(viewModel.mcpService.availableTools) { tool in
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(.cyan)
                        Text(tool.name).compact(AppFont.caption)
                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
    }
}

private struct SourcesPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader("출처")
            Text("연결된 출처 없음")
                .compact(AppFont.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VarsPanel: View {
    let viewModel: DochiViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader("런타임 변수")
            Group {
                KVRow(k: "모델", v: "\(viewModel.settings.llmProvider.displayName) / \(viewModel.settings.llmModel)")
                KVRow(k: "상태", v: "\(String(describing: viewModel.state))")
                KVRow(k: "연결", v: viewModel.isConnected ? "연결됨" : "연결 안 됨")
            }
        }
    }
}

private struct KVRow: View {
    let k: String
    let v: String
    var body: some View {
        HStack {
            Text(k).compact(AppFont.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).compact(AppFont.caption)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

