import SwiftUI

/// K-2: 제안 기록 시트
struct SuggestionHistoryView: View {
    let history: [ProactiveSuggestion]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("제안 기록")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Today summary
            let todayAccepted = history.filter { suggestion in
                Calendar.current.isDateInToday(suggestion.timestamp) && suggestion.status == .accepted
            }.count
            let todayTotal = history.filter { suggestion in
                Calendar.current.isDateInToday(suggestion.timestamp)
            }.count

            HStack {
                Text("오늘 \(todayTotal)건 제안 (\(todayAccepted)건 수락)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // History list
            if history.isEmpty {
                Spacer()
                Text("아직 제안 기록이 없습니다.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(history.prefix(20)) { suggestion in
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.type.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Text(suggestion.timestamp, style: .relative)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        statusBadge(for: suggestion.status)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 400, height: 480)
    }

    @ViewBuilder
    private func statusBadge(for status: SuggestionStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .shown: return ("표시됨", .blue)
            case .accepted: return ("수락", .green)
            case .deferred: return ("나중에", .orange)
            case .dismissed: return ("비활성화", .red)
            }
        }()

        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
