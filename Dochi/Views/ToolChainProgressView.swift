import SwiftUI

/// Displays a chain progress indicator when tool loop count >= 2.
/// Shows step indicators (check/spinner/empty/X) with connecting lines.
struct ToolChainProgressView: View {
    let executions: [ToolExecution]

    /// Total elapsed seconds from first start to last completion (or now).
    private var totalElapsed: TimeInterval {
        guard let first = executions.first else { return 0 }
        let end = executions.last?.completedAt ?? Date()
        return end.timeIntervalSince(first.startedAt)
    }

    private var completedCount: Int {
        executions.filter { $0.status == .success }.count
    }

    private var totalCount: Int {
        executions.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Step indicators with connecting lines
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(executions.enumerated()), id: \.element.id) { index, execution in
                        if index > 0 {
                            // Connecting line
                            connectingLine(before: execution)
                        }
                        stepIndicator(execution: execution, index: index)
                    }
                }
                .padding(.horizontal, 4)
            }

            // Summary text
            HStack(spacing: 4) {
                Text("전체 소요: \(String(format: "%.1f초", totalElapsed))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text("\u{00B7}")
                    .foregroundStyle(.quaternary)

                Text("\(completedCount)/\(totalCount)단계 완료")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Step Indicator

    private func stepIndicator(execution: ToolExecution, index: Int) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(fillColorForStatus(execution.status))
                    .frame(width: 22, height: 22)

                statusSymbol(execution.status)
            }

            Text(execution.displayName)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
    }

    @ViewBuilder
    private func statusSymbol(_ status: ToolExecutionStatus) -> some View {
        switch status {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        case .error:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func fillColorForStatus(_ status: ToolExecutionStatus) -> Color {
        switch status {
        case .running: .blue
        case .success: .green
        case .error: .red
        }
    }

    // MARK: - Connecting Line

    private func connectingLine(before execution: ToolExecution) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(lineColorForStatus(execution.status))
                .frame(width: 20, height: 2)
            Spacer()
                .frame(height: 14) // Align with step name text
        }
    }

    private func lineColorForStatus(_ status: ToolExecutionStatus) -> Color {
        switch status {
        case .running: .blue.opacity(0.3)
        case .success: .green.opacity(0.5)
        case .error: .red.opacity(0.5)
        }
    }
}
