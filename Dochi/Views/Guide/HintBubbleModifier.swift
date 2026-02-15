import SwiftUI
import os

// MARK: - HintManager

/// 인앱 힌트 표시 상태를 관리하는 싱글턴.
/// UserDefaults 기반으로 각 힌트의 표시 여부와 전역 비활성화 상태를 추적한다.
@MainActor
@Observable
final class HintManager {
    static let shared = HintManager()

    /// 현재 표시 중인 힌트 ID (동시 최대 1개)
    var activeHintId: String?

    private init() {}

    // MARK: - 개별 힌트

    /// 특정 힌트가 이미 표시되었는지 확인
    func hasSeenHint(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: "hint_seen_\(id)")
    }

    /// 특정 힌트를 표시 완료로 기록
    func markHintSeen(_ id: String) {
        UserDefaults.standard.set(true, forKey: "hint_seen_\(id)")
        if activeHintId == id {
            activeHintId = nil
        }
        Log.app.info("Hint marked seen: \(id)")
    }

    /// 힌트를 표시할 수 있는지 확인 (미표시 + 전역 활성 + 다른 힌트 미표시)
    func canShowHint(_ id: String) -> Bool {
        !isGloballyDisabled && !hasSeenHint(id) && (activeHintId == nil || activeHintId == id)
    }

    /// 힌트를 활성 상태로 설정
    func activateHint(_ id: String) {
        guard canShowHint(id) else { return }
        activeHintId = id
    }

    /// 활성 힌트 해제 (닫기)
    func dismissHint(_ id: String) {
        markHintSeen(id)
    }

    // MARK: - 전역 비활성화

    /// 모든 힌트가 전역적으로 비활성화되었는지
    var isGloballyDisabled: Bool {
        UserDefaults.standard.bool(forKey: "hintsGloballyDisabled")
    }

    /// 모든 힌트 전역 비활성화
    func disableAllHints() {
        UserDefaults.standard.set(true, forKey: "hintsGloballyDisabled")
        activeHintId = nil
        Log.app.info("All hints globally disabled")
    }

    // MARK: - 리셋

    /// 모든 hint_seen_ 키 삭제 + 전역 비활성화 해제
    func resetAllHints() {
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("hint_seen_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set(false, forKey: "hintsGloballyDisabled")
        activeHintId = nil
        Log.app.info("All hints reset")
    }
}

// MARK: - HintBubbleModifier

/// 말풍선 형태의 일회성 힌트를 표시하는 ViewModifier.
/// 대상 뷰 진입 후 1.5초 후 fadeIn으로 나타나며, "확인" 또는 "X"로 닫을 수 있다.
struct HintBubbleModifier: ViewModifier {
    let id: String
    let title: String
    let message: String
    let edge: Edge
    let condition: Bool

    @State private var isVisible = false
    @State private var appearTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: overlayAlignment) {
                if isVisible {
                    hintBubble
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(999)
                }
            }
            .onAppear {
                scheduleAppearance()
            }
            .onDisappear {
                appearTask?.cancel()
                appearTask = nil
            }
            .onChange(of: condition) { _, newValue in
                if newValue {
                    scheduleAppearance()
                } else {
                    withAnimation { isVisible = false }
                }
            }
    }

    private var overlayAlignment: Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    private func scheduleAppearance() {
        guard condition, HintManager.shared.canShowHint(id) else { return }
        appearTask?.cancel()
        appearTask = Task { @MainActor in
            if reduceMotion {
                HintManager.shared.activateHint(id)
                isVisible = true
            } else {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                guard HintManager.shared.canShowHint(id) else { return }
                HintManager.shared.activateHint(id)
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible = true
                }
            }
        }
    }

    @ViewBuilder
    private var hintBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 헤더: 아이콘 + 제목 + 닫기
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
            }

            // 설명
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 하단 버튼
            HStack {
                Spacer()

                Button("다시 보지 않기") {
                    HintManager.shared.disableAllHints()
                    withAnimation { isVisible = false }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)

                Button("확인") {
                    dismiss()
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityHint("확인 버튼으로 닫을 수 있습니다")
    }

    private func dismiss() {
        HintManager.shared.dismissHint(id)
        withAnimation(.easeIn(duration: 0.2)) {
            isVisible = false
        }
    }
}

// MARK: - View Extension

extension View {
    /// 일회성 힌트 버블을 표시하는 modifier.
    /// - Parameters:
    ///   - id: 힌트 고유 ID (UserDefaults 키에 사용)
    ///   - title: 힌트 제목
    ///   - message: 힌트 설명
    ///   - edge: 화살표 방향 (힌트 표시 위치)
    ///   - condition: 표시 조건 (true일 때만 표시 시도)
    func hintBubble(
        id: String,
        title: String,
        message: String,
        edge: Edge = .top,
        condition: Bool = true
    ) -> some View {
        modifier(HintBubbleModifier(
            id: id,
            title: title,
            message: message,
            edge: edge,
            condition: condition
        ))
    }
}
