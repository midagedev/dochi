import Foundation

/// 기능 제안 카테고리별 예시 프롬프트
struct FeatureSuggestion: Identifiable, Sendable {
    let id = UUID()
    let icon: String
    let category: String
    let prompts: [String]
}

/// 슬래시 명령 정의
struct SlashCommand: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let description: String
    let example: String
    let toolGroup: String?
}

enum FeatureCatalog {

    // MARK: - 대화 시작 제안 (카테고리별)

    static let suggestions: [FeatureSuggestion] = [
        FeatureSuggestion(
            icon: "calendar",
            category: "일정",
            prompts: [
                "오늘 일정 알려줘",
                "내일 오후 3시에 회의 추가해줘",
                "이번 주 일정 정리해줘",
            ]
        ),
        FeatureSuggestion(
            icon: "checklist",
            category: "할 일",
            prompts: [
                "오늘 할 일 정리해줘",
                "장보기 목록 미리알림에 추가해줘",
                "30분 타이머 맞춰줘",
            ]
        ),
        FeatureSuggestion(
            icon: "rectangle.3.group",
            category: "칸반",
            prompts: [
                "새 프로젝트 보드 만들어줘",
                "칸반 보드 현황 보여줘",
                "진행 중인 작업 뭐 있어?",
            ]
        ),
        FeatureSuggestion(
            icon: "magnifyingglass",
            category: "검색",
            prompts: [
                "최근 AI 뉴스 찾아줘",
                "Swift 6 변경사항 검색해줘",
                "서울 맛집 추천해줘",
            ]
        ),
        FeatureSuggestion(
            icon: "doc.text",
            category: "파일",
            prompts: [
                "데스크탑 파일 목록 보여줘",
                "다운로드 폴더에서 PDF 찾아줘",
                "클립보드 내용 읽어줘",
            ]
        ),
        FeatureSuggestion(
            icon: "terminal",
            category: "개발",
            prompts: [
                "git 상태 확인해줘",
                "이 코드 리뷰해줘",
                "GitHub 이슈 목록 보여줘",
            ]
        ),
        FeatureSuggestion(
            icon: "music.note",
            category: "미디어",
            prompts: [
                "지금 재생 중인 곡 뭐야?",
                "이미지 하나 생성해줘",
                "스크린샷 찍어줘",
            ]
        ),
        FeatureSuggestion(
            icon: "brain",
            category: "기억",
            prompts: [
                "내가 좋아하는 음식 기억해줘",
                "지난번 얘기한 프로젝트 뭐였지?",
                "메모 저장해줘",
            ]
        ),
    ]

    private static func suggestion(for category: String) -> FeatureSuggestion {
        suggestions.first { $0.category == category }!
    }

    /// 시간대별 맞춤 제안 반환 (3개)
    static func contextualSuggestions(hour: Int? = nil) -> [FeatureSuggestion] {
        let h = hour ?? Calendar.current.component(.hour, from: Date())

        switch h {
        case 5..<9:
            return [suggestion(for: "일정"), suggestion(for: "할 일"), suggestion(for: "검색")]
        case 9..<12:
            return [suggestion(for: "일정"), suggestion(for: "칸반"), suggestion(for: "개발")]
        case 12..<14:
            return [suggestion(for: "검색"), suggestion(for: "미디어"), suggestion(for: "할 일")]
        case 14..<18:
            return [suggestion(for: "개발"), suggestion(for: "칸반"), suggestion(for: "파일")]
        case 18..<22:
            return [suggestion(for: "기억"), suggestion(for: "할 일"), suggestion(for: "미디어")]
        default:
            return [suggestion(for: "기억"), suggestion(for: "검색"), suggestion(for: "미디어")]
        }
    }

    // MARK: - 슬래시 명령

    static let slashCommands: [SlashCommand] = [
        SlashCommand(name: "/일정", description: "오늘 일정 확인", example: "오늘 일정 알려줘", toolGroup: "calendar"),
        SlashCommand(name: "/미리알림", description: "미리알림 목록 확인", example: "미리알림 목록 보여줘", toolGroup: "reminders"),
        SlashCommand(name: "/타이머", description: "타이머 설정", example: "10분 타이머 맞춰줘", toolGroup: "timer"),
        SlashCommand(name: "/알람", description: "알람 설정", example: "내일 아침 7시 알람", toolGroup: "alarm"),
        SlashCommand(name: "/칸반", description: "칸반 보드 관리", example: "칸반 보드 현황 보여줘", toolGroup: "kanban"),
        SlashCommand(name: "/검색", description: "웹 검색", example: "최신 뉴스 검색해줘", toolGroup: "search"),
        SlashCommand(name: "/파일", description: "파일 관리", example: "데스크탑 파일 목록", toolGroup: "file"),
        SlashCommand(name: "/스크린샷", description: "화면 캡처", example: "스크린샷 찍어줘", toolGroup: "screenshot"),
        SlashCommand(name: "/클립보드", description: "클립보드 읽기/쓰기", example: "클립보드 내용 읽어줘", toolGroup: "clipboard"),
        SlashCommand(name: "/계산", description: "수식 계산", example: "123 * 456 계산해줘", toolGroup: "calculator"),
        SlashCommand(name: "/날짜", description: "현재 날짜/시간", example: "지금 몇 시야?", toolGroup: "datetime"),
        SlashCommand(name: "/음악", description: "음악 재생 제어", example: "지금 재생 중인 곡", toolGroup: "music"),
        SlashCommand(name: "/연락처", description: "연락처 검색", example: "김철수 연락처 찾아줘", toolGroup: "contacts"),
        SlashCommand(name: "/git", description: "Git 상태/로그", example: "git 상태 확인", toolGroup: "git"),
        SlashCommand(name: "/github", description: "GitHub 이슈/PR", example: "GitHub 이슈 목록", toolGroup: "github"),
        SlashCommand(name: "/메모", description: "기억에 저장", example: "이거 기억해줘", toolGroup: "memory"),
        SlashCommand(name: "/이미지", description: "이미지 생성", example: "고양이 그림 그려줘", toolGroup: "image"),
        SlashCommand(name: "/셸", description: "터미널 명령 실행", example: "ls -la 실행해줘", toolGroup: "shell"),
        SlashCommand(name: "/워크플로우", description: "다단계 작업 자동화", example: "워크플로우 목록 보여줘", toolGroup: "workflow"),
        SlashCommand(name: "/설정", description: "앱 설정 변경", example: "모델 바꿔줘", toolGroup: "settings"),
        SlashCommand(name: "/에이전트", description: "에이전트 관리", example: "에이전트 목록 보여줘", toolGroup: "agent"),
        SlashCommand(name: "/도움말", description: "사용 가능한 기능 전체 보기", example: "", toolGroup: nil),
    ]

    /// 입력 텍스트에 매칭되는 슬래시 명령 필터링
    static func matchingCommands(for input: String) -> [SlashCommand] {
        guard input.hasPrefix("/") else { return [] }
        let query = input.lowercased()
        if query == "/" {
            return slashCommands
        }
        return slashCommands.filter {
            $0.name.lowercased().hasPrefix(query) ||
            $0.description.localizedCaseInsensitiveContains(String(query.dropFirst()))
        }
    }
}
