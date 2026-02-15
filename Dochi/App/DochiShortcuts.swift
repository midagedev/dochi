import AppIntents

/// Dochi의 Shortcuts/Siri 등록을 위한 AppShortcutsProvider.
/// macOS Shortcuts 앱에 도치 액션을 자동 노출한다.
struct DochiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskDochiIntent(),
            phrases: [
                "\(.applicationName)에게 물어보기",
                "\(.applicationName)에게 질문하기",
                "\(.applicationName)에 물어봐"
            ],
            shortTitle: "도치에게 물어보기",
            systemImageName: "bubble.left.and.bubble.right"
        )

        AppShortcut(
            intent: AddMemoIntent(),
            phrases: [
                "\(.applicationName) 메모 추가",
                "\(.applicationName)에 메모하기",
                "\(.applicationName) 메모 저장"
            ],
            shortTitle: "메모 추가",
            systemImageName: "note.text"
        )

        AppShortcut(
            intent: CreateKanbanCardIntent(),
            phrases: [
                "\(.applicationName) 칸반 카드 생성",
                "\(.applicationName) 할 일 추가",
                "\(.applicationName) 카드 만들기"
            ],
            shortTitle: "칸반 카드 생성",
            systemImageName: "rectangle.3.group"
        )

        AppShortcut(
            intent: TodayBriefingIntent(),
            phrases: [
                "\(.applicationName) 오늘 브리핑",
                "\(.applicationName) 오늘 요약",
                "\(.applicationName) 브리핑 해줘"
            ],
            shortTitle: "오늘 브리핑",
            systemImageName: "sun.max"
        )
    }
}
