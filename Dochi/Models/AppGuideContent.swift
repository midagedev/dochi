import Foundation

/// app.guide 도구가 반환하는 가이드 항목
struct GuideItem: Sendable {
    let title: String
    let description: String
    let shortcut: String?
    let category: String?
    let example: String?
}

/// app.guide 도구가 반환하는 가이드 응답
struct GuideResponse: Sendable {
    let topic: String
    let items: [GuideItem]
    let relatedTopics: [String]

    func formatted() -> String {
        var lines: [String] = []
        lines.append("[\(topic)] 가이드 (\(items.count)개 항목)")
        lines.append("")

        for item in items {
            var line = "- \(item.title)"
            if let shortcut = item.shortcut {
                line += " (\(shortcut))"
            }
            if let category = item.category {
                line += " [\(category)]"
            }
            lines.append(line)
            lines.append("  \(item.description)")
            if let example = item.example {
                lines.append("  예시: \"\(example)\"")
            }
        }

        if !relatedTopics.isEmpty {
            lines.append("")
            lines.append("관련 주제: \(relatedTopics.joined(separator: ", "))")
            lines.append("(app.guide 도구에 topic 파라미터로 조회 가능)")
        }

        return lines.joined(separator: "\n")
    }
}

/// 앱 가이드 콘텐츠 생성기
/// ToolRegistry 등 런타임 데이터와 정적 가이드 데이터를 결합하여 가이드 응답을 생성한다.
@MainActor
enum AppGuideContentBuilder {

    // MARK: - Topics

    static let allTopics = [
        "features", "shortcuts", "settings", "tools", "agents",
        "workspaces", "kanban", "voice", "memory", "mcp",
        "telegram", "terminal",
    ]

    // MARK: - Build

    /// 검색 결과 최대 항목 수 (LLM 토큰 절약)
    static let maxSearchResults = 20

    static func build(topic: String?, query: String?, toolRegistry: ToolRegistry?) -> GuideResponse {
        if let topic, !topic.isEmpty, topic != "overview" {
            let items = contentFor(topic: topic, toolRegistry: toolRegistry)
            let filtered = applyQuery(items, query: query)
            // query가 있으면 검색 결과 제한, topic만이면 전체 반환
            let limited = query != nil && !query!.isEmpty ? Array(filtered.prefix(maxSearchResults)) : filtered
            return GuideResponse(
                topic: topic,
                items: limited,
                relatedTopics: relatedTopics(for: topic)
            )
        }

        if let query, !query.isEmpty {
            // query만 전달: 모든 topic에서 검색
            var allItems: [GuideItem] = []
            for t in allTopics {
                allItems.append(contentsOf: contentFor(topic: t, toolRegistry: toolRegistry))
            }
            let filtered = applyQuery(allItems, query: query)
            return GuideResponse(
                topic: "검색: \(query)",
                items: Array(filtered.prefix(maxSearchResults)),
                relatedTopics: allTopics
            )
        }

        // 둘 다 미전달 또는 topic == "overview": overview
        return buildOverview()
    }

    // MARK: - Overview

    private static func buildOverview() -> GuideResponse {
        let items = [
            GuideItem(
                title: "기능 카테고리",
                description: "일정, 칸반, 검색, 파일, 개발, 미디어, 메모리, 확장(MCP) 등 8개 카테고리 35개+ 도구를 대화로 사용할 수 있습니다.",
                shortcut: nil, category: nil, example: "오늘 일정 알려줘"
            ),
            GuideItem(
                title: "음성 대화",
                description: "마이크 버튼 또는 웨이크워드로 음성 입력을 시작합니다. TTS로 음성 답변도 가능합니다.",
                shortcut: nil, category: nil, example: nil
            ),
            GuideItem(
                title: "에이전트",
                description: "목적에 맞는 AI 비서를 만들어 사용합니다. 코딩, 리서치, 일정 관리 등 템플릿이 준비되어 있습니다.",
                shortcut: "⌘⇧A", category: nil, example: nil
            ),
            GuideItem(
                title: "워크스페이스",
                description: "프로젝트별 독립 공간을 만들어 에이전트와 메모리를 분리할 수 있습니다.",
                shortcut: "⌘⇧W", category: nil, example: nil
            ),
            GuideItem(
                title: "칸반 보드",
                description: "프로젝트를 칸반으로 시각화하고 관리합니다. 대화로 카드를 추가/이동할 수 있습니다.",
                shortcut: "⌘⇧K", category: nil, example: "프로젝트 보드 만들어줘"
            ),
            GuideItem(
                title: "커맨드 팔레트",
                description: "기능, 에이전트 전환, 설정 등 거의 모든 동작을 빠르게 실행합니다.",
                shortcut: "⌘K", category: nil, example: nil
            ),
            GuideItem(
                title: "메모리",
                description: "대화 내용을 기억하고 개인 정보를 관리합니다. 워크스페이스/에이전트/개인별 3계층 메모리.",
                shortcut: "⌘I", category: nil, example: "이거 기억해줘"
            ),
        ]

        return GuideResponse(
            topic: "overview",
            items: items,
            relatedTopics: allTopics
        )
    }

    // MARK: - Per-Topic Content

    private static func contentFor(topic: String, toolRegistry: ToolRegistry?) -> [GuideItem] {
        switch topic {
        case "features":
            return featuresContent()
        case "shortcuts":
            return shortcutsContent()
        case "settings":
            return settingsContent()
        case "tools":
            return toolsContent(registry: toolRegistry)
        case "agents":
            return agentsContent()
        case "workspaces":
            return workspacesContent()
        case "kanban":
            return kanbanContent()
        case "voice":
            return voiceContent()
        case "memory":
            return memoryContent()
        case "mcp":
            return mcpContent()
        case "telegram":
            return telegramContent()
        case "terminal":
            return terminalContent()
        default:
            return []
        }
    }

    // MARK: - Features

    private static func featuresContent() -> [GuideItem] {
        [
            GuideItem(title: "일정 & 미리알림", description: "캘린더 조회/추가, 미리알림 관리, 타이머, 알람 설정", shortcut: nil, category: "일정", example: "오늘 일정 알려줘"),
            GuideItem(title: "칸반 보드", description: "프로젝트를 칸반으로 시각화하고 관리. 보드 생성, 카드 추가/이동/삭제", shortcut: nil, category: "칸반", example: "칸반 보드 현황 보여줘"),
            GuideItem(title: "웹 검색", description: "실시간 웹 검색과 정보 수집 (Tavily API)", shortcut: nil, category: "검색", example: "최신 AI 뉴스 검색해줘"),
            GuideItem(title: "파일 & 클립보드", description: "파일 탐색, 읽기/쓰기, 클립보드 읽기/쓰기, 스크린샷", shortcut: nil, category: "파일", example: "데스크탑 파일 목록 보여줘"),
            GuideItem(title: "개발 도구", description: "Git 상태/로그/커밋, GitHub 이슈/PR, 셸 명령 실행, 코드 리뷰", shortcut: nil, category: "개발", example: "git 상태 확인해줘"),
            GuideItem(title: "미디어", description: "음악 재생/제어, 이미지 생성 (fal.ai), 스크린샷 캡처", shortcut: nil, category: "미디어", example: "지금 재생 중인 곡 뭐야?"),
            GuideItem(title: "메모리", description: "대화 내용 기억, 개인 정보 관리. 워크스페이스/에이전트/개인 3계층", shortcut: nil, category: "메모리", example: "이거 기억해줘"),
            GuideItem(title: "확장 (MCP)", description: "Model Context Protocol 서버로 외부 도구 연결. 데이터베이스, API 등", shortcut: nil, category: "확장", example: nil),
        ]
    }

    // MARK: - Shortcuts

    private static func shortcutsContent() -> [GuideItem] {
        [
            // 대화
            GuideItem(title: "새 대화", description: "새로운 대화를 시작합니다", shortcut: "⌘N", category: "대화", example: nil),
            GuideItem(title: "N번째 대화", description: "대화 목록에서 N번째 대화를 선택합니다", shortcut: "⌘1~9", category: "대화", example: nil),
            GuideItem(title: "빠른 내보내기", description: "현재 대화를 Markdown으로 빠르게 내보냅니다", shortcut: "⌘E", category: "대화", example: nil),
            GuideItem(title: "내보내기 옵션", description: "내보내기 형식과 옵션을 선택합니다", shortcut: "⌘⇧E", category: "대화", example: nil),
            GuideItem(title: "즐겨찾기 필터", description: "즐겨찾기한 대화만 필터링합니다", shortcut: "⌘⇧L", category: "대화", example: nil),
            GuideItem(title: "일괄 선택", description: "여러 대화를 선택하여 일괄 작업합니다", shortcut: "⌘⇧M", category: "대화", example: nil),
            GuideItem(title: "요청 취소", description: "진행 중인 AI 응답을 취소합니다", shortcut: "Esc", category: "대화", example: nil),
            GuideItem(title: "메시지 전송", description: "입력한 메시지를 전송합니다", shortcut: "Enter", category: "대화", example: nil),
            GuideItem(title: "줄바꿈", description: "입력 중 줄바꿈을 합니다", shortcut: "⇧Enter", category: "대화", example: nil),
            // 탐색
            GuideItem(title: "에이전트 전환", description: "다른 에이전트로 빠르게 전환합니다", shortcut: "⌘⇧A", category: "탐색", example: nil),
            GuideItem(title: "워크스페이스 전환", description: "다른 워크스페이스로 전환합니다", shortcut: "⌘⇧W", category: "탐색", example: nil),
            GuideItem(title: "사용자 전환", description: "다른 사용자로 전환합니다", shortcut: "⌘⇧U", category: "탐색", example: nil),
            GuideItem(title: "칸반/대화 전환", description: "칸반 보드와 대화 뷰를 전환합니다", shortcut: "⌘⇧K", category: "탐색", example: nil),
            // 패널
            GuideItem(title: "메모리 패널", description: "AI가 기억하는 정보를 확인하고 편집합니다", shortcut: "⌘I", category: "패널", example: nil),
            GuideItem(title: "컨텍스트 인스펙터", description: "현재 컨텍스트 상태를 확인합니다", shortcut: "⌘⌥I", category: "패널", example: nil),
            GuideItem(title: "시스템 상태", description: "시스템 리소스 및 상태를 확인합니다", shortcut: "⌘⇧S", category: "패널", example: nil),
            GuideItem(title: "기능 카탈로그", description: "사용 가능한 전체 기능 목록을 봅니다", shortcut: "⌘⇧F", category: "패널", example: nil),
            GuideItem(title: "설정", description: "앱 설정을 열어 모델, 음성, 도구 등을 조정합니다", shortcut: "⌘,", category: "패널", example: nil),
            // 메뉴바
            GuideItem(title: "메뉴바 퀵 액세스", description: "메뉴바 퀵 액세스를 토글합니다 (글로벌 단축키)", shortcut: "⌘⇧D", category: "메뉴바", example: nil),
            // 명령 팔레트
            GuideItem(title: "커맨드 팔레트", description: "기능, 에이전트 전환, 설정 등을 빠르게 검색하고 실행합니다", shortcut: "⌘K", category: "명령 팔레트", example: nil),
            GuideItem(title: "단축키 도움말", description: "전체 단축키 목록을 표시합니다", shortcut: "⌘/", category: "명령 팔레트", example: nil),
            // 터미널
            GuideItem(title: "터미널 패널 토글", description: "하단 터미널 패널을 열거나 닫습니다", shortcut: "⌃`", category: "터미널", example: nil),
        ]
    }

    // MARK: - Settings

    private static func settingsContent() -> [GuideItem] {
        [
            GuideItem(title: "일반", description: "글꼴 크기, 상호작용 모드, 웨이크워드, 아바타, 하트비트 설정", shortcut: "⌘,", category: "설정", example: nil),
            GuideItem(title: "AI 모델", description: "LLM 프로바이더 선택, 컨텍스트 크기, 용도별 모델 라우팅 (자동 선택)", shortcut: nil, category: "설정", example: "모델 바꿔줘"),
            GuideItem(title: "API 키", description: "프로바이더별 API 키 관리 (macOS 키체인 암호화 저장)", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "음성", description: "TTS 프로바이더 선택 (시스템/Google Cloud/Supertonic), 속도, 음높이", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "가족", description: "여러 사용자가 하나의 도치를 공유. 각 사용자별 메모리/대화 분리", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "에이전트", description: "에이전트 생성/편집/삭제. 템플릿, 페르소나, 도구 권한 설정", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "도구", description: "35개+ 내장 도구 목록 확인. 기본/조건부 도구, 권한 등급 표시", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "통합", description: "텔레그램 봇 연결, MCP 서버 추가/관리", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "계정", description: "Supabase 클라우드 동기화 연결. 대화, 메모리, 설정 동기화", shortcut: nil, category: "설정", example: nil),
        ]
    }

    // MARK: - Tools (Dynamic from Registry)

    private static func toolsContent(registry: ToolRegistry?) -> [GuideItem] {
        guard let registry else {
            return [
                GuideItem(
                    title: "도구 목록",
                    description: "tools.list 도구를 호출하면 현재 사용 가능한 전체 도구 목록을 확인할 수 있습니다.",
                    shortcut: nil, category: nil, example: nil
                ),
            ]
        }

        return registry.allToolInfos.map { info in
            let statusLabel: String
            if info.isBaseline {
                statusLabel = "기본 제공"
            } else if info.isEnabled {
                statusLabel = "활성"
            } else {
                statusLabel = "조건부"
            }

            return GuideItem(
                title: info.name,
                description: info.description,
                shortcut: nil,
                category: "\(statusLabel), \(info.category.rawValue)",
                example: nil
            )
        }
    }

    // MARK: - Agents

    private static func agentsContent() -> [GuideItem] {
        [
            GuideItem(title: "에이전트란?", description: "특정 목적에 맞게 설정된 AI 비서입니다. 고유 페르소나, 모델, 도구 권한을 가집니다.", shortcut: nil, category: "개념", example: nil),
            GuideItem(title: "에이전트 생성", description: "사이드바 + 버튼 또는 대화로 새 에이전트를 만듭니다. 코딩, 리서치, 일정, 작문, 칸반 템플릿이 준비되어 있습니다.", shortcut: nil, category: "사용법", example: "코딩 에이전트 만들어줘"),
            GuideItem(title: "에이전트 전환", description: "사이드바 또는 단축키로 활성 에이전트를 전환합니다.", shortcut: "⌘⇧A", category: "사용법", example: nil),
            GuideItem(title: "페르소나 편집", description: "에이전트의 성격과 행동 지침을 편집합니다. 대화로도 수정 가능합니다.", shortcut: nil, category: "사용법", example: "에이전트 페르소나 보여줘"),
            GuideItem(title: "에이전트 메모리", description: "각 에이전트는 독립된 메모리를 가집니다. 에이전트별로 기억하는 내용이 다릅니다.", shortcut: nil, category: "개념", example: nil),
            GuideItem(title: "태스크 위임", description: "한 에이전트가 다른 에이전트에게 작업을 위임할 수 있습니다.", shortcut: nil, category: "고급", example: nil),
        ]
    }

    // MARK: - Workspaces

    private static func workspacesContent() -> [GuideItem] {
        [
            GuideItem(title: "워크스페이스란?", description: "프로젝트별 독립된 공간입니다. 각 워크스페이스에 별도 메모리와 에이전트를 설정합니다.", shortcut: nil, category: "개념", example: nil),
            GuideItem(title: "워크스페이스 생성", description: "사이드바 또는 대화로 새 워크스페이스를 만듭니다.", shortcut: nil, category: "사용법", example: "새 워크스페이스 만들어줘"),
            GuideItem(title: "워크스페이스 전환", description: "사이드바 드롭다운 또는 단축키로 전환합니다.", shortcut: "⌘⇧W", category: "사용법", example: nil),
            GuideItem(title: "초대 코드", description: "워크스페이스를 다른 사용자와 공유할 수 있습니다 (Supabase 연결 필요).", shortcut: nil, category: "고급", example: nil),
            GuideItem(title: "독립 메모리", description: "워크스페이스별로 별도의 메모리가 유지됩니다. 프로젝트 간 정보가 섞이지 않습니다.", shortcut: nil, category: "개념", example: nil),
        ]
    }

    // MARK: - Kanban

    private static func kanbanContent() -> [GuideItem] {
        [
            GuideItem(title: "보드 생성", description: "새 칸반 보드를 만듭니다. 기본 컬럼: To Do, In Progress, Done", shortcut: nil, category: "사용법", example: "프로젝트 보드 만들어줘"),
            GuideItem(title: "카드 추가", description: "보드에 새 카드를 추가합니다. 제목, 설명, 우선순위, 라벨, 담당자 설정 가능", shortcut: nil, category: "사용법", example: "칸반에 새 카드 추가해줘"),
            GuideItem(title: "카드 이동", description: "카드를 다른 컬럼으로 이동합니다 (드래그 또는 대화)", shortcut: nil, category: "사용법", example: "이 카드 Done으로 옮겨줘"),
            GuideItem(title: "보드 현황", description: "보드의 전체 카드 현황을 확인합니다", shortcut: nil, category: "사용법", example: "칸반 보드 현황 보여줘"),
            GuideItem(title: "칸반 전환", description: "대화 뷰와 칸반 뷰를 전환합니다", shortcut: "⌘⇧K", category: "사용법", example: nil),
            GuideItem(title: "필터링", description: "컬럼, 우선순위별로 카드를 필터링합니다", shortcut: nil, category: "고급", example: nil),
        ]
    }

    // MARK: - Voice

    private static func voiceContent() -> [GuideItem] {
        [
            GuideItem(title: "음성 입력", description: "마이크 버튼을 클릭하거나 웨이크워드를 말해 음성 입력을 시작합니다.", shortcut: nil, category: "사용법", example: nil),
            GuideItem(title: "웨이크워드", description: "기본값 \"도치야\". 설정에서 변경 가능. \"항상 대기 모드\"를 켜면 앱이 활성화된 동안 계속 감지합니다.", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "TTS (텍스트→음성)", description: "AI 응답을 음성으로 읽어줍니다. 시스템 TTS, Google Cloud TTS, Supertonic(로컬 ONNX) 중 선택.", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "상호작용 모드", description: "\"음성 + 텍스트\" 또는 \"텍스트 전용\" 모드를 선택합니다. 텍스트 전용이면 음성 기능 비활성화.", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "침묵 감지", description: "말하다 멈추면 자동으로 음성 입력을 종료합니다. 감지 시간은 설정에서 조절.", shortcut: nil, category: "설정", example: nil),
        ]
    }

    // MARK: - Memory

    private static func memoryContent() -> [GuideItem] {
        [
            GuideItem(title: "3계층 메모리", description: "개인(사용자별), 워크스페이스(프로젝트별), 에이전트(AI별) 세 계층으로 메모리가 관리됩니다.", shortcut: nil, category: "개념", example: nil),
            GuideItem(title: "저장", description: "대화 중 \"이거 기억해줘\"라고 하면 AI가 메모리에 저장합니다.", shortcut: nil, category: "사용법", example: "내가 좋아하는 음식은 파스타야, 기억해줘"),
            GuideItem(title: "조회/편집", description: "메모리 패널에서 저장된 내용을 확인하고 직접 편집할 수 있습니다.", shortcut: "⌘I", category: "사용법", example: nil),
            GuideItem(title: "자동 통합", description: "메모리가 커지면 AI가 자동으로 중복/오래된 내용을 정리합니다 (설정에서 활성화).", shortcut: nil, category: "고급", example: nil),
            GuideItem(title: "시스템 프롬프트", description: "AI의 기본 행동 지침을 설정합니다. ~/Library/Application Support/Dochi/system_prompt.md에서 직접 편집 가능.", shortcut: nil, category: "고급", example: nil),
        ]
    }

    // MARK: - MCP

    private static func mcpContent() -> [GuideItem] {
        [
            GuideItem(title: "MCP란?", description: "Model Context Protocol — AI가 외부 도구와 데이터 소스에 접근할 수 있게 하는 표준 프로토콜입니다.", shortcut: nil, category: "개념", example: nil),
            GuideItem(title: "서버 추가", description: "설정 > 통합 > MCP에서 서버를 추가합니다. 명령어(command)와 인자(arguments)를 설정합니다.", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "대화로 관리", description: "대화에서 도구를 사용해 MCP 서버를 추가/수정/삭제할 수도 있습니다.", shortcut: nil, category: "사용법", example: "MCP 서버 추가해줘"),
            GuideItem(title: "사용 예", description: "데이터베이스 조회, 사내 API 호출, 파일 시스템 접근 등 다양한 외부 도구를 AI가 직접 사용합니다.", shortcut: nil, category: "활용", example: nil),
        ]
    }

    // MARK: - Telegram

    private static func telegramContent() -> [GuideItem] {
        [
            GuideItem(title: "텔레그램 봇 연결", description: "텔레그램 DM으로도 도치와 대화할 수 있습니다. @BotFather에서 봇을 만들고 토큰을 입력합니다.", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "설정 방법", description: "설정 > 통합 > 텔레그램에서 봇 토큰을 입력하고 활성화합니다.", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "스트리밍 응답", description: "텔레그램에서도 응답을 점진적으로 전송할 수 있습니다 (API 호출 증가). 설정에서 토글.", shortcut: nil, category: "설정", example: nil),
            GuideItem(title: "대화로 관리", description: "대화에서 도구를 사용해 텔레그램을 설정할 수도 있습니다.", shortcut: nil, category: "사용법", example: "텔레그램 봇 상태 확인해줘"),
        ]
    }

    // MARK: - Terminal

    private static func terminalContent() -> [GuideItem] {
        [
            GuideItem(title: "터미널 패널", description: "하단 터미널 패널에서 셸 명령을 직접 실행할 수 있습니다. 여러 세션을 탭으로 관리합니다.", shortcut: "⌃`", category: "사용법", example: nil),
            GuideItem(title: "AI와 터미널", description: "대화에서 셸 명령 실행을 요청하면 터미널 패널에서 실행됩니다.", shortcut: nil, category: "사용법", example: "npm install 해줘"),
            GuideItem(title: "설정", description: "셸 경로, 글꼴 크기, 최대 세션 수, 명령 타임아웃 등을 설정에서 조절할 수 있습니다.", shortcut: nil, category: "설정", example: nil),
        ]
    }

    // MARK: - Related Topics

    private static func relatedTopics(for topic: String) -> [String] {
        switch topic {
        case "features": return ["tools", "shortcuts", "settings"]
        case "shortcuts": return ["features", "settings"]
        case "settings": return ["features", "voice", "agents"]
        case "tools": return ["features", "settings", "mcp"]
        case "agents": return ["workspaces", "memory", "tools"]
        case "workspaces": return ["agents", "memory"]
        case "kanban": return ["features", "shortcuts"]
        case "voice": return ["settings", "features"]
        case "memory": return ["agents", "workspaces"]
        case "mcp": return ["tools", "settings"]
        case "telegram": return ["settings", "features"]
        case "terminal": return ["tools", "settings"]
        default: return []
        }
    }

    // MARK: - Query Filtering

    private static func applyQuery(_ items: [GuideItem], query: String?) -> [GuideItem] {
        guard let query, !query.isEmpty else { return items }
        let lowered = query.lowercased()
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(lowered) ||
            $0.description.localizedCaseInsensitiveContains(lowered) ||
            ($0.category?.localizedCaseInsensitiveContains(lowered) ?? false) ||
            ($0.shortcut?.localizedCaseInsensitiveContains(lowered) ?? false) ||
            ($0.example?.localizedCaseInsensitiveContains(lowered) ?? false)
        }
    }
}
