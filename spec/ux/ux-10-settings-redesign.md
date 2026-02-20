# UX-10: 설정 UX 재구성

> 상태: 설계 완료 | 작성일: 2026-02-15

---

## 1. 현재 문제 분석

### 1.1 구조적 문제
- **9개 탭이 수평 나열**: 일반/AI 모델/API 키/음성/가족/에이전트/도구/통합/계정 — 탭이 작아 라벨이 잘 읽히지 않고, 논리적 그룹핑 없이 나열됨
- **별도 윈도우**: `Settings { }` scene으로 열리므로 대화 중 설정을 바꾸려면 윈도우 전환 필요 (컨텍스트 단절)
- **고정 크기**: `frame(width: 600, height: 480)` — 도구 브라우저, 에이전트 그리드 등 넓은 공간이 필요한 탭에서 비좁음

### 1.2 사용 패턴 문제
- **자주 바꾸는 설정**: 모델 변경, 음성 프로바이더 변경, TTS 속도 조절 — 매번 설정 윈도우를 열어야 함
- **관련 설정 분산**: API 키는 별도 탭인데 모델 선택과 밀접. 음성 설정에도 GCP API 키 입력 존재
- **상태 피드백 부재**: 설정 변경 시 즉시 적용되는지, 재시작이 필요한지 알 수 없음

### 1.3 접근성 문제
- 설정 간 이동에 마우스 필수 (탭 클릭)
- 키보드로 특정 설정 항목을 찾을 방법 없음 (검색 없음)
- SystemHealthBarView에서 모델명이 보이지만 클릭해도 설정으로 가지 않음

---

## 2. 설계 목표

1. **사이드바 네비게이션**: 수평 탭 -> 좌측 사이드바 + 논리적 섹션 그룹핑
2. **빠른 설정 팝오버**: 대화 화면에서 모델/음성을 1클릭으로 변경
3. **설정 검색**: 설정 내 키워드 검색으로 2초 내 원하는 항목 도달
4. **적용 피드백**: 변경 즉시 적용 확인, 재시작 필요 항목 표시
5. **기존 단축키 보존**: `Cmd+,`로 설정 열기 유지

---

## 3. 설정 사이드바 패턴

### 3.1 레이아웃

```
┌──────────────────────────────────────────────────────────────────────┐
│ 설정                                                          [닫기] │
├───────────────┬──────────────────────────────────────────────────────┤
│ [🔍 검색...]   │                                                     │
│               │  AI 모델                                             │
│ ── AI ──      │  ─────────────────────────────────────────────       │
│  AI 모델       │  LLM 프로바이더                              [?]     │
│  API 키        │  ┌─────────────────────────────────────────┐       │
│               │  │ 프로바이더:  [OpenAI      ▼]             │       │
│ ── 음성 ──    │  │ 모델:       [gpt-4o      ▼]             │       │
│  음성 합성     │  └─────────────────────────────────────────┘       │
│               │                                                     │
│ ── 일반 ──    │  컨텍스트                                    [?]     │
│  인터페이스    │  ┌─────────────────────────────────────────┐       │
│  웨이크워드    │  │ 컨텍스트 윈도우       128K tokens        │       │
│  하트비트      │  └─────────────────────────────────────────┘       │
│               │                                                     │
│ ── 사람 ──    │  용도별 모델 라우팅                           [?]     │
│  가족 구성원   │  ┌─────────────────────────────────────────┐       │
│  에이전트      │  │ [✓] 자동 모델 선택                       │       │
│               │  │ 경량 모델: ...                           │       │
│ ── 연결 ──    │  │ 고급 모델: ...                           │       │
│  도구          │  └─────────────────────────────────────────┘       │
│  통합 서비스   │                                                     │
│  계정/동기화   │                                                     │
│               │                                                     │
│ ── 도움말 ──  │                                                     │
│  가이드        │                                                     │
├───────────────┤                                                     │
│ v1.x.x        │                                                     │
└───────────────┴──────────────────────────────────────────────────────┘
```

### 3.2 사이드바 섹션 구성

| 그룹 | 항목 | 아이콘 | 원래 위치 |
|------|------|--------|-----------|
| **AI** | AI 모델 | `brain` | AI 모델 탭 |
| | API 키 | `key` | API 키 탭 |
| **음성** | 음성 합성 | `speaker.wave.2` | 음성 탭 |
| **일반** | 인터페이스 | `textformat.size` | 일반 탭 (글꼴, 상호작용 모드) |
| | 웨이크워드 | `mic` | 일반 탭 (웨이크워드 섹션) |
| | 하트비트 | `heart` | 일반 탭 (하트비트 섹션) |
| **사람** | 가족 구성원 | `person.2` | 가족 탭 |
| | 에이전트 | `person.crop.rectangle.stack` | 에이전트 탭 |
| **연결** | 도구 | `wrench.and.screwdriver` | 도구 탭 |
| | 통합 서비스 | `puzzlepiece` | 통합 탭 |
| | 계정/동기화 | `person.circle` | 계정 탭 |
| **도움말** | 가이드 | `play.rectangle` | 일반 탭 (가이드 섹션) |

**변경점 vs 현재**:
- "일반" 탭을 3개로 분리: 인터페이스(글꼴+상호작용 모드+아바타), 웨이크워드, 하트비트
- "가이드" 섹션을 별도 항목으로 분리
- API 키를 "AI" 그룹 하위에 배치하여 모델 설정과 인접

### 3.3 윈도우 크기

- **기본 크기**: 780 x 540 (현재 600 x 480에서 확대)
- **최소 크기**: 680 x 440
- **사이드바 폭**: 180pt (고정)
- **도구/에이전트 탭**: 콘텐츠 영역이 HSplitView/그리드를 포함하므로 넓은 공간 활용 가능

### 3.4 사이드바 검색

**위치**: 사이드바 최상단, 항목 목록 위

**동작**:
1. 검색 필드에 키워드 입력 (예: "모델", "속도", "텔레그램")
2. 사이드바의 섹션 항목을 필터링하여 해당 키워드와 관련된 항목만 표시
3. 검색 결과 선택 시 해당 섹션으로 이동 + 매칭 항목 하이라이트 (3초간 배경색 강조 후 페이드아웃)

**검색 인덱스** (각 사이드바 항목에 연결된 키워드):
| 항목 | 검색 키워드 |
|------|-------------|
| AI 모델 | 모델, 프로바이더, OpenAI, Anthropic, Z.AI, Ollama, 라우팅, 폴백 |
| API 키 | API, 키, key, OpenAI, Anthropic, Tavily, Fal, 티어 |
| 음성 합성 | 음성, TTS, 속도, 피치, Google Cloud, 프로바이더 |
| 인터페이스 | 글꼴, 폰트, 크기, 모드, 아바타, VRM |
| 웨이크워드 | 웨이크워드, 마이크, 침묵, 음성 입력 |
| 하트비트 | 하트비트, 주기, 캘린더, 칸반, 미리알림, 조용한 시간 |
| 가족 구성원 | 가족, 구성원, 프로필, 사용자 |
| 에이전트 | 에이전트, 페르소나, 템플릿 |
| 도구 | 도구, tool, 권한, safe, sensitive, restricted |
| 통합 서비스 | 텔레그램, MCP, 봇, 웹훅 |
| 계정/동기화 | Supabase, 동기화, 로그인, 인증 |
| 가이드 | 투어, 힌트, 온보딩 |

**키보드 동작**: 검색 필드에 포커스된 상태에서 화살표 위/아래로 결과 탐색, Enter로 이동.

### 3.5 사이드바 항목 선택 상태

- **선택된 항목**: `Color.accentColor.opacity(0.12)` 배경 + 볼드 텍스트
- **호버**: `Color.secondary.opacity(0.06)` 배경
- **그룹 헤더**: `font(.caption)`, `.foregroundStyle(.secondary)`, `textCase(.uppercase)`, 위에 12pt 여백
- **아이콘**: 각 항목 왼쪽에 SF Symbols 아이콘 (14pt, `.secondary`)

### 3.6 키보드 네비게이션

| 단축키 | 동작 |
|--------|------|
| `Cmd+,` | 설정 윈도우 열기 (기존 유지) |
| `Cmd+F` (설정 윈도우 내) | 검색 필드로 포커스 이동 |
| 위/아래 화살표 | 사이드바 항목 이동 (검색 결과 내에서도 동작) |
| Escape | 검색 초기화 또는 설정 닫기 |

---

## 4. 빠른 설정 팝오버

### 4.1 진입점

**SystemHealthBarView의 모델명 영역을 클릭 가능하게 변경.**

현재: SystemHealthBarView 전체가 하나의 버튼 -> SystemStatusSheetView 열기.
변경: 각 indicator 영역을 독립 버튼으로 분리.

```
┌────────────────────────────────────────────────────────────┐
│ [⚡ gpt-4o ▼]  |  🟢 동기화  |  ❤️ 3분 전  |  # 2.1K 토큰 │
│   ↑ 클릭 →      ↑ 클릭 →                     ↑ 클릭 →      │
│   모델 팝오버    동기화 시트                    상태 시트     │
└────────────────────────────────────────────────────────────┘
```

| 클릭 영역 | 동작 |
|-----------|------|
| 모델명 (`gpt-4o`) | **QuickModelPopover** 열기 |
| 동기화 상태 | SystemStatusSheetView 열기 (클라우드 탭) |
| 하트비트 상태 | SystemStatusSheetView 열기 (하트비트 탭) |
| 토큰 사용량 | SystemStatusSheetView 열기 (LLM 탭) |

### 4.2 QuickModelPopover (모델 빠른 변경)

**트리거**: SystemHealthBarView 모델명 영역 클릭 또는 `Cmd+Shift+M` (신규 단축키)

```
┌─────────────────────────────────────┐
│ 빠른 모델 변경                       │
│ ─────────────────────────────────── │
│ 프로바이더                           │
│ ┌─────────────────────────────────┐ │
│ │ ○ OpenAI  ○ Anthropic  ○ Z.AI  │ │
│ │ ○ Ollama                       │ │
│ └─────────────────────────────────┘ │
│                                     │
│ 모델                                │
│ ┌─────────────────────────────────┐ │
│ │ ● gpt-4o              128K  ✓  │ │
│ │ ○ gpt-4o-mini          128K    │ │
│ │ ○ gpt-4-turbo          128K    │ │
│ │ ○ o1-preview           128K    │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ☑ 자동 모델 선택 (라우팅)             │
│                                     │
│ ─────────────────────────────────── │
│ [설정에서 상세 설정 열기]       [닫기] │
└─────────────────────────────────────┘
```

**사양**:
- **크기**: 320 x auto (콘텐츠에 따라 높이 조정, 최대 400pt)
- **프로바이더 선택**: 라디오 버튼 그룹 (현재 선택 표시), API 키 미등록 프로바이더는 비활성(dimmed) + "(키 없음)" 표시
- **모델 목록**: 현재 프로바이더의 모델 리스트, 현재 선택된 모델에 체크마크
- **컨텍스트 윈도우**: 각 모델 옆에 `128K` 등 토큰 수 표시
- **자동 모델 선택 토글**: 한 줄로 표시, 토글 가능
- **"설정에서 상세 설정 열기"**: 클릭 시 팝오버 닫고 Settings 윈도우의 "AI 모델" 섹션으로 이동
- **변경 즉시 적용**: 프로바이더/모델 선택 즉시 `settings.llmProvider`, `settings.llmModel` 반영
- **적용 피드백**: 변경 시 모델명 텍스트에 0.3초 `scaleEffect(1.1)` 애니메이션 + SystemHealthBarView의 모델명 즉시 갱신

### 4.3 QuickVoicePopover (음성 빠른 변경) -- 선택적 확장

**트리거**: 커맨드 팔레트에서 "음성 설정" 또는 InputBarView 마이크 버튼 우클릭

```
┌─────────────────────────────────────┐
│ 빠른 음성 설정                       │
│ ─────────────────────────────────── │
│ TTS 프로바이더                       │
│ ○ 시스템 TTS  ○ Google Cloud        │
│ ○ Supertonic                        │
│                                     │
│ 속도: ━━━━━━●━━━━ 1.2x              │
│ 피치: ━━━━●━━━━━━ +0.0              │
│                                     │
│ [▶ 테스트]        [설정에서 열기]     │
└─────────────────────────────────────┘
```

**사양**:
- **크기**: 300 x auto
- **TTS 프로바이더**: 라디오 그룹, 변경 즉시 적용
- **슬라이더**: 속도(0.5~2.0), 피치(-10~+10), 드래그 해제 시 즉시 적용
- **테스트 재생**: "안녕하세요" 문장으로 현재 설정 미리 듣기
- 키 미등록 프로바이더 비활성화 처리 (Google Cloud의 경우 API 키 필요)

---

## 5. 설정 변경 피드백 시스템

### 5.1 즉시 적용 설정 (대부분)

대부분의 설정은 변경 즉시 적용된다. 이를 사용자에게 알리기 위해:

**적용 확인 토스트**: 설정 변경 시 설정 윈도우 하단에 1.5초간 표시 후 페이드아웃.
```
┌─────────────────────────────────────┐
│ ✓ 모델이 gpt-4o로 변경되었습니다     │
└─────────────────────────────────────┘
```

**스타일**:
- 배경: `Color.green.opacity(0.12)` + `ultraThinMaterial`
- 아이콘: `checkmark.circle.fill` (green)
- 폰트: `.callout`
- 애니메이션: slide up + fade in (0.2s), 1.5초 유지, fade out (0.3s)

### 5.2 재시작 필요 설정

일부 설정은 변경 후 재시작(또는 재연결)이 필요하다.

| 설정 | 재시작 유형 | 표시 방법 |
|------|------------|-----------|
| Supabase URL/Anon Key | 재연결 필요 | "연결" 버튼 + 상태 표시 |
| 텔레그램 봇 토큰 | 재연결 필요 | "저장 후 재연결" 라벨 |
| MCP 서버 설정 | 재연결 필요 | 서버별 재연결 버튼 |
| Ollama Base URL | 재연결 필요 | "새로고침" 버튼으로 모델 재탐색 |

**재시작 필요 표시**:
```
┌──────────────────────────────────────────────┐
│ ⚠ 변경 사항을 적용하려면 재연결이 필요합니다    │
│                                [재연결]       │
└──────────────────────────────────────────────┘
```
- 배경: `Color.orange.opacity(0.1)`
- 아이콘: `exclamationmark.triangle.fill` (orange)
- 인라인 액션 버튼 포함

### 5.3 API 키 저장 피드백

현재: "저장" 버튼 클릭 -> "저장 완료" 텍스트 3초 표시.
변경: 저장 성공 시 키 입력 필드 옆 체크마크 아이콘에 `scaleEffect` 애니메이션 추가 + 입력 필드 테두리를 0.5초간 green으로 강조.

### 5.4 설정 변경 로그

설정 변경 시 `Log.app.info("설정 변경: \(key) = \(value)")` 로깅 추가 (디버깅용).

---

## 6. 커맨드 팔레트 통합

### 6.1 신규 팔레트 명령

CommandPaletteView의 items에 설정 관련 명령 추가:

| 명령 ID | 제목 | 카테고리 | 동작 |
|---------|------|----------|------|
| `settings.model` | "모델 빠르게 변경" | settings | QuickModelPopover 열기 |
| `settings.voice` | "음성 빠르게 변경" | settings | QuickVoicePopover 열기 |
| `settings.open` | "설정 열기" | settings | Settings 윈도우 열기 |
| `settings.open.ai` | "AI 모델 설정" | settings | Settings > AI 모델 섹션으로 열기 |
| `settings.open.apikey` | "API 키 설정" | settings | Settings > API 키 섹션으로 열기 |
| `settings.open.voice` | "음성 설정" | settings | Settings > 음성 합성 섹션으로 열기 |
| `settings.open.agent` | "에이전트 설정" | settings | Settings > 에이전트 섹션으로 열기 |
| `settings.open.integration` | "통합 서비스 설정" | settings | Settings > 통합 서비스 섹션으로 열기 |
| `settings.open.account` | "계정/동기화 설정" | settings | Settings > 계정 섹션으로 열기 |

### 6.2 딥링크 메커니즘

설정 윈도우가 특정 섹션으로 열리도록 하기 위해:

1. `SettingsView`에 `@State var selectedSection: SettingsSection` 상태 추가
2. 외부에서 열 때 `initialSection` 파라미터로 원하는 섹션 전달
3. `onAppear`에서 `selectedSection = initialSection`으로 자동 이동

```swift
enum SettingsSection: String, CaseIterable, Identifiable {
    case aiModel = "ai-model"
    case apiKey = "api-key"
    case voice = "voice"
    case interface = "interface"
    case wakeWord = "wake-word"
    case heartbeat = "heartbeat"
    case family = "family"
    case agent = "agent"
    case tools = "tools"
    case integrations = "integrations"
    case account = "account"
    case guide = "guide"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiModel: return "AI 모델"
        case .apiKey: return "API 키"
        case .voice: return "음성 합성"
        case .interface: return "인터페이스"
        case .wakeWord: return "웨이크워드"
        case .heartbeat: return "하트비트"
        case .family: return "가족 구성원"
        case .agent: return "에이전트"
        case .tools: return "도구"
        case .integrations: return "통합 서비스"
        case .account: return "계정/동기화"
        case .guide: return "가이드"
        }
    }

    var icon: String {
        switch self {
        case .aiModel: return "brain"
        case .apiKey: return "key"
        case .voice: return "speaker.wave.2"
        case .interface: return "textformat.size"
        case .wakeWord: return "mic"
        case .heartbeat: return "heart"
        case .family: return "person.2"
        case .agent: return "person.crop.rectangle.stack"
        case .tools: return "wrench.and.screwdriver"
        case .integrations: return "puzzlepiece"
        case .account: return "person.circle"
        case .guide: return "play.rectangle"
        }
    }

    var group: SettingsSectionGroup {
        switch self {
        case .aiModel, .apiKey: return .ai
        case .voice: return .voice
        case .interface, .wakeWord, .heartbeat: return .general
        case .family, .agent: return .people
        case .tools, .integrations, .account: return .connection
        case .guide: return .help
        }
    }
}

enum SettingsSectionGroup: String, CaseIterable {
    case ai = "AI"
    case voice = "음성"
    case general = "일반"
    case people = "사람"
    case connection = "연결"
    case help = "도움말"
}
```

---

## 7. 신규 키보드 단축키

| 단축키 | 동작 | 위치 |
|--------|------|------|
| `Cmd+Shift+M` | QuickModelPopover 열기 | ContentView (hidden button) |

**기존 단축키 변경 없음.** `Cmd+,`는 macOS 표준으로 Settings 윈도우를 열며, 이는 유지한다.

---

## 8. SystemHealthBarView 분리 클릭

### 8.1 현재
- 전체 바가 하나의 `Button`이고 `onTap` 핸들러 하나.

### 8.2 변경
- 각 indicator를 독립 `Button`으로 분리.
- `onTap` 콜백 -> 4개의 개별 콜백으로 변경:

```swift
struct SystemHealthBarView: View {
    // 기존
    let settings: AppSettings
    let metricsCollector: MetricsCollector
    var heartbeatService: HeartbeatService?
    var supabaseService: SupabaseServiceProtocol?

    // 변경: onTap 제거, 개별 콜백 추가
    let onModelTap: () -> Void        // QuickModelPopover 열기
    let onSyncTap: () -> Void         // SystemStatusSheet (클라우드 탭)
    let onHeartbeatTap: () -> Void    // SystemStatusSheet (하트비트 탭)
    let onTokenTap: () -> Void        // SystemStatusSheet (LLM 탭)
}
```

**모델 indicator 시각 변경**: 현재 모델명 뒤에 chevron 추가하여 클릭 가능함을 암시.

```
[cpu.fill] gpt-4o [chevron.down]
```

- chevron은 `font(.system(size: 7))`, `.foregroundStyle(.quaternary)`
- 호버 시 전체 indicator 배경에 `Color.secondary.opacity(0.08)` + `cornerRadius(4)`

---

## 9. 마이그레이션 전략

### 9.1 SettingsView 구조 변경

**현재**: `TabView { ... }` + 9개 `.tabItem`
**변경**: `NavigationSplitView { sidebar } detail: { ... }`

```swift
// 개념적 구조
struct SettingsView: View {
    @State var selectedSection: SettingsSection = .aiModel

    var body: some View {
        NavigationSplitView {
            // 사이드바
            SettingsSidebarView(
                selectedSection: $selectedSection,
                searchText: $searchText
            )
        } detail: {
            // 콘텐츠 영역
            settingsContent(for: selectedSection)
        }
        .frame(minWidth: 680, minHeight: 440)
        .frame(idealWidth: 780, idealHeight: 540)
    }
}
```

### 9.2 기존 뷰 재활용

| 기존 뷰 | 변경 | 비고 |
|---------|------|------|
| `ModelSettingsView` | 그대로 사용 | AI 모델 섹션 콘텐츠로 |
| `APIKeySettingsView` | 그대로 사용 | API 키 섹션 콘텐츠로 |
| `VoiceSettingsView` | 그대로 사용 | 음성 합성 섹션 콘텐츠로 |
| `FamilySettingsView` | 그대로 사용 | 가족 구성원 섹션 콘텐츠로 |
| `AgentSettingsView` | 그대로 사용 | 에이전트 섹션 콘텐츠로 |
| `ToolsSettingsView` | 그대로 사용 | 도구 섹션 콘텐츠로 |
| `IntegrationsSettingsView` | 그대로 사용 | 통합 서비스 섹션 콘텐츠로 |
| `AccountSettingsView` | 그대로 사용 | 계정/동기화 섹션 콘텐츠로 |
| `GeneralSettingsView` | **3개로 분리** | 인터페이스/웨이크워드/하트비트 |

### 9.3 GeneralSettingsView 분리

**InterfaceSettingsContent**: 글꼴 크기, 상호작용 모드, 아바타 설정
**WakeWordSettingsContent**: 웨이크워드 설정 전체 (웨이크워드 활성화, 단어, 침묵 타임아웃, 항상 대기)
**HeartbeatSettingsContent**: 하트비트 설정 전체 (활성화, 주기, 점검 항목, 조용한 시간, 상태)
**GuideSettingsContent**: 기능 투어, 인앱 힌트 관리

분리된 각 뷰는 `Form { }` 래퍼 없이 섹션 콘텐츠만 포함. 상위 `settingsContent(for:)`에서 `Form { ... }.formStyle(.grouped)` 래핑.

---

## 10. 신규 뷰 목록

| 뷰 이름 | 파일 위치 | 설명 |
|---------|-----------|------|
| `SettingsSidebarView` | `Views/Settings/SettingsSidebarView.swift` | 설정 사이드바 (검색 + 그룹별 항목 목록) |
| `QuickModelPopoverView` | `Views/QuickModelPopoverView.swift` | 모델 빠른 변경 팝오버 |
| `QuickVoicePopoverView` | `Views/QuickVoicePopoverView.swift` | 음성 빠른 변경 팝오버 |
| `InterfaceSettingsContent` | `Views/Settings/SettingsView.swift` 내 | 인터페이스 설정 (GeneralSettingsView에서 분리) |
| `WakeWordSettingsContent` | `Views/Settings/SettingsView.swift` 내 | 웨이크워드 설정 (GeneralSettingsView에서 분리) |
| `HeartbeatSettingsContent` | `Views/Settings/SettingsView.swift` 내 | 하트비트 설정 (GeneralSettingsView에서 분리) |
| `GuideSettingsContent` | `Views/Settings/SettingsView.swift` 내 | 가이드 설정 (GeneralSettingsView에서 분리) |
| `SettingsToastView` | `Views/Settings/SettingsView.swift` 내 | 설정 변경 확인 토스트 |

---

## 11. 데이터 흐름 (신규/변경)

### 11.1 모델 빠른 변경

```
SystemHealthBarView 모델명 클릭
  -> ContentView: showQuickModelPopover = true
  -> QuickModelPopoverView 표시 (.popover modifier)
  -> 사용자가 프로바이더/모델 선택
  -> settings.llmProvider / settings.llmModel 즉시 변경
  -> SystemHealthBarView 모델명 자동 갱신 (AppSettings가 @Observable이므로)
  -> QuickModelPopoverView 닫기
  -> (선택) 적용 토스트 표시
```

### 11.2 설정 섹션 딥링크

```
커맨드 팔레트 "AI 모델 설정" 선택
  -> executePaletteAction: openSettings(section: .aiModel)
  -> NSApp.sendAction(Selector(("showSettingsWindow:"))) 호출 (Settings scene 열기)
  -> SettingsView에 환경변수/Notification으로 initialSection 전달
  -> selectedSection = .aiModel
  -> 해당 콘텐츠 표시
```

**주의**: SwiftUI `Settings` scene은 프로그래밍적으로 특정 탭으로 여는 것이 제한적이다. 구현 시 다음 접근법 검토:
- `@SceneStorage`를 사용하여 마지막 선택 섹션 기억 + `NotificationCenter`로 외부에서 섹션 전환 트리거
- 또는 `Settings` scene 대신 별도 `Window`로 설정을 구현하여 완전한 제어 확보 (권장)

---

## 12. 접근성 체크리스트

- [x] 모든 설정 항목에 UI 진입점 (사이드바 네비게이션)
- [x] 검색으로 2초 내 원하는 설정 도달
- [x] 빈 상태 안내: 검색 결과 없을 시 "일치하는 설정이 없습니다"
- [x] 진행/완료/실패 피드백: 토스트 + 재시작 필요 배너
- [x] 키보드 접근: `Cmd+,`, `Cmd+F`(검색), 화살표, Enter
- [x] 빠른 설정: SystemHealthBarView에서 1클릭 모델 변경
- [x] 첫 접근 힌트: 설정 사이드바에 SettingsHelpButton 유지

---

## 13. 구현 우선순위

### Phase 1: 사이드바 전환 (핵심)
1. `SettingsSection` enum 정의
2. `SettingsSidebarView` 구현
3. `SettingsView`를 `NavigationSplitView`로 변경 (TabView 제거)
4. `GeneralSettingsView` -> 4개 콘텐츠 뷰로 분리
5. 검색 기능 구현
6. 윈도우 크기 조정

### Phase 2: 빠른 설정 팝오버
1. `QuickModelPopoverView` 구현
2. `SystemHealthBarView` indicator 분리
3. ContentView에 `Cmd+Shift+M` 단축키 추가
4. 커맨드 팔레트에 설정 관련 명령 추가

### Phase 3: 피드백 시스템
1. `SettingsToastView` 구현
2. 변경 즉시 적용 확인 토스트 연결
3. 재시작 필요 설정에 배너 추가
4. API 키 저장 피드백 개선

### Phase 4: 확장 (선택)
1. `QuickVoicePopoverView` 구현
2. 설정 딥링크 메커니즘 구현
3. 마이크 버튼 우클릭 -> 음성 팝오버

---

## 14. 테스트 범위

| 테스트 | 검증 내용 |
|--------|-----------|
| `SettingsSectionTests` | SettingsSection enum의 title/icon/group 매핑 정확성 |
| `SettingsSearchTests` | 검색 키워드가 올바른 섹션에 매칭되는지 검증 |
| `QuickModelPopoverTests` | 프로바이더/모델 선택 시 settings 즉시 반영 검증 |
| `SystemHealthBarSplitTests` | 각 indicator 클릭 시 올바른 콜백 호출 검증 |
| 스모크 테스트 | 설정 윈도우 열기 -> 각 섹션 이동 -> 값 변경 -> 적용 확인 |
