import SwiftUI

// MARK: - Delegation Execution Card

/// Inline card in conversation showing delegation status.
struct DelegationExecutionCardView: View {
    let delegation: DelegationTask
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                headerContent
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundForStatus)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColorForStatus, lineWidth: 0.5)
        )
        .onAppear {
            isExpanded = delegation.status == .failed
        }
    }

    // MARK: - Header

    private var headerContent: some View {
        HStack(spacing: 6) {
            statusIcon
                .frame(width: 16, height: 16)

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(delegation.targetAgentName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(delegation.task)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Elapsed or duration
            if delegation.status == .running {
                elapsedTimeView
            } else if let duration = delegation.durationSeconds {
                Text(String(format: "%.1f\u{CD08}", duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .contentShape(Rectangle())
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch delegation.status {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Elapsed Time

    private var elapsedTimeView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let started = delegation.startedAt {
                let elapsed = Date().timeIntervalSince(started)
                Text(String(format: "%.0f\u{CD08}", elapsed))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.vertical, 2)

            // Origin agent
            HStack(spacing: 4) {
                Text("\u{BC1C}\u{C2E0}")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(delegation.originAgentName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                Text("\u{C218}\u{C2E0}")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(delegation.targetAgentName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Task
            VStack(alignment: .leading, spacing: 2) {
                Text("\u{C791}\u{C5C5}")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(delegation.task)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            // Context
            if let context = delegation.context, !context.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\u{CEE8}\u{D14D}\u{C2A4}\u{D2B8}")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(context)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }

            // Result
            if let result = delegation.result {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\u{ACB0}\u{ACFC}")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(result)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(5)
                }
            }

            // Error
            if let error = delegation.errorMessage {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\u{C624}\u{B958}")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.8))
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }

            // Chain depth
            if delegation.chainDepth > 0 {
                HStack(spacing: 4) {
                    Text("\u{CCB4}\u{C778} \u{AE4A}\u{C774}")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(delegation.chainDepth)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Colors

    private var backgroundForStatus: Color {
        switch delegation.status {
        case .pending: Color.gray.opacity(0.06)
        case .running: Color.purple.opacity(0.06)
        case .completed: Color.green.opacity(0.06)
        case .failed: Color.red.opacity(0.06)
        case .cancelled: Color.orange.opacity(0.06)
        }
    }

    private var borderColorForStatus: Color {
        switch delegation.status {
        case .pending: Color.gray.opacity(0.15)
        case .running: Color.purple.opacity(0.2)
        case .completed: Color.green.opacity(0.15)
        case .failed: Color.red.opacity(0.2)
        case .cancelled: Color.orange.opacity(0.15)
        }
    }
}
