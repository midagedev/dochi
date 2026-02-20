# K-5: 앱 사용 가이드 빌트인 도구 — `app.guide`

> 상태: UX 설계 완료 / 구현 대기
> 관련 이슈: #176
> 의존: ToolRegistry, BuiltInToolProtocol, KeyboardShortcutHelpView, CapabilityCatalogView, SettingsView
> 보완 관계: UX-9 온보딩 가이드 (#137) — UI 기반 수동 가이드 vs LLM 기반 능동 도구

---

## 1. 설계 목표

사용자가 대화 중 "이 앱 어떻게 써?", "단축키 알려줘", "칸반 사용법" 등의 질문을 할 때, LLM이 `app.guide` 도구를 호출하여 앱 내부의 구조화된 데이터를 기반으로 정확한 안내를 제공한다.

설계 원칙:
- **정보 조회 전용**: 앱 상태를 변경하지 않음 (safe 카테고리)
- **항상 사용 가능**: baseline 도구로 등록, 별도 활성화 불필요
- **기존 데이터 활용**: 하드코딩된 가이드 콘텐츠를 구조화하여 반환 (별도 파일 관리 불필요)
- **LLM 친화적 반환**: JSON 문자열로 반환하여 LLM이 자연어로 재구성

---

## 2. 도구 정의

| 항목 | 값 |
|------|-----|
| 이름 | `app.guide` |
| 카테고리 | `safe` |
| baseline | `true` (항상 사용 가능) |
| 설명 | 앱 사용법, 기능, 단축키, 설정 등의 가이드 정보를 조회합니다. |

### 2.1 파라미터 스키마

```json
{
  "type": "object",
  "properties": {
    "topic": {
      "type": "string",
      "enum": [
        "overview", "features", "shortcuts", "settings", "tools",
        "agents", "workspaces", "kanban", "voice", "memory",
        "mcp", "telegram", "terminal"
      ],
      "description": "가이드 주제. 생략 시 전체 개요(overview) 반환."
    },
    "query": {
      "type": "string",
      "description": "자연어 검색 쿼리. topic 내 또는 전체에서 키워드 매칭."
    }
  }
}
```

### 2.2 파라미터 동작 규칙

| topic | query | 동작 |
|-------|-------|------|
| 있음 | 없음 | 해당 topic의 전체 가이드 반환 |
| 없음 | 있음 | 전체 topic에서 키워드 매칭하여 관련 항목 반환 |
| 있음 | 있음 | topic 범위 내에서 query 필터링 |
| 없음 | 없음 | overview (전체 기능 요약) 반환 |

---

## 3. 반환 데이터 구조

### 3.1 공통 반환 포맷

```json
{
  "topic": "shortcuts",
  "title": "키보드 단축키",
  "items": [ ... ],
  "relatedTopics": ["features", "settings"]
}
```

ToolResult.content에 위 JSON을 문자열로 직렬화하여 반환. LLM이 이를 파싱하여 사용자에게 자연어로 전달.

### 3.2 topic별 상세 스키마

#### overview (전체 개요)

```json
{
  "topic": "overview",
  "title": "도치 앱 개요",
  "items": [
    {
      "topic": "features",
      "title": "주요 기능",
      "summary": "AI 대화, 도구 자동 실행, 칸반 보드, 에이전트 시스템 등"
    },
    {
      "topic": "shortcuts",
      "title": "키보드 단축키",
      "summary": "20+ 단축키로 빠른 조작. ⌘K 커맨드 팔레트, ⌘N 새 대화 등"
    },
    ...
  ],
  "relatedTopics": []
}
```

overview의 items는 모든 topic에 대한 1줄 요약 목록.

#### features (주요 기능)

```json
{
  "topic": "features",
  "title": "주요 기능",
  "items": [
    {
      "category": "대화",
      "icon": "bubble.left.and.bubble.right",
      "features": [
        "텍스트 입력으로 AI와 대화",
        "슬래시 명령 (/ 입력)으로 빠른 기능 실행",
        "음성 입력 (마이크 버튼 또는 웨이크워드)",
        "대화 내보내기 (Markdown, JSON, PDF, 텍스트)",
        "대화 폴더/태그 정리, 즐겨찾기, 일괄 관리"
      ]
    },
    {
      "category": "도구",
      "icon": "wrench.and.screwdriver",
      "features": [
        "AI가 필요한 도구를 자동 선택하여 실행",
        "캘린더/미리알림/타이머/알람 관리",
        "웹 검색, 이미지 생성, 파일 관리",
        "Git/GitHub 연동, 셸 명령 실행",
        "클립보드, 스크린샷, Finder 연동"
      ]
    },
    {
      "category": "칸반 보드",
      "icon": "rectangle.3.group",
      "features": [
        "프로젝트를 칸반 보드로 시각화",
        "대화로 카드 생성/이동/수정 가능",
        "우선순위, 라벨, 담당자 지정"
      ]
    },
    {
      "category": "에이전트",
      "icon": "person.crop.rectangle.stack",
      "features": [
        "목적별 AI 비서 생성 (코딩, 리서치, 일정 등)",
        "에이전트별 고유 페르소나/모델/도구 권한",
        "에이전트 간 태스크 위임"
      ]
    },
    {
      "category": "워크스페이스",
      "icon": "square.stack.3d.up",
      "features": [
        "프로젝트별 독립 공간",
        "워크스페이스별 메모리/에이전트 분리",
        "초대 코드로 협업"
      ]
    },
    {
      "category": "메모리",
      "icon": "brain",
      "features": [
        "대화 내용을 기억 (개인/워크스페이스/에이전트 범위)",
        "메모리 인스펙터 패널 (⌘I)로 확인/편집",
        "자동 메모리 정리 (consolidation)"
      ]
    },
    {
      "category": "음성",
      "icon": "waveform",
      "features": [
        "음성 입력 (Apple STT)",
        "웨이크워드 감지",
        "TTS 음성 출력 (시스템/Google Cloud/Supertonic)"
      ]
    },
    {
      "category": "확장",
      "icon": "puzzlepiece.extension",
      "features": [
        "MCP 서버로 외부 도구 연결",
        "텔레그램 봇 연동",
        "Supabase 클라우드 동기화",
        "외부 도구 세션 관리 (tmux)"
      ]
    }
  ],
  "relatedTopics": ["tools", "shortcuts"]
}
```

#### shortcuts (키보드 단축키)

**데이터 소스**: `KeyboardShortcutHelpView.swift`의 하드코딩된 데이터와 동일.

```json
{
  "topic": "shortcuts",
  "title": "키보드 단축키",
  "items": [
    {
      "section": "대화",
      "entries": [
        { "keys": "⌘N", "description": "새 대화" },
        { "keys": "⌘1~9", "description": "대화 목록에서 N번째 대화 선택" },
        { "keys": "⌘E", "description": "현재 대화 빠른 내보내기 (Markdown)" },
        { "keys": "⌘⇧E", "description": "내보내기 옵션 시트" },
        { "keys": "⌘⇧L", "description": "즐겨찾기 필터 토글" },
        { "keys": "⌘⇧M", "description": "일괄 선택 모드 토글" },
        { "keys": "Esc", "description": "요청 취소" },
        { "keys": "Enter", "description": "메시지 전송" },
        { "keys": "⇧Enter", "description": "줄바꿈" }
      ]
    },
    {
      "section": "탐색",
      "entries": [
        { "keys": "⌘⇧A", "description": "에이전트 전환" },
        { "keys": "⌘⇧W", "description": "워크스페이스 전환" },
        { "keys": "⌘⇧U", "description": "사용자 전환" },
        { "keys": "⌘⇧K", "description": "칸반/대화 전환" }
      ]
    },
    {
      "section": "패널",
      "entries": [
        { "keys": "⌘I", "description": "메모리 인스펙터 패널" },
        { "keys": "⌘⌥I", "description": "컨텍스트 인스펙터 (시트)" },
        { "keys": "⌘⇧S", "description": "시스템 상태" },
        { "keys": "⌘⇧F", "description": "기능 카탈로그" },
        { "keys": "⌘,", "description": "설정" }
      ]
    },
    {
      "section": "메뉴바",
      "entries": [
        { "keys": "⌘⇧D", "description": "메뉴바 퀵 액세스 토글 (글로벌)" }
      ]
    },
    {
      "section": "명령 팔레트",
      "entries": [
        { "keys": "⌘K", "description": "커맨드 팔레트 열기" },
        { "keys": "⌘/", "description": "단축키 도움말 표시" }
      ]
    },
    {
      "section": "터미널",
      "entries": [
        { "keys": "⌃`", "description": "터미널 패널 토글" }
      ]
    }
  ],
  "relatedTopics": ["features", "tools"]
}
```

#### settings (설정 안내)

**데이터 소스**: UX-9 설정 도움말 데이터 + SettingsSidebarView 섹션 구조.

```json
{
  "topic": "settings",
  "title": "설정 안내",
  "items": [
    {
      "section": "일반",
      "icon": "gear",
      "description": "글꼴 크기, 상호작용 모드, 웨이크워드, 아바타, 하트비트 설정",
      "access": "⌘, → 일반"
    },
    {
      "section": "AI 모델",
      "icon": "cpu",
      "description": "LLM 프로바이더, 모델 선택, 컨텍스트 크기, 용도별 라우팅",
      "access": "⌘, → AI 모델"
    },
    {
      "section": "API 키",
      "icon": "key",
      "description": "프로바이더별 API 키 관리 (키체인 암호화 저장)",
      "access": "⌘, → API 키"
    },
    {
      "section": "음성",
      "icon": "waveform",
      "description": "TTS 프로바이더, 음성 속도/피치, Supertonic ONNX 설정",
      "access": "⌘, → 음성"
    },
    {
      "section": "사용자",
      "icon": "person.2",
      "description": "가족 프로필 관리, 사용자 추가/전환",
      "access": "⌘, → 사용자"
    },
    {
      "section": "에이전트",
      "icon": "person.crop.rectangle.stack",
      "description": "에이전트 생성/편집/삭제, 템플릿, 도구 권한",
      "access": "⌘, → 에이전트"
    },
    {
      "section": "도구",
      "icon": "wrench.and.screwdriver",
      "description": "내장 도구 목록, 기본/조건부 도구 현황",
      "access": "⌘, → 도구"
    },
    {
      "section": "통합",
      "icon": "link",
      "description": "텔레그램 봇, MCP 서버 연결",
      "access": "⌘, → 통합"
    },
    {
      "section": "계정",
      "icon": "person.circle",
      "description": "Supabase 클라우드 연결, 동기화 설정",
      "access": "⌘, → 계정"
    }
  ],
  "relatedTopics": ["features", "tools"]
}
```

#### tools (도구 목록)

**데이터 소스**: `ToolRegistry.allToolInfos` (실시간 동적 데이터).

이 topic은 다른 topic과 달리 **실시간 데이터**를 사용한다. ToolRegistry에서 등록된 도구 목록을 읽어 반환.

```json
{
  "topic": "tools",
  "title": "내장 도구 목록",
  "totalCount": 85,
  "items": [
    {
      "group": "calendar",
      "tools": [
        {
          "name": "calendar.list_events",
          "description": "캘린더 일정 조회",
          "category": "safe",
          "isBaseline": true,
          "isEnabled": true
        },
        ...
      ]
    },
    ...
  ],
  "relatedTopics": ["features", "settings"]
}
```

도구가 많으므로 group별로 묶어서 반환. query가 있으면 이름/설명에서 필터링하여 해당 도구만 반환.

#### agents (에이전트)

```json
{
  "topic": "agents",
  "title": "에이전트 시스템",
  "items": [
    {
      "title": "에이전트란?",
      "content": "목적에 맞게 설정된 AI 비서입니다. 각 에이전트는 고유한 페르소나, 모델, 도구 권한을 가집니다."
    },
    {
      "title": "에이전트 만들기",
      "content": "설정 > 에이전트에서 템플릿으로 빠르게 생성하거나, 대화에서 '코딩 에이전트 만들어줘'라고 요청할 수 있습니다."
    },
    {
      "title": "에이전트 전환",
      "content": "사이드바 상단 드롭다운 또는 ⌘⇧A 단축키로 전환합니다."
    },
    {
      "title": "에이전트 간 태스크 위임",
      "content": "현재 에이전트가 다른 에이전트에게 태스크를 위임할 수 있습니다. 예: '이 코드 리뷰를 코딩 에이전트에게 맡겨줘'."
    },
    {
      "title": "에이전트 편집 도구",
      "content": "대화에서 에이전트의 페르소나, 메모리, 설정을 직접 편집할 수 있습니다 (agent.persona.*, agent.memory.*, agent.config.* 도구)."
    }
  ],
  "relatedTopics": ["workspaces", "tools"]
}
```

#### workspaces (워크스페이스)

```json
{
  "topic": "workspaces",
  "title": "워크스페이스",
  "items": [
    {
      "title": "워크스페이스란?",
      "content": "프로젝트별 독립 공간입니다. 각 워크스페이스에 별도의 메모리, 에이전트, 대화가 분리됩니다."
    },
    {
      "title": "워크스페이스 만들기",
      "content": "대화에서 '새 워크스페이스 만들어줘'라고 요청하거나, 사이드바 헤더의 워크스페이스 드롭다운에서 생성합니다."
    },
    {
      "title": "워크스페이스 전환",
      "content": "사이드바 상단 드롭다운 또는 ⌘⇧W 단축키로 전환합니다."
    },
    {
      "title": "협업",
      "content": "초대 코드를 생성하여 다른 사용자를 워크스페이스에 초대할 수 있습니다 (Supabase 연결 필요)."
    }
  ],
  "relatedTopics": ["agents", "memory"]
}
```

#### kanban (칸반 보드)

```json
{
  "topic": "kanban",
  "title": "칸반 보드",
  "items": [
    {
      "title": "칸반 보드란?",
      "content": "프로젝트 작업을 시각적으로 관리하는 보드입니다. 열(column)별로 카드를 이동하며 진행 상황을 추적합니다."
    },
    {
      "title": "보드 만들기",
      "content": "대화에서 '프로젝트 보드 만들어줘'라고 요청하거나, 사이드바에서 칸반 탭 > + 버튼을 클릭합니다."
    },
    {
      "title": "카드 관리",
      "content": "대화에서 카드 추가/이동/수정이 가능합니다. 예: '이 태스크를 완료로 옮겨줘', '새 카드 추가해줘'."
    },
    {
      "title": "카드 속성",
      "content": "우선순위(urgent/high/medium/low), 라벨, 담당자, 설명을 설정할 수 있습니다."
    },
    {
      "title": "접근 방법",
      "content": "사이드바의 칸반 탭(⌘⇧K로 전환) 또는 대화에서 칸반 도구를 사용합니다."
    }
  ],
  "relatedTopics": ["features", "tools"]
}
```

#### voice (음성)

```json
{
  "topic": "voice",
  "title": "음성 입력/출력",
  "items": [
    {
      "title": "음성 입력",
      "content": "하단 입력바의 마이크 버튼을 누르거나, 웨이크워드를 말하면 음성 입력이 시작됩니다. Apple STT를 사용합니다."
    },
    {
      "title": "웨이크워드",
      "content": "기본값 '도치야'. 설정 > 일반에서 변경 가능. '항상 대기 모드'를 켜면 앱이 활성화된 동안 계속 감지합니다."
    },
    {
      "title": "TTS (텍스트→음성)",
      "content": "세 가지 엔진 지원: 시스템 TTS (기본, 추가 설정 불필요), Google Cloud TTS (자연스러운 음성, API 키 필요), Supertonic (로컬 ONNX, 오프라인 가능)."
    },
    {
      "title": "설정",
      "content": "설정 > 음성에서 TTS 프로바이더, 속도, 피치 등을 조절합니다. 설정 > 일반에서 상호작용 모드(음성+텍스트/텍스트 전용)를 변경합니다."
    }
  ],
  "relatedTopics": ["settings", "features"]
}
```

#### memory (메모리)

```json
{
  "topic": "memory",
  "title": "메모리 시스템",
  "items": [
    {
      "title": "메모리란?",
      "content": "대화에서 중요한 정보를 기억하는 시스템입니다. 세 가지 범위: 개인(사용자별), 워크스페이스(프로젝트별), 에이전트(에이전트별)."
    },
    {
      "title": "메모리 저장",
      "content": "대화 중 '이거 기억해줘'라고 요청하면 AI가 save_memory 도구로 저장합니다. 자동 메모리 정리(consolidation)도 지원합니다."
    },
    {
      "title": "메모리 확인/편집",
      "content": "⌘I로 메모리 인스펙터 패널을 열어 계층별 메모리를 확인하고 직접 편집할 수 있습니다."
    },
    {
      "title": "메모리 정리",
      "content": "대화가 길어지면 자동으로 메모리를 정리(consolidation)합니다. 설정 > 일반에서 자동 정리 옵션을 조절할 수 있습니다."
    }
  ],
  "relatedTopics": ["features", "agents"]
}
```

#### mcp (MCP 서버)

```json
{
  "topic": "mcp",
  "title": "MCP (Model Context Protocol)",
  "items": [
    {
      "title": "MCP란?",
      "content": "외부 도구 서버를 AI에 연결하는 프로토콜입니다. 데이터베이스, 사내 API 등을 도치가 직접 사용할 수 있습니다."
    },
    {
      "title": "서버 추가",
      "content": "설정 > 통합 > MCP에서 서버를 추가하거나, 대화에서 'MCP 서버 추가해줘'라고 요청합니다. stdio, sse, streamable-http 전송 지원."
    },
    {
      "title": "도구 사용",
      "content": "MCP 서버가 연결되면 해당 서버의 도구가 자동으로 AI에 노출됩니다. 별도 활성화 불필요."
    }
  ],
  "relatedTopics": ["tools", "settings"]
}
```

#### telegram (텔레그램)

```json
{
  "topic": "telegram",
  "title": "텔레그램 연동",
  "items": [
    {
      "title": "텔레그램 봇 연결",
      "content": "@BotFather에서 봇을 만들고, 설정 > 통합 > 텔레그램에서 토큰을 입력합니다. 또는 대화에서 '텔레그램 연결해줘'라고 요청합니다."
    },
    {
      "title": "사용법",
      "content": "텔레그램 DM으로 봇에게 메시지를 보내면 도치가 응답합니다. 스트리밍 응답, 이미지 전송 등을 지원합니다."
    },
    {
      "title": "워크스페이스 매핑",
      "content": "텔레그램 채팅을 특정 워크스페이스에 연결할 수 있습니다. 설정 > 통합에서 매핑을 관리합니다."
    }
  ],
  "relatedTopics": ["settings", "features"]
}
```

#### terminal (터미널)

```json
{
  "topic": "terminal",
  "title": "통합 터미널",
  "items": [
    {
      "title": "터미널 패널",
      "content": "⌃` (Ctrl+백틱)으로 하단 터미널 패널을 토글합니다. 여러 세션을 탭으로 관리할 수 있습니다."
    },
    {
      "title": "AI와 터미널",
      "content": "대화에서 셸 명령 실행을 요청하면 터미널 패널에서 실행됩니다. 'npm install 해줘' 같은 요청이 가능합니다."
    },
    {
      "title": "설정",
      "content": "설정에서 셸 경로, 글꼴 크기, 최대 세션 수, 명령 타임아웃 등을 조절할 수 있습니다."
    }
  ],
  "relatedTopics": ["tools", "settings"]
}
```

---

## 4. 검색(query) 동작

### 4.1 검색 알고리즘

query가 제공되면 다음 필드에서 대소문자 무시 키워드 매칭을 수행:

1. 각 topic의 `title`
2. 각 item의 `title`, `content`, `description`, `features`, `keys` 등 텍스트 필드
3. 도구 목록의 경우 `name`, `description`

### 4.2 검색 결과 반환

```json
{
  "topic": "search",
  "title": "검색 결과: '칸반'",
  "query": "칸반",
  "items": [
    {
      "sourceTopic": "kanban",
      "title": "칸반 보드란?",
      "content": "프로젝트 작업을 시각적으로 관리하는 보드입니다..."
    },
    {
      "sourceTopic": "shortcuts",
      "title": "⌘⇧K",
      "content": "칸반/대화 전환"
    },
    {
      "sourceTopic": "tools",
      "title": "kanban.create_board",
      "content": "칸반 보드를 생성합니다."
    }
  ],
  "relatedTopics": ["kanban", "features"]
}
```

### 4.3 결과 제한

- 검색 결과는 최대 **20개** 항목으로 제한 (LLM 토큰 절약)
- 관련도 순: title 매칭 > content 매칭 순으로 정렬

---

## 5. 가이드 콘텐츠 관리

### 5.1 콘텐츠 소스

| topic | 소스 | 유형 |
|-------|------|------|
| overview | 하드코딩 (topic 목록 집계) | 정적 |
| features | 하드코딩 (8개 카테고리) | 정적 |
| shortcuts | 하드코딩 (KeyboardShortcutHelpView와 동일 데이터) | 정적 |
| settings | 하드코딩 (UX-9 설정 도움말과 동일 데이터) | 정적 |
| tools | `ToolRegistry.allToolInfos` | **동적** |
| agents | 하드코딩 (개념 설명) | 정적 |
| workspaces | 하드코딩 (개념 설명) | 정적 |
| kanban | 하드코딩 (사용법) | 정적 |
| voice | 하드코딩 (설정 안내) | 정적 |
| memory | 하드코딩 (개념 설명) | 정적 |
| mcp | 하드코딩 (연결 안내) | 정적 |
| telegram | 하드코딩 (연결 안내) | 정적 |
| terminal | 하드코딩 (사용법) | 정적 |

### 5.2 정적 콘텐츠 구조

`AppGuideTool.swift` 내부에 `AppGuideContent` 네임스페이스(또는 enum)로 정적 데이터를 구성한다. 별도 JSON 파일이나 외부 리소스 없이 Swift 코드 내 하드코딩.

이유:
- 가이드 콘텐츠는 앱 기능과 강하게 결합되어 있으므로, 기능 변경 시 코드와 함께 업데이트되는 것이 자연스러움
- 별도 파일 관리 오버헤드 불필요
- 빌드 타임에 오류 검출 가능

### 5.3 동적 콘텐츠 (tools topic)

tools topic만 ToolRegistry에서 실시간 데이터를 조회. `AppGuideTool`이 `ToolRegistry` 참조를 보유하여 execute 시점에 `allToolInfos`를 읽음.

---

## 6. 설정 UI

### 6.1 AppSettings 추가 필드

```swift
// MARK: - App Guide (K-5)

var appGuideEnabled: Bool = UserDefaults.standard.object(forKey: "appGuideEnabled") as? Bool ?? true {
    didSet { UserDefaults.standard.set(appGuideEnabled, forKey: "appGuideEnabled") }
}
```

### 6.2 설정 UI 위치

설정에 별도 섹션을 추가하지 않는다. `app.guide`는 baseline 도구이므로 **도구 설정(ToolsSettingsView)** 목록에 자동으로 표시되며, 기존 도구와 동일한 방식으로 정보를 확인할 수 있다.

`appGuideEnabled` 설정은 도구 등록 시 조건부로 사용:
- `true` (기본): `app.guide` 도구를 ToolRegistry에 등록
- `false`: 등록하지 않음 (LLM이 호출 불가)

이 토글은 **설정 > 일반 > 가이드** 섹션(UX-9에서 이미 정의)에 추가:

```
섹션: "가이드"
├── [기능 투어 다시 보기] 버튼          (기존, UX-9)
├── [인앱 힌트 초기화] 버튼              (기존, UX-9)
├── Toggle: "인앱 힌트 표시"             (기존, UX-9)
└── Toggle: "AI 앱 가이드 도구"          (신규, K-5)
    Caption: "AI가 앱 사용법 질문에 정확한 가이드를 제공합니다"
```

---

## 7. 기존 패턴과의 일관성

### 7.1 BuiltInToolProtocol 준수

```swift
@MainActor
final class AppGuideTool: BuiltInToolProtocol {
    let name = "app.guide"
    let category: ToolCategory = .safe
    let description = "앱 사용법, 기능, 단축키, 설정 등의 가이드 정보를 조회합니다."
    let isBaseline = true

    private let registry: ToolRegistry

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    var inputSchema: [String: Any] { ... }
    func execute(arguments: [String: Any]) async -> ToolResult { ... }
}
```

- 기존 `ToolsListTool`과 동일한 패턴: ToolRegistry 참조를 생성자에서 받음
- `safe` + `isBaseline = true`로 항상 노출
- ToolResult.content에 JSON 문자열 반환 (기존 도구들과 동일)

### 7.2 BuiltInToolService 등록

```swift
// BuiltInToolService.init 내부
// App Guide (baseline, safe) (K-5)
if settings.appGuideEnabled {
    registry.register(AppGuideTool(registry: registry))
}
```

`settings` 참조가 이미 init 파라미터로 전달되므로, 조건부 등록이 기존 패턴과 일관적.

### 7.3 도구 이름 규칙

- `app.guide`: 기존 `app` 그룹이 없으므로 새 그룹 생성
- ToolInfo.group 매핑에서 `app` → `"app"` (기본 동작, 별도 추가 불필요)
- OpenAI 호환: `app-_-guide` (기존 sanitize 로직 자동 적용)

---

## 8. ToolRegistry / 도구 목록 등록

### 8.1 spec/tools.md 업데이트

Baseline 테이블에 추가:

```
| `app.guide` | safe | { topic?, query? } | appGuideEnabled=true (기본) |
```

### 8.2 ui-inventory.md 업데이트

도구 목록에 `app.guide` 추가 — 자동 표시 (ToolsSettingsView가 allToolInfos를 동적으로 읽으므로 별도 UI 변경 불필요).

---

## 9. 구현 파일 목록

### 9.1 신규 파일

| 파일 | 설명 |
|------|------|
| `Dochi/Services/Tools/AppGuideTool.swift` | 도구 구현 + 정적 가이드 콘텐츠 |
| `DochiTests/AppGuideToolTests.swift` | 단위 테스트 |

### 9.2 수정 파일

| 파일 | 변경 |
|------|------|
| `Dochi/Services/Tools/BuiltInToolService.swift` | `AppGuideTool` 등록 (조건부: appGuideEnabled) |
| `Dochi/Models/AppSettings.swift` | `appGuideEnabled` 프로퍼티 추가 |
| `spec/tools.md` | baseline 테이블에 `app.guide` 추가 |

### 9.3 변경 불필요

- `project.yml`: 자동 포함 (Dochi/ 하위 자동 인식)
- `ToolRegistry.swift`: 변경 없음 (register 호출만)
- `ToolsSettingsView.swift`: 변경 없음 (allToolInfos 동적 표시)
- 설정 UI: UX-9 가이드 섹션이 이미 있다면 토글 1개 추가만

---

## 10. 테스트 계획

### 10.1 단위 테스트

| 테스트 | 검증 내용 |
|--------|----------|
| `testOverviewTopic` | topic 미지정 시 overview 반환, 모든 topic 요약 포함 |
| `testShortcutsTopic` | shortcuts topic 반환, 섹션별 단축키 데이터 정확성 |
| `testFeaturesTopic` | features topic 반환, 8개 카테고리 포함 |
| `testSettingsTopic` | settings topic 반환, 모든 설정 섹션 포함 |
| `testToolsTopic` | tools topic 반환, ToolRegistry의 실시간 데이터와 일치 |
| `testQuerySearch` | query 검색 시 관련 항목 반환, 무관한 항목 제외 |
| `testTopicWithQuery` | topic + query 조합 시 해당 topic 내에서만 검색 |
| `testEmptyQueryResult` | 매칭 없는 query 시 빈 결과 + 안내 메시지 |
| `testAllTopics` | 모든 13개 topic에 대해 유효한 JSON 반환 |
| `testInvalidTopic` | 잘못된 topic 값 시 에러 메시지 반환 |

### 10.2 스모크 테스트

`app.guide`가 baseline 도구로 등록되어 있는지 확인:
- tools.list 실행 시 `app.guide`가 `[기본]`으로 표시되는지 검증

---

## 11. UX-9와의 관계 정리

| 측면 | UX-9 온보딩 가이드 | K-5 app.guide 도구 |
|------|-------------------|-------------------|
| 트리거 | 앱 UI (첫 실행, 첫 진입, 설정) | 사용자 질문 → LLM 호출 |
| 대상 | 시각적 UI 가이드 | 구조화된 텍스트 데이터 |
| 시점 | 1회성 (온보딩, 힌트) | 무제한 반복 |
| 범위 | 핵심 기능 투어, 맥락 힌트 | 모든 기능의 상세 가이드 |
| 데이터 | UI 컴포넌트 직접 표시 | JSON → LLM → 자연어 |

둘은 **보완 관계**. UX-9는 시각적 발견을, K-5는 대화 기반 안내를 담당.

---

## 12. 구현 순서 (권장)

| 순서 | 작업 | 예상 난이도 |
|------|------|------------|
| 1 | `AppSettings.appGuideEnabled` 추가 | 하 |
| 2 | `AppGuideTool.swift` — 정적 콘텐츠 + execute 구현 | 중 |
| 3 | `BuiltInToolService` 등록 | 하 |
| 4 | `AppGuideToolTests.swift` 단위 테스트 | 중 |
| 5 | 설정 UI 가이드 섹션에 토글 추가 (선택) | 하 |
| 6 | spec/tools.md 업데이트 | 하 |

---

*최종 업데이트: 2026-02-16*
