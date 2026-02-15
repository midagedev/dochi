import SwiftUI

/// K-2: 프로액티브 제안 토스트 — 좌측 하단에 6초 auto fade
struct SuggestionToastView: View {
    let event: SuggestionToastEvent
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            toastContent
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 20)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isVisible = true
                    }
                    // Auto-dismiss after 6 seconds
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(6))
                        dismiss()
                    }
                }
        }
    }

    private var toastContent: some View {
        Button {
            onTap()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("도치의 제안")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(event.suggestion.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                // Type badge
                HStack(spacing: 3) {
                    Image(systemName: event.suggestion.type.icon)
                        .font(.system(size: 8))
                    Text(event.suggestion.type.displayName)
                        .font(.system(size: 9, weight: .medium))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.15))
                .foregroundStyle(badgeColor)
                .clipShape(Capsule())

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .frame(maxWidth: 340)
        }
        .buttonStyle(.plain)
    }

    private var badgeColor: Color {
        switch event.suggestion.type.badgeColor {
        case "blue": return .blue
        case "purple": return .purple
        case "teal": return .teal
        case "orange": return .orange
        case "green": return .green
        case "red": return .red
        default: return .gray
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            isVisible = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            dismissed = true
            onDismiss()
        }
    }
}

/// 토스트 컨테이너 — 좌측 하단에 스택
struct SuggestionToastContainerView: View {
    let events: [SuggestionToastEvent]
    let onTap: () -> Void
    let onDismiss: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            ForEach(events) { event in
                SuggestionToastView(
                    event: event,
                    onTap: onTap,
                    onDismiss: { onDismiss(event.id) }
                )
            }
        }
        .padding(.leading, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(!events.isEmpty)
    }
}
