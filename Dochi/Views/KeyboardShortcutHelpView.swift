import SwiftUI

/// 키보드 단축키 도움말 시트 (⌘/)
struct KeyboardShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct ShortcutEntry: Identifiable {
        let id = UUID()
        let keys: String
        let description: String
    }

    private let sections: [(title: String, icon: String, entries: [ShortcutEntry])] = [
        (
            title: "대화",
            icon: "bubble.left.and.bubble.right",
            entries: [
                ShortcutEntry(keys: "⌘N", description: "새 대화"),
                ShortcutEntry(keys: "⌘1~9", description: "대화 목록에서 N번째 대화 선택"),
                ShortcutEntry(keys: "⌘E", description: "현재 대화 빠른 내보내기 (Markdown)"),
                ShortcutEntry(keys: "⌘⇧E", description: "내보내기 옵션 시트"),
                ShortcutEntry(keys: "⌘⇧L", description: "즐겨찾기 필터 토글"),
                ShortcutEntry(keys: "⌘⇧M", description: "일괄 선택 모드 토글"),
                ShortcutEntry(keys: "Esc", description: "요청 취소"),
                ShortcutEntry(keys: "Enter", description: "메시지 전송"),
                ShortcutEntry(keys: "⇧Enter", description: "줄바꿈"),
            ]
        ),
        (
            title: "탐색",
            icon: "arrow.triangle.branch",
            entries: [
                ShortcutEntry(keys: "⌘⇧A", description: "에이전트 전환"),
                ShortcutEntry(keys: "⌘⇧W", description: "워크스페이스 전환"),
                ShortcutEntry(keys: "⌘⇧U", description: "사용자 전환"),
                ShortcutEntry(keys: "⌘⇧K", description: "칸반/대화 전환"),
            ]
        ),
        (
            title: "패널",
            icon: "sidebar.squares.leading",
            entries: [
                ShortcutEntry(keys: "⌘I", description: "메모리 인스펙터 패널"),
                ShortcutEntry(keys: "⌘⌥I", description: "컨텍스트 인스펙터 (시트)"),
                ShortcutEntry(keys: "⌘⇧S", description: "시스템 상태"),
                ShortcutEntry(keys: "⌘⇧F", description: "기능 카탈로그"),
                ShortcutEntry(keys: "⌘,", description: "설정"),
            ]
        ),
        (
            title: "메뉴바",
            icon: "menubar.rectangle",
            entries: [
                ShortcutEntry(keys: "⌘⇧D", description: "메뉴바 퀵 액세스 토글 (글로벌)"),
            ]
        ),
        (
            title: "명령 팔레트",
            icon: "command",
            entries: [
                ShortcutEntry(keys: "⌘K", description: "커맨드 팔레트 열기"),
                ShortcutEntry(keys: "⌘/", description: "이 도움말 표시"),
            ]
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text("키보드 단축키")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("닫기 (Esc)")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // 섹션 목록
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            // 섹션 제목
                            HStack(spacing: 6) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(section.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            // 항목
                            ForEach(section.entries) { entry in
                                HStack {
                                    keycapView(entry.keys)
                                    Spacer()
                                    Text(entry.description)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .frame(width: 480, height: 520)
    }

    /// 키캡 스타일 단축키 표시
    @ViewBuilder
    private func keycapView(_ keys: String) -> some View {
        HStack(spacing: 3) {
            ForEach(splitKeys(keys), id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }
        }
        .frame(minWidth: 80, alignment: .leading)
    }

    /// 단축키 문자열을 개별 키캡으로 분리
    private func splitKeys(_ keys: String) -> [String] {
        // "⌘⇧K" -> ["⌘", "⇧", "K"] 같은 분리
        // "⌘1~9" -> ["⌘", "1~9"]
        // "Enter" -> ["Enter"]
        // "⇧Enter" -> ["⇧", "Enter"]
        // "Esc" -> ["Esc"]

        var result: [String] = []
        var current = ""
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]

        for char in keys {
            if modifiers.contains(char) {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                result.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}
