import SwiftUI

// MARK: - Delegation Monitor View

/// Sheet view showing active and recent delegations with chain visualization.
struct DelegationMonitorView: View {
    let delegationManager: DelegationManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("위임 모니터", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Chain visualization
            if let chain = delegationManager.currentChain, chain.tasks.count >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("위임 체인")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    DelegationChainProgressView(chain: chain)
                        .padding(.horizontal)
                }

                Divider()
                    .padding(.top, 4)
            }

            // Content
            if delegationManager.activeDelegations.isEmpty && delegationManager.recentDelegations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Active delegations
                        if !delegationManager.activeDelegations.isEmpty {
                            sectionHeader("진행 중", count: delegationManager.activeDelegations.count, color: .purple)

                            ForEach(delegationManager.activeDelegations) { task in
                                DelegationExecutionCardView(delegation: task)
                            }
                        }

                        // Recent delegations
                        if !delegationManager.recentDelegations.isEmpty {
                            sectionHeader("최근 완료", count: delegationManager.recentDelegations.count, color: .secondary)

                            ForEach(delegationManager.recentDelegations) { task in
                                DelegationExecutionCardView(delegation: task)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("진행 중인 위임이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("에이전트 간 작업 위임 시 여기에 상태가 표시됩니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}
