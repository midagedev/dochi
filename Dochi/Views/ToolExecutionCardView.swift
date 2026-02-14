import SwiftUI

// MARK: - Live Tool Execution Card

/// Collapsible card showing a live tool execution's status, name, input summary, and duration.
struct ToolExecutionCardView: View {
    let execution: ToolExecution
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
            // Auto-expand errors, auto-collapse success
            isExpanded = execution.status == .error
        }
        .onChange(of: execution.status) { _, newStatus in
            withAnimation(.easeInOut(duration: 0.2)) {
                if newStatus == .error {
                    isExpanded = true
                } else if newStatus == .success {
                    isExpanded = false
                }
            }
        }
    }

    // MARK: - Header

    private var headerContent: some View {
        HStack(spacing: 6) {
            statusIcon
                .frame(width: 16, height: 16)

            Text(execution.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Category badge (only for sensitive/restricted)
            if execution.category != .safe {
                categoryBadge
            }

            if !execution.inputSummary.isEmpty {
                Text(execution.inputSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Duration
            if let duration = execution.durationSeconds {
                Text(String(format: "%.1f초", duration))
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
        switch execution.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Category Badge

    private var categoryBadge: some View {
        Text(execution.category.rawValue)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(categoryBadgeColor.opacity(0.15))
            .foregroundStyle(categoryBadgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var categoryBadgeColor: Color {
        switch execution.category {
        case .safe: .green
        case .sensitive: .orange
        case .restricted: .red
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.vertical, 2)

            // Input parameters
            if !execution.inputSummary.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("입력")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(execution.inputSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Result summary
            if let result = execution.resultSummary {
                VStack(alignment: .leading, spacing: 2) {
                    Text(execution.status == .error ? "오류" : "결과")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(execution.status == .error ? .red : .secondary)
                    Text(result)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(execution.status == .error ? .red.opacity(0.8) : .secondary)
                        .textSelection(.enabled)
                        .lineLimit(5)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Colors

    private var backgroundForStatus: Color {
        switch execution.status {
        case .running: Color.blue.opacity(0.06)
        case .success: Color.green.opacity(0.06)
        case .error: Color.red.opacity(0.06)
        }
    }

    private var borderColorForStatus: Color {
        switch execution.status {
        case .running: Color.blue.opacity(0.2)
        case .success: Color.green.opacity(0.15)
        case .error: Color.red.opacity(0.2)
        }
    }
}

// MARK: - Archived Tool Execution Record Card

/// Card for displaying archived ToolExecutionRecord from past messages.
struct ToolExecutionRecordCardView: View {
    let record: ToolExecutionRecord
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                headerContent
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(record.isError ? Color.red.opacity(0.06) : Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(record.isError ? Color.red.opacity(0.15) : Color.green.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var headerContent: some View {
        HStack(spacing: 6) {
            Image(systemName: record.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(record.isError ? .red : .green)

            Text(record.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !record.inputSummary.isEmpty {
                Text(record.inputSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if let duration = record.durationSeconds {
                Text(String(format: "%.1f초", duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .contentShape(Rectangle())
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.vertical, 2)

            if !record.inputSummary.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("입력")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(record.inputSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let result = record.resultSummary {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.isError ? "오류" : "결과")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(record.isError ? .red : .secondary)
                    Text(result)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(record.isError ? .red.opacity(0.8) : .secondary)
                        .textSelection(.enabled)
                        .lineLimit(5)
                }
            }
        }
        .padding(.top, 2)
    }
}
