import SwiftUI

/// K-2: 프로액티브 제안 버블 — 대화 영역 하단에 표시
/// 노란 좌측 border 3pt, .ultraThinMaterial 배경
/// lightbulb.fill 아이콘 + "도치의 제안" 라벨
/// 유형 배지 칩 (SuggestionType별 색상/아이콘)
/// [수락]: suggestedPrompt를 대화에 전송
/// [나중에]: 숨기고 history에 .deferred로 저장
/// [이런 제안 그만]: 확인 팝오버 후 해당 유형 설정 false
struct SuggestionBubbleView: View {
    let suggestion: ProactiveSuggestion
    let onAccept: () -> Void
    let onDefer: () -> Void
    let onDismissType: () -> Void

    @State private var showDismissConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // 노란 좌측 border 3pt
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                // Header: lightbulb + label + type badge
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.yellow)

                    Text("도치의 제안")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Type badge chip
                    typeBadge
                }

                // Title
                Text(suggestion.title)
                    .font(.system(size: 13, weight: .semibold))

                // Body text
                Text(suggestion.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                // Action buttons
                HStack(spacing: 8) {
                    Button {
                        onAccept()
                    } label: {
                        Label("수락", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("나중에") {
                        onDefer()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button("이런 제안 그만") {
                        showDismissConfirmation = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .popover(isPresented: $showDismissConfirmation) {
                        dismissConfirmationPopover
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    // MARK: - Type Badge

    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: suggestion.type.icon)
                .font(.system(size: 9))
            Text(suggestion.type.displayName)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeBackgroundColor.opacity(0.15))
        .foregroundStyle(badgeBackgroundColor)
        .clipShape(Capsule())
    }

    private var badgeBackgroundColor: Color {
        switch suggestion.type.badgeColor {
        case "blue": return .blue
        case "purple": return .purple
        case "teal": return .teal
        case "orange": return .orange
        case "green": return .green
        case "red": return .red
        default: return .gray
        }
    }

    // MARK: - Dismiss Confirmation Popover

    private var dismissConfirmationPopover: some View {
        VStack(spacing: 12) {
            Text("\"\(suggestion.type.displayName)\" 유형의 제안을\n더 이상 받지 않을까요?")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("취소") {
                    showDismissConfirmation = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("끄기") {
                    showDismissConfirmation = false
                    onDismissType()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}
