import SwiftUI

// MARK: - Delegation Chain Progress View

/// Visualization of a delegation chain: A ----> B ----> C
/// Shows connected nodes with status-colored indicators.
struct DelegationChainProgressView: View {
    let chain: DelegationChain

    var body: some View {
        if chain.tasks.count < 2 {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(chain.involvedAgents.enumerated()), id: \.offset) { index, agent in
                        // Node
                        chainNode(agent: agent, status: statusForAgent(agent))

                        // Connector line (not after last)
                        if index < chain.involvedAgents.count - 1 {
                            connectorLine(status: connectorStatusBetween(index: index))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Node

    private func chainNode(agent: String, status: DelegationStatus) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(colorForStatus(status))
                .frame(width: 12, height: 12)
                .overlay {
                    if status == .running {
                        Circle()
                            .stroke(colorForStatus(status).opacity(0.5), lineWidth: 2)
                            .frame(width: 18, height: 18)
                    }
                }

            Text(agent)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 40)
    }

    // MARK: - Connector

    private func connectorLine(status: DelegationStatus) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(colorForStatus(status).opacity(0.5))
                .frame(width: 24, height: 2)
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(colorForStatus(status).opacity(0.5))
        }
        .padding(.bottom, 14) // Align with circle center
    }

    // MARK: - Status Helpers

    private func statusForAgent(_ agent: String) -> DelegationStatus {
        // Find the task where this agent is the target
        if let task = chain.tasks.last(where: { $0.targetAgentName == agent }) {
            return task.status
        }
        // If this is the first origin agent
        if let firstTask = chain.tasks.first, firstTask.originAgentName == agent {
            return .completed // Origin has already delegated
        }
        return .pending
    }

    private func connectorStatusBetween(index: Int) -> DelegationStatus {
        let agents = chain.involvedAgents
        guard index < agents.count - 1 else { return .pending }
        let fromAgent = agents[index]
        let toAgent = agents[index + 1]

        // Find the delegation task from -> to
        if let task = chain.tasks.first(where: {
            $0.originAgentName == fromAgent && $0.targetAgentName == toAgent
        }) {
            return task.status
        }
        return .pending
    }

    private func colorForStatus(_ status: DelegationStatus) -> Color {
        switch status {
        case .pending: .gray
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }
}
