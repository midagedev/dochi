import SwiftUI

/// 설정 > 에이전트 탭 — AgentCardGridView 래퍼
struct AgentSettingsView: View {
    let contextService: ContextServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    var viewModel: DochiViewModel?
    var onAgentDeleted: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("에이전트 관리")
                    .font(.headline)
                SettingsHelpButton(
                    title: "에이전트",
                    content: "에이전트는 특정 목적에 맞게 설정된 AI 비서입니다. 각 에이전트는 고유한 페르소나, 모델, 도구 권한을 가집니다. 템플릿으로 빠르게 만들거나, 기존 에이전트를 복제/편집할 수 있습니다."
                )
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)

            AgentCardGridView(
                contextService: contextService,
                settings: settings,
                sessionContext: sessionContext,
                viewModel: viewModel,
                onAgentDeleted: onAgentDeleted
            )
            .padding()
        }
    }
}

// MARK: - String Identifiable (for sheet binding)

extension String: @retroactive Identifiable {
    public var id: String { self }
}
