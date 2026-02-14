import SwiftUI

/// 설정 > 에이전트 탭 — AgentCardGridView 래퍼
struct AgentSettingsView: View {
    let contextService: ContextServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    var viewModel: DochiViewModel?
    var onAgentDeleted: (() -> Void)?

    var body: some View {
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

// MARK: - String Identifiable (for sheet binding)

extension String: @retroactive Identifiable {
    public var id: String { self }
}
