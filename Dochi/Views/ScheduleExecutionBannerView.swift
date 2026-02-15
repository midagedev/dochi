import SwiftUI

// MARK: - ScheduleExecutionBannerView

struct ScheduleExecutionBannerView: View {
    let execution: ScheduleExecutionRecord
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(iconColor)

            Text(bannerText)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            if execution.status == .failure {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .onTapGesture {
            if execution.status != .failure {
                onDismiss?()
            }
        }
    }

    private var iconName: String {
        switch execution.status {
        case .running: return "clock"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch execution.status {
        case .running: return .blue
        case .success: return .green
        case .failure: return .red
        }
    }

    private var bannerText: String {
        switch execution.status {
        case .running:
            return "자동화: \(execution.scheduleName) 실행 중..."
        case .success:
            return "자동화: \(execution.scheduleName) 완료"
        case .failure:
            let errorSuffix = execution.errorMessage.map { " — \($0)" } ?? ""
            return "자동화: \(execution.scheduleName) 실패\(errorSuffix)"
        }
    }

    private var backgroundColor: Color {
        switch execution.status {
        case .running: return Color.blue.opacity(0.1)
        case .success: return Color.green.opacity(0.1)
        case .failure: return Color.red.opacity(0.1)
        }
    }
}
