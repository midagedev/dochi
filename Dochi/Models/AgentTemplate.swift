import Foundation

/// 에이전트 생성 위저드에서 사용하는 템플릿 모델
struct AgentTemplate: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let detailedDescription: String
    let suggestedPersona: String
    let suggestedModel: String?
    let suggestedPermissions: [String]
    let suggestedTools: [String]
    let isBuiltIn: Bool
    let accentColor: String

    // MARK: - Built-in Templates

    static let blank = AgentTemplate(
        id: "blank",
        name: "빈 에이전트",
        icon: "person.badge.plus",
        description: "처음부터 직접 설정합니다",
        detailedDescription: "모든 설정을 직접 입력하여 나만의 에이전트를 만듭니다.",
        suggestedPersona: "",
        suggestedModel: nil,
        suggestedPermissions: ["safe"],
        suggestedTools: [],
        isBuiltIn: true,
        accentColor: "gray"
    )

    static let codingAssistant = AgentTemplate(
        id: "coding-assistant",
        name: "코딩 어시스턴트",
        icon: "chevron.left.forwardslash.chevron.right",
        description: "코드 작성, 리뷰, 디버깅을 도와줍니다",
        detailedDescription: "프로그래밍 언어에 능통하며, 코드 작성, 리팩토링, 버그 수정, 코드 리뷰를 수행합니다. 셸 명령 실행과 파일 관리도 지원합니다.",
        suggestedPersona: """
        당신은 숙련된 소프트웨어 엔지니어입니다.
        - 코드를 작성할 때 베스트 프랙티스를 따릅니다
        - 변경 사항을 명확하게 설명합니다
        - 테스트 작성을 권장합니다
        - 성능과 보안을 항상 고려합니다
        """,
        suggestedModel: nil,
        suggestedPermissions: ["safe", "sensitive", "restricted"],
        suggestedTools: ["shell.exec", "file.read", "file.write", "web.search"],
        isBuiltIn: true,
        accentColor: "blue"
    )

    static let researcher = AgentTemplate(
        id: "researcher",
        name: "리서처",
        icon: "magnifyingglass",
        description: "웹 검색과 정보 수집을 수행합니다",
        detailedDescription: "웹 검색, 요약, 분석을 수행하는 연구 보조 에이전트입니다. 최신 정보를 찾아 정리하고, 출처를 명시합니다.",
        suggestedPersona: """
        당신은 꼼꼼한 리서처입니다.
        - 여러 출처를 교차 검증합니다
        - 핵심 내용을 요약하고 출처를 명시합니다
        - 정보의 신뢰도를 평가합니다
        - 추가 조사가 필요한 부분을 알려줍니다
        """,
        suggestedModel: nil,
        suggestedPermissions: ["safe", "sensitive"],
        suggestedTools: ["web.search", "web.fetch"],
        isBuiltIn: true,
        accentColor: "purple"
    )

    static let scheduler = AgentTemplate(
        id: "scheduler",
        name: "스케줄러",
        icon: "calendar",
        description: "일정 관리와 미리알림을 돕습니다",
        detailedDescription: "캘린더 일정과 미리알림을 관리하는 에이전트입니다. 일정 충돌을 확인하고, 효율적인 시간 관리를 제안합니다.",
        suggestedPersona: """
        당신은 효율적인 비서입니다.
        - 일정 충돌을 미리 확인합니다
        - 우선순위에 따라 일정을 제안합니다
        - 미리알림을 적절한 시점에 설정합니다
        - 하루/주간 일정을 요약합니다
        """,
        suggestedModel: nil,
        suggestedPermissions: ["safe", "sensitive"],
        suggestedTools: ["calendar.list", "calendar.create", "reminders.list", "reminders.create"],
        isBuiltIn: true,
        accentColor: "orange"
    )

    static let writer = AgentTemplate(
        id: "writer",
        name: "작가",
        icon: "pencil.line",
        description: "문서 작성과 교정을 도와줍니다",
        detailedDescription: "문서, 이메일, 블로그 글 등 다양한 형태의 텍스트를 작성하고 교정합니다. 톤과 스타일을 조절할 수 있습니다.",
        suggestedPersona: """
        당신은 경험 많은 작가이자 편집자입니다.
        - 독자의 수준에 맞춰 글을 씁니다
        - 명확하고 간결한 문장을 지향합니다
        - 문법과 맞춤법을 꼼꼼히 확인합니다
        - 요청에 따라 톤(격식/비격식)을 조절합니다
        """,
        suggestedModel: nil,
        suggestedPermissions: ["safe"],
        suggestedTools: ["file.write", "web.search"],
        isBuiltIn: true,
        accentColor: "green"
    )

    static let kanbanManager = AgentTemplate(
        id: "kanban-manager",
        name: "칸반 매니저",
        icon: "rectangle.3.group",
        description: "칸반 보드와 태스크를 관리합니다",
        detailedDescription: "칸반 보드를 활용하여 프로젝트와 태스크를 관리합니다. 카드 생성, 이동, 우선순위 설정을 수행합니다.",
        suggestedPersona: """
        당신은 프로젝트 관리 전문가입니다.
        - 태스크를 명확하게 정의합니다
        - 우선순위와 마감일을 관리합니다
        - 진행 상황을 요약합니다
        - 병목 지점을 식별하고 해결책을 제안합니다
        """,
        suggestedModel: nil,
        suggestedPermissions: ["safe", "sensitive"],
        suggestedTools: ["kanban.list", "kanban.create", "kanban.move"],
        isBuiltIn: true,
        accentColor: "teal"
    )

    /// 기본 제공 템플릿 목록 (5종 + blank)
    static let builtInTemplates: [AgentTemplate] = [
        .codingAssistant,
        .researcher,
        .scheduler,
        .writer,
        .kanbanManager,
    ]

    /// Persona 추천 칩 (Step 2에서 사용)
    var personaChips: [String] {
        switch id {
        case "coding-assistant":
            return ["코드 리뷰에 집중", "테스트 우선 개발", "성능 최적화 전문"]
        case "researcher":
            return ["학술 자료 중심", "최신 뉴스 추적", "데이터 분석 전문"]
        case "scheduler":
            return ["미팅 최적화", "데드라인 추적", "워라밸 관리"]
        case "writer":
            return ["기술 문서 전문", "마케팅 카피", "소설/창작"]
        case "kanban-manager":
            return ["스프린트 관리", "개인 태스크", "팀 프로젝트"]
        default:
            return ["친근한 톤", "전문적인 톤", "간결한 답변"]
        }
    }
}
