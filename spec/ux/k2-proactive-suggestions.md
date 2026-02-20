# UX 명세: [K-2] 프로액티브 제안 시스템

> 상태: 설계 완료
> 관련: HeartbeatService, ContextService, ResourceOptimizerService, ConversationView
> 이슈: #165

---

## 1. 개요

사용자의 활동이 뜸해졌을 때 최근 대화/메모리/칸반 컨텍스트를 분석하여 의미 있는 제안을 자동 표시하는 시스템. 기존 HeartbeatService의 주기적 점검을 확장하여, 유휴 감지 + 컨텍스트 분석 + 제안 생성을 수행한다.

### 핵심 원칙
- **비침투적**: 사용자 작업을 방해하지 않음. 대화 영역 하단에 부드럽게 나타남
- **맥락 기반**: 단순 알림이 아닌, 최근 대화/작업에서 파생된 관련 제안
- **피로 방지**: 하루 최대 횟수 제한, 같은 제안 반복 방지, "이런 제안 그만" 지원
- **리소스 인식**: 남는 토큰이 있을 때 더 풍부한 제안, 없으면 로컬 분석만

---

## 2. 제안 유형 (SuggestionType)

| 유형 | enum case | 아이콘 | 소스 | 예시 |
|------|-----------|--------|------|------|
| 뉴스/트렌드 | `trending` | `globe` | 최근 대화 키워드 + 웹 검색 | "Swift 6.1 관련 소식이 있습니다" |
| 심화 설명 | `deepDive` | `text.book.closed` | 최근 대화 미완료 토픽 | "어제 대화하신 ONNX에 대해 더 설명드릴까요?" |
| 관련 자료 | `research` | `doc.text.magnifyingglass` | 최근 코드/대화 주제 | "RAG 관련 최신 블로그가 있습니다" |
| 칸반 진행 | `kanbanCheck` | `checklist` | 칸반 in-progress 카드 | "'디자인 시스템' 카드, 도움이 필요하신가요?" |
| 메모리 리마인드 | `memoryRemind` | `brain` | memory.md 시간 표현 분석 | "이번 주 안에 확인하겠다고 메모하신 건이 있습니다" |
| 비용 리포트 | `usageReport` | `chart.bar` | UsageStore | "이번 주 AI 사용 요약: Claude 70%, GPT 30%" |

---

## 3. 진입점 (Discoverability)

### 3-1. 대화 영역 — 제안 버블

제안은 **대화 메시지 영역 하단**에 별도의 "제안 버블"로 나타남. 일반 메시지와 구분되는 스타일.

```
┌──────────────────────────────────────────────────────┐
│  대화 메시지들...                                      │
│  ...                                                  │
│                                                       │
│  ┌─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┐   │
│  │ lightbulb.fill  관심있으실 만한 소식             │   │
│  │                                               │   │
│  │ Swift 6.1에서 새로운 concurrency 기능이        │   │
│  │ 발표되었습니다. 최근 프로젝트에서 관련 작업을    │   │
│  │ 하셨는데, 자세히 알아볼까요?                    │   │
│  │                                               │   │
│  │ [조사하기]  [나중에]  [이런 제안 그만]          │   │
│  └─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┘   │
│                                                       │
│  ──────────────────── input bar ────────────────────   │
└──────────────────────────────────────────────────────┘
```

제안 버블 위치: ConversationView 메시지 목록 끝 + InputBarView 사이.
대화에 메시지로 삽입되는 것이 **아닌**, 별도 오버레이 영역.

### 3-2. 설정

| 위치 | 그룹 "일반" → 기존 "하트비트" 아래 |
|------|------|
| 섹션 이름 | 기존 `heartbeat` 섹션에 통합 |
| 파일 | `Views/Settings/HeartbeatSettingsView.swift` (기존 파일에 섹션 추가) |

하트비트 설정과 프로액티브 제안은 동일한 "에이전트가 스스로 행동하는" 범주이므로 기존 하트비트 섹션에 "프로액티브 제안" Section을 추가한다. 별도 설정 섹션을 만들지 않음.

### 3-3. 커맨드 팔레트 (Cmd+K)

| 명령 | action | 동작 |
|------|--------|------|
| "제안 설정" | `.openSettingsSection(section: "heartbeat")` | 하트비트 설정 열기 (제안 섹션) |
| "제안 기록" | `.showSuggestionHistory` | 제안 기록 시트 표시 |

### 3-4. SystemHealthBarView 연동

기존 하트비트 인디케이터에 **제안 대기 상태** 아이콘 추가하지 않음 (복잡도 대비 가치 낮음).
대신 하트비트 상태 시트(SystemStatusSheetView)에 "오늘 제안: N/M건" 요약 1줄 추가.

---

## 4. 화면 상세

### 4-1. SuggestionBubbleView

새 파일: `Views/SuggestionBubbleView.swift`

```
구조:
VStack(alignment: .leading, spacing: 8)
  ├── HStack — 아이콘 + 제목 (13pt semibold)
  ├── Text — 본문 (12pt, secondary color, 최대 3줄)
  └── HStack — 액션 버튼들
       ├── [주 액션] — bordered prominent, controlSize small
       ├── [나중에] — bordered, controlSize small
       └── [이런 제안 그만] — plain, 11pt, secondary
```

스타일 속성:
- 배경: `Color.accentColor.opacity(0.06)` (연한 액센트)
- 테두리: `Color.accentColor.opacity(0.15)`, cornerRadius 10
- 점선 테두리: 일반 메시지 버블과 시각적 차별화
- 패딩: horizontal 14, vertical 10
- 최대 너비: 480pt (대화 영역 중앙 정렬)
- 진입 애니메이션: `opacity(0→1)` + `offset(y: 10→0)`, duration 0.4, easeOut
- 퇴장: "나중에"/"그만" 클릭 시 fade out (0.25초)

아이콘: SuggestionType별 SF Symbol (위 표 참조), 14pt, accentColor

주 액션 버튼 레이블 (SuggestionType별):
| 유형 | 주 액션 텍스트 |
|------|----------------|
| `trending` | "알아보기" |
| `deepDive` | "설명 듣기" |
| `research` | "자료 보기" |
| `kanbanCheck` | "칸반 보기" |
| `memoryRemind` | "확인하기" |
| `usageReport` | "상세 보기" |

### 4-2. 제안 버블 배치 (ConversationView / ContentView)

제안 버블은 ConversationView 하단, InputBarView 바로 위에 배치:

```swift
// ContentView 내 chatDetailView
VStack(spacing: 0) {
    // ... banners
    ConversationView(...)        // 메시지 목록

    // K-2: 프로액티브 제안 버블 (있을 때만 표시)
    if let suggestion = viewModel.currentSuggestion {
        SuggestionBubbleView(
            suggestion: suggestion,
            onAccept: { viewModel.acceptSuggestion(suggestion) },
            onDismiss: { viewModel.dismissSuggestion(suggestion) },
            onMute: { viewModel.muteSuggestionType(suggestion.type) }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    Divider()
    InputBarView(...)            // 입력 바
}
```

### 4-3. 제안 액션 동작

| 버튼 | 동작 |
|------|------|
| 주 액션 ("알아보기" 등) | 제안 내용을 기반으로 자동 프롬프트 생성 → 새 대화로 전송. 제안 버블 소멸 |
| "나중에" | 제안 버블 소멸. 동일 제안은 24시간 후 재시도 가능 |
| "이런 제안 그만" | 해당 SuggestionType을 `proactiveMutedTypes`에 추가. 제안 버블 소멸 |

주 액션 시 자동 생성되는 프롬프트 예시:
- `trending`: "최근 {keyword} 관련 뉴스와 트렌드를 조사해줘"
- `deepDive`: "{topic}에 대해 더 자세히 설명해줘"
- `kanbanCheck`: "칸반 보드에서 진행 중인 '{cardTitle}' 카드 상태를 확인하고 도움이 필요한지 알려줘"

### 4-4. 설정 UI (HeartbeatSettingsView 확장)

기존 HeartbeatSettingsView에 새 Section 추가:

```
Section("프로액티브 제안") {
    Toggle: "프로액티브 제안 활성화" — proactiveSuggestionsEnabled (기본 true)

    if enabled:
        HStack: "유휴 감지 시간" + Stepper (10~120분, 기본 30분)
        HStack: "하루 최대 제안 수" + Stepper (1~20, 기본 5)

        제안 유형 토글 목록:
            Toggle: "뉴스/트렌드 조사" — proactiveSuggestionTypes contains .trending
            Toggle: "심화 설명 제안" — .deepDive
            Toggle: "관련 자료 조사" — .research
            Toggle: "칸반 진행 체크" — .kanbanCheck
            Toggle: "메모리 리마인드" — .memoryRemind
            Toggle: "비용 리포트" — .usageReport

        Text: "음소거한 유형은 여기서 다시 활성화할 수 있습니다."
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

        HStack: "리소스 연동" + Toggle
            proactiveUseResourceBudget (기본 true)
        Text: "활성화 시 남는 토큰이 있을 때 웹 검색 등 풍부한 제안을 생성합니다."
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
}
```

### 4-5. 제안 기록 (SuggestionHistoryView)

시트로 표시. 파일: `Views/SuggestionHistoryView.swift`

```
구조:
VStack
  ├── 헤더: "제안 기록" + 닫기 버튼
  ├── 오늘 제안 요약: "오늘 N건 제안 (M건 수락)"
  └── List (최근 50건)
       └── 각 행: HStack
            ├── 아이콘 (SuggestionType)
            ├── VStack: 제목 + 시각 (relative date)
            └── 상태 배지: 수락/나중에/음소거
```

시트 크기: 400x480pt

### 4-6. 상태별 처리

#### 빈 상태 (Empty State)

**제안 없음 (정상)**: 제안이 없을 때 SuggestionBubbleView는 아예 렌더링하지 않음. 별도의 "제안 없음" UI는 표시하지 않는다 — 프로액티브 기능이므로 빈 상태를 사용자에게 알릴 필요 없음.

**제안 기록 없음 (SuggestionHistoryView)**:
```
VStack(spacing: 12)
  Image(systemName: "lightbulb")
    .font(.system(size: 28))
    .foregroundStyle(.tertiary)
  Text("아직 제안 기록이 없습니다")
    .font(.system(size: 13))
    .foregroundStyle(.secondary)
  Text("유휴 시간이 지나면 자동으로 제안이 생성됩니다")
    .font(.system(size: 11))
    .foregroundStyle(.tertiary)
```

**설정에서 비활성화됨**: `proactiveSuggestionsEnabled = false`이면 설정 UI에서 하위 항목이 모두 숨겨지고 (if enabled 패턴), 서비스는 유휴 감지를 중단한다. 별도 배너 불필요.

**모든 유형 음소거됨**: 활성화된 유형이 0개이면 제안이 생성되지 않음. 설정 UI에서 유형 토글 하단에 경고 표시:
```
Text("모든 제안 유형이 비활성화되어 있습니다.")
  .font(.system(size: 11))
  .foregroundStyle(.orange)
```

#### 로딩 상태 (Loading State)

LLM 기반 제안 생성(trending, research 등) 시 시간이 걸릴 수 있음:
- 제안 생성은 **백그라운드**에서 수행. 생성 완료 전까지 UI에 아무것도 표시하지 않음
- 제안 버블은 완성된 제안만 표시 — 로딩 스피너나 스켈레톤 UI 없음
- 이유: 프로액티브 기능이므로 "지금 생성 중" 상태를 사용자에게 보여줄 필요 없음. 기다리게 하는 것이 아니라 준비되면 조용히 나타나는 것

#### 에러 상태 (Error State)

**LLM API 실패**: 제안 생성 중 API 오류 발생 시 해당 제안은 폐기. 에러 토스트/배너를 표시하지 않음 — 사용자가 요청한 것이 아니므로 실패를 알릴 필요 없음. `Log.app.warning`으로 로깅만 수행.

**컨텍스트 수집 실패**: ContextService/UsageStore 접근 실패 시 해당 소스 건너뛰고 나머지로 제안 시도. 모든 소스 실패 시 제안 미생성.

**오프라인 상태**: 웹 검색이 필요한 유형(trending, research)은 건너뛰고 로컬 분석 유형(kanbanCheck, memoryRemind, usageReport)만 후보로 사용.

---

## 5. 데이터 모델

### ProactiveSuggestion

새 파일: `Models/ProactiveSuggestionModels.swift`

```swift
enum SuggestionType: String, Codable, Sendable, CaseIterable {
    case trending
    case deepDive
    case research
    case kanbanCheck
    case memoryRemind
    case usageReport
}

struct ProactiveSuggestion: Identifiable, Sendable {
    let id: UUID
    let type: SuggestionType
    let title: String           // 제안 제목 (1줄)
    let body: String            // 제안 본문 (최대 3줄)
    let prompt: String          // 수락 시 전송할 프롬프트
    let sourceContext: String   // 제안 생성에 사용된 컨텍스트 요약
    let createdAt: Date
    var status: SuggestionStatus
}

enum SuggestionStatus: String, Codable, Sendable {
    case pending        // 아직 표시 전
    case shown          // 표시 중
    case accepted       // 사용자가 수락
    case dismissed      // "나중에"
    case muted          // "이런 제안 그만"
}
```

### SuggestionRecord (기록용, Codable)

```swift
struct SuggestionRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let type: SuggestionType
    let title: String
    let status: SuggestionStatus
    let createdAt: Date
    let resolvedAt: Date?
}
```

---

## 6. 서비스 구조

### ProactiveSuggestionService

새 파일: `Services/ProactiveSuggestionService.swift`

```swift
@MainActor
@Observable
final class ProactiveSuggestionService {
    // State
    private(set) var currentSuggestion: ProactiveSuggestion?
    private(set) var todaySuggestionCount: Int = 0
    private(set) var history: [SuggestionRecord] = []

    // Dependencies
    private let settings: AppSettings
    private var contextService: ContextServiceProtocol?
    private var resourceOptimizer: (any ResourceOptimizerProtocol)?

    // Idle detection
    private var lastActivityDate: Date = Date()
    private var idleCheckTask: Task<Void, Never>?
}
```

프로토콜: `ProactiveSuggestionServiceProtocol` (새 파일: `Services/Protocols/ProactiveSuggestionServiceProtocol.swift`)

```swift
@MainActor
protocol ProactiveSuggestionServiceProtocol: AnyObject {
    var currentSuggestion: ProactiveSuggestion? { get }
    var todaySuggestionCount: Int { get }
    var history: [SuggestionRecord] { get }

    func recordActivity()
    func acceptSuggestion(_ suggestion: ProactiveSuggestion)
    func dismissSuggestion(_ suggestion: ProactiveSuggestion)
    func muteSuggestionType(_ type: SuggestionType)
    func start()
    func stop()
}
```

### 유휴 감지 흐름

```
1. recordActivity() — 사용자 입력/클릭 시마다 호출 (InputBarView, ContentView onKeyPress 등)
     → lastActivityDate = Date()

2. idleCheckTask (30초 주기 반복):
     → elapsed = Date() - lastActivityDate
     → if elapsed >= proactiveIdleMinutes * 60:
         → if todaySuggestionCount < proactiveMaxSuggestionsPerDay:
             → generateSuggestion()
             → 다음 체크까지 대기 (제안 생성 후 쿨다운: 유휴 시간 / 2)
```

### 제안 생성 흐름 (generateSuggestion)

```
1. 활성화 확인: settings.proactiveSuggestionsEnabled
2. 방해 금지 확인: HeartbeatService 방해 금지 시간 재사용
3. 컨텍스트 수집:
   a. 최근 3개 대화에서 키워드/토픽 추출
   b. 칸반 in-progress 카드 조회
   c. memory.md에서 시간 표현 ("이번 주", "내일까지" 등) 탐색
   d. UsageStore에서 이번 주 사용량 조회
4. 후보 생성: 각 SuggestionType별로 1개 후보 (활성화된 유형만)
5. 중복 필터: 최근 24시간 내 동일 title 제안 제거
6. 리소스 판단:
   a. proactiveUseResourceBudget && 남는 토큰 있음 → LLM 요약 포함 (trending, research)
   b. 남는 토큰 없음 → 로컬 분석만 (kanbanCheck, memoryRemind, usageReport)
7. 최종 1개 선택 (우선순위: memoryRemind > kanbanCheck > trending > deepDive > research > usageReport)
8. currentSuggestion = 선택된 제안
```

---

## 7. ViewModel 연동

DochiViewModel에 추가할 속성/메서드:

```swift
// MARK: - Proactive Suggestions (K-2)
private(set) var proactiveSuggestionService: ProactiveSuggestionServiceProtocol?

var currentSuggestion: ProactiveSuggestion? {
    proactiveSuggestionService?.currentSuggestion
}

func configureProactiveSuggestionService(_ service: ProactiveSuggestionServiceProtocol) {
    self.proactiveSuggestionService = service
}

func recordUserActivity() {
    proactiveSuggestionService?.recordActivity()
}

func acceptSuggestion(_ suggestion: ProactiveSuggestion) {
    proactiveSuggestionService?.acceptSuggestion(suggestion)
    // 프롬프트를 현재 대화에 전송
    inputText = suggestion.prompt
    sendMessage()
}

func dismissSuggestion(_ suggestion: ProactiveSuggestion) {
    proactiveSuggestionService?.dismissSuggestion(suggestion)
}

func muteSuggestionType(_ type: SuggestionType) {
    proactiveSuggestionService?.muteSuggestionType(type)
}
```

### 활동 기록 위치

`recordUserActivity()` 호출 시점:
- `InputBarView`: `onSubmit` (메시지 전송 시)
- `ContentView`: `onKeyPress` (키 입력 시)
- `SidebarView`: 대화 선택 시
- `KanbanWorkspaceView`: 카드 조작 시

---

## 8. AppSettings 확장

```swift
// MARK: - Proactive Suggestions (K-2)

var proactiveSuggestionsEnabled: Bool      // 기본 true
var proactiveIdleMinutes: Int              // 기본 30 (범위 10~120)
var proactiveMaxSuggestionsPerDay: Int     // 기본 5 (범위 1~20)
var proactiveSuggestionTypes: [String]     // 기본 SuggestionType.allCases.map(\.rawValue)
var proactiveMutedTypes: [String]          // 기본 [] — "이런 제안 그만"으로 추가됨
var proactiveUseResourceBudget: Bool       // 기본 true
```

---

## 9. 키보드 단축키

없음. 제안 버블은 마우스/트랙패드로 조작. 제안이 표시되었을 때 Escape로 "나중에" 동작은 **추가하지 않음** (대화 입력 중 Escape와 충돌 가능성).

---

## 10. 커맨드 팔레트 추가

```swift
CommandPaletteItem(
    id: "suggestion-history",
    icon: "lightbulb",
    title: "제안 기록",
    subtitle: "",
    category: .navigation,
    action: .showSuggestionHistory
)
```

CommandPaletteItem.Action에 `.showSuggestionHistory` case 추가.

---

## 11. HeartbeatService와의 관계

**분리 유지**. HeartbeatService는 알림 기반(캘린더/칸반/미리알림 주기 점검), ProactiveSuggestionService는 유휴 기반(컨텍스트 분석 후 인앱 제안). 서로 다른 트리거와 출력 채널을 가진다.

공유하는 것:
- `settings.heartbeatQuietHoursStart/End`: 방해 금지 시간 로직 재사용
- ContextService: 메모리/대화 데이터 접근

공유하지 않는 것:
- 타이밍: HeartbeatService는 고정 주기, ProactiveSuggestionService는 유휴 감지
- 출력: HeartbeatService → macOS 알림, ProactiveSuggestionService → 인앱 제안 버블

---

## 12. 파일 목록

| 구분 | 파일 | 설명 |
|------|------|------|
| 신규 | `Models/ProactiveSuggestionModels.swift` | SuggestionType, ProactiveSuggestion, SuggestionStatus, SuggestionRecord |
| 신규 | `Services/Protocols/ProactiveSuggestionServiceProtocol.swift` | 프로토콜 |
| 신규 | `Services/ProactiveSuggestionService.swift` | 유휴 감지, 컨텍스트 분석, 제안 생성 |
| 신규 | `Views/SuggestionBubbleView.swift` | 제안 버블 UI |
| 신규 | `Views/SuggestionHistoryView.swift` | 제안 기록 시트 |
| 수정 | `Models/AppSettings.swift` | proactive* 설정 추가 |
| 수정 | `Models/CommandPaletteItem.swift` | `.showSuggestionHistory` action 추가 |
| 수정 | `ViewModels/DochiViewModel.swift` | ProactiveSuggestionService 연동 |
| 수정 | `Views/ContentView.swift` | SuggestionBubbleView 배치, recordUserActivity 호출 |
| 수정 | `Views/Settings/HeartbeatSettingsView.swift` | 프로액티브 제안 Section 추가 |
| 수정 | `App/DochiApp.swift` | ProactiveSuggestionService 생성 + DI |
| 신규 | `DochiTests/Mocks/MockServices.swift` | MockProactiveSuggestionService 추가 |
| 신규 | `DochiTests/ProactiveSuggestionTests.swift` | 유닛 테스트 |

---

## 13. 테스트 계획

| 테스트 | 검증 항목 |
|--------|-----------|
| `testIdleDetection` | recordActivity 후 유휴 시간 경과 → 제안 생성 |
| `testMaxDailySuggestions` | 하루 최대 횟수 초과 시 제안 미생성 |
| `testDuplicateFilter` | 24시간 내 동일 제안 제거 |
| `testMutedTypeFilter` | 음소거된 유형 제안 미생성 |
| `testDisabledSetting` | proactiveSuggestionsEnabled = false → 미동작 |
| `testQuietHours` | 방해 금지 시간 → 미생성 |
| `testAcceptSuggestion` | 수락 → status 변경, 기록 추가 |
| `testDismissSuggestion` | "나중에" → status 변경, 24시간 쿨다운 |
| `testMuteSuggestionType` | "그만" → 설정에 유형 추가 |
| `testSuggestionPriority` | memoryRemind > kanbanCheck > trending 순서 |
| `testResourceBudgetIntegration` | 토큰 여유 시 LLM 제안, 부족 시 로컬만 |

---

## 14. UI 인벤토리 업데이트 (머지 시 반영)

### 앱 구조 트리에 추가

```
│   │   ├── SuggestionBubbleView — 프로액티브 제안 버블 (유휴 감지 시 자동 표시, 3 액션) (K-2)
```

위치: ConversationView와 InputBarView 사이

### 모든 화면 목록에 추가

| 화면 | 파일 | 접근 방법 | 설명 |
|------|------|-----------|------|
| SuggestionBubbleView | `Views/SuggestionBubbleView.swift` | 유휴 감지 시 자동 | 프로액티브 제안 버블: 아이콘+제목+본문+3액션 (K-2) |
| SuggestionHistoryView | `Views/SuggestionHistoryView.swift` | 커맨드 팔레트 "제안 기록" | 제안 기록 시트: 오늘 요약 + 최근 50건 리스트 (K-2) |

### DochiViewModel 속성 추가

| 속성 | 타입 | 설명 | 사용처 |
|------|------|------|--------|
| `proactiveSuggestionService` | `ProactiveSuggestionServiceProtocol?` | 프로액티브 제안 서비스 (K-2) | SuggestionBubbleView |
| `currentSuggestion` | `ProactiveSuggestion?` | 현재 표시 중인 제안 (K-2) | ContentView |

### AppSettings 추가

| 기능 | 키 |
|------|-----|
| 프로액티브 제안 (K-2) | `proactiveSuggestionsEnabled`, `proactiveIdleMinutes`, `proactiveMaxSuggestionsPerDay`, `proactiveSuggestionTypes`, `proactiveMutedTypes`, `proactiveUseResourceBudget` |

### 컴포넌트 스타일 패턴 추가

| 패턴 | 사용처 | 설명 |
|------|--------|------|
| 제안 버블 (VStack + 점선 테두리 + 액센트 배경) | SuggestionBubbleView | 대화 하단 비침투적 제안 카드, 3 액션 버튼, fade 애니메이션 (K-2) |

### 플로우 추가

```
프로액티브 제안 (K-2 추가)
사용자 유휴 감지: recordUserActivity() 호출 중단 → 30분 경과
  → ProactiveSuggestionService.generateSuggestion()
  → 컨텍스트 분석 (대화/칸반/메모리/사용량)
  → currentSuggestion 설정 → SuggestionBubbleView 표시
수락: "알아보기" → suggestion.prompt → 새 대화로 전송 → 버블 소멸
나중에: "나중에" → 24시간 쿨다운 → 버블 소멸
음소거: "이런 제안 그만" → proactiveMutedTypes에 유형 추가 → 버블 소멸
설정: 설정 > 하트비트 > 프로액티브 제안 섹션
AppSettings: proactiveSuggestionsEnabled, proactiveIdleMinutes, proactiveMaxSuggestionsPerDay,
  proactiveSuggestionTypes, proactiveMutedTypes, proactiveUseResourceBudget
```
