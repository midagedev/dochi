import SwiftUI

/// G-3: 동기화 이벤트 토스트 (MemoryToastView 패턴)
struct SyncToastView: View {
    let event: SyncToastEvent
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
                    // Auto-dismiss after 4 seconds
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(4))
                        dismiss()
                    }
                }
        }
    }

    private var toastContent: some View {
        HStack(spacing: 8) {
            // 방향 아이콘
            Image(systemName: event.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(event.isConflict ? .orange : (event.direction == .incoming ? .blue : .green))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayMessage)
                    .font(.system(size: 11, weight: .medium))

                if !event.entityTitle.isEmpty {
                    Text(event.entityTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

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
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .frame(maxWidth: 320)
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

/// 동기화 토스트 컨테이너 (여러 토스트를 우측 하단에 스택)
struct SyncToastContainerView: View {
    let events: [SyncToastEvent]
    let onDismiss: (UUID) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Spacer()
            ForEach(events) { event in
                SyncToastView(
                    event: event,
                    onDismiss: { onDismiss(event.id) }
                )
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 80) // Memory toast 위에 배치
        .frame(maxWidth: .infinity, alignment: .trailing)
        .allowsHitTesting(!events.isEmpty)
    }
}
