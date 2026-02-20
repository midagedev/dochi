# UX 명세: [K-3] 사용자 관심사 발굴 시스템

> 상태: 설계 완료
> 관련: ContextService, MemoryConsolidator, HeartbeatService, ProactiveSuggestionService, ConversationView
> 이슈: #166

---

## 1. 개요

사용자의 개인 컨텍스트가 부족할수록 더 적극적으로 관심사를 발굴하는 시스템. 대화 중 관심사 힌트를 감지하고, 유휴 시 인접 관심사를 탐색하며, memory.md에 구조화된 관심사 섹션을 자동 관리한다.

### 핵심 원칙
- **컨텍스트 반비례 적극성**: 아는 것이 적을수록 적극 발굴, 충분하면 수동 전환
- **자연스러운 대화 삽입**: 발굴 질문은 대화 흐름에 녹아들어야 함. 별도 팝업이 아닌 대화 메시지로 등장
- **사용자 통제**: 추정된 관심사를 확인/삭제/편집 가능. 발굴 빈도 조절 가능
- **memory.md 연동**: 발굴된 관심사는 memory.md "## 관심사" 섹션에 자동 기록, MemoryConsolidator와 호환

---

## 2. 관심사 모델 (InterestEntry)

| 필드 | 타입 | 설명 |
|------|------|------|
| id | UUID | 고유 식별자 |
| topic | String | 관심사 주제 (예: "Swift/SwiftUI", "Rust", "시스템 디자인") |
| status | InterestStatus | `.confirmed`, `.inferred`, `.expired` |
| confidence | Double | 0.0~1.0, 추정 신뢰도 |
| source | String | 발견 소스 (예: "conversation:uuid", "onboarding", "proactive") |
| firstSeen | Date | 최초 감지 일시 |
| lastSeen | Date | 마지막 관련 대화 일시 |
| tags | [String] | 하위 분류 (예: ["macOS", "앱 개발", "SwiftUI"]) |

### InterestStatus

| 상태 | 의미 | 전환 조건 |
|------|------|-----------|
| `.confirmed` | 사용자가 직접 언급하거나 동의 | 온보딩 답변, 설정에서 "확인" 버튼, 대화 중 명시적 언급 |
| `.inferred` | 대화 패턴에서 자동 추출 | 키워드 3회+ 등장, 감정 신호 감지 |
| `.expired` | 30일 이상 관련 대화 없음 | lastSeen 기준 자동 격하 |

---

## 3. 적극성 레벨 (DiscoveryAggressiveness)

| 레벨 | 확인된 관심사 | 동작 |
|------|-------------|------|
| `.eager` (Cold) | 0~2개 | 대화 시작 시 관심사 질문, 매 대화에서 힌트 탐색 |
| `.active` (Warm) | 3~5개 | 새 주제 감지 시 파고들기, 유휴 시 인접 관심사 탐색 |
| `.passive` (Hot) | 6개+ | 유휴 시에만 제안, 사용자 요청 시 심화 |
| `.manual` | 무관 | 사용자 설정으로 강제 수동 모드 |

적극성 레벨은 confirmed 관심사 수에서 자동 결정되나, 사용자가 설정에서 `.manual`로 오버라이드 가능.

---

## 4. 진입점 (Discoverability)

### 4-1. 대화 내 발굴 질문

발굴 질문은 **일반 assistant 메시지**로 대화에 삽입됨. 별도 버블/오버레이가 아니라, 도치의 일반 응답처럼 보이되 시스템이 자동으로 트리거한 것임.

LLM 호출 시 시스템 프롬프트에 관심사 발굴 지시를 추가하는 방식으로 구현. 별도 UI 컴포넌트 없음.

**Cold Start (온보딩)**:
- 첫 실행 또는 confirmed 관심사 0~2개일 때
- 사용자가 첫 메시지를 보내면, LLM 시스템 프롬프트에 "사용자의 관심사/직업/주 사용 도구를 자연스럽게 파악하라" 지시 추가
- LLM이 응답에 자연스럽게 관심사 질문을 포함

**Warm State (대화 중 감지)**:
- 키워드 매칭으로 새 관심사 힌트 감지 시
- 다음 LLM 호출의 시스템 프롬프트에 "사용자가 {topic}에 관심을 보임, 자연스럽게 구체적인 관심 분야를 파악하라" 지시 추가

**Proactive Discovery (유휴 시)**:
- K-2 ProactiveSuggestionService의 새 SuggestionType으로 추가
- 기존 관심사 기반 인접 관심사 탐색 제안 생성

### 4-2. 설정

| 위치 | 그룹 "사람" → 새 섹션 "관심사" |
|------|------|
| SettingsSection | `.interest` (신규) |
| 그룹 | `.people` (family, agent와 함께) |
| 파일 | `Views/Settings/InterestSettingsView.swift` (신규) |

"사람" 그룹에 배치하는 이유: 관심사는 **사용자 프로필**의 일부이며, 가족 구성원/에이전트와 같은 "사람에 대한 정보" 범주.

### 4-3. 커맨드 팔레트 (Cmd+K)

| 명령 | ID | 동작 |
|------|-----|------|
| "관심사 설정" | `settings.open.interest` | 관심사 설정 열기 |
| "관심사 목록" | `interest.list` | 관심사 설정의 목록 섹션으로 스크롤 |

### 4-4. 시스템 프롬프트 연동

발굴된 관심사는 시스템 프롬프트에 자동 반영:
```
## 사용자 관심사
- [확인됨] Swift/SwiftUI macOS 앱 개발
- [확인됨] AI/LLM 활용
- [추정] Rust (신뢰도 0.7)
```

---

## 5. 화면 상세

### 5-1. InterestSettingsView

새 파일: `Views/Settings/InterestSettingsView.swift`

```
┌─────────────────────────────────────────────────────────────┐
│  [Form]                                                      │
│                                                              │
│  ── 관심사 발굴 ──────────────────────────────────────────    │
│  (i) 대화를 통해 사용자의 관심사를 파악하여 맞춤 도움을       │
│      제공합니다.                                              │
│                                                              │
│  [Toggle] 관심사 발굴 활성화                                  │
│                                                              │
│  적극성 모드:                                                 │
│  [Picker: 자동 / 적극 / 수동]                                 │
│  (caption) 자동: 관심사 수에 따라 적극성이 자동 조절됩니다     │
│  현재 적극성: ● 적극 (확인 2개)                               │
│                                                              │
│  ── 수집된 관심사 ────────────────────────────────────────    │
│                                                              │
│  ┌─ ● Swift/SwiftUI macOS 앱 개발 ──── [확인됨] ────────┐    │
│  │  태그: macOS, 앱 개발, SwiftUI                        │    │
│  │  소스: 온보딩 | 최초: 2024-02-01 | 최근: 2024-02-15   │    │
│  │                               [편집] [삭제]          │    │
│  └───────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─ ○ Rust ──────────────────────── [추정 70%] ──────────┐   │
│  │  태그: 시스템 프로그래밍                                │   │
│  │  소스: 대화 | 최초: 2024-02-15 | 최근: 2024-02-15     │   │
│  │                     [확인으로 승격] [편집] [삭제]      │   │
│  └───────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─ ◇ 시스템 디자인 ───────────── [만료] ────────────────┐   │
│  │  태그: 아키텍처                                        │   │
│  │  소스: 대화 | 최초: 2024-01-01 | 최근: 2024-01-10     │   │
│  │                     [복원] [삭제]                      │   │
│  └───────────────────────────────────────────────────────┘    │
│                                                              │
│  [+ 관심사 직접 추가]                                         │
│                                                              │
│  ── 고급 ─────────────────────────────────────────────────   │
│  만료 기간: [30]일 (Slider 7~90)                              │
│  최소 감지 횟수: [3]회 (Slider 2~10)                          │
│  (caption) 키워드가 이 횟수 이상 등장하면 추정 관심사로 등록   │
│                                                              │
│  [Toggle] 시스템 프롬프트에 관심사 포함                        │
│  (caption) 비활성화하면 관심사가 AI 응답에 반영되지 않습니다   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5-2. 관심사 항목 카드 (InterestEntryCardView)

각 관심사는 카드 형태로 표시. 상태별 스타일:

| 상태 | 아이콘 | 배지 색상 | 배지 텍스트 |
|------|--------|-----------|-------------|
| confirmed | ● (circle.fill) | green | "확인됨" |
| inferred | ○ (circle) | orange | "추정 {confidence}%" |
| expired | ◇ (diamond) | gray | "만료" |

카드 내 액션:
- **확인으로 승격** (inferred만): 해당 관심사를 `.confirmed`로 변경
- **복원** (expired만): `.confirmed`로 복원, lastSeen 갱신
- **편집**: topic, tags 인라인 편집
- **삭제**: 확인 없이 즉시 삭제 (실수 방지보다 조작 편의성 우선 — 다시 추가 쉬움)

### 5-3. 관심사 직접 추가 시트

"+ 관심사 직접 추가" 버튼 클릭 시 인라인 폼 표시:

```
┌───────────────────────────────────────────┐
│  주제: [TextField "예: Python 데이터 분석"]│
│  태그: [TextField "예: 데이터, 머신러닝"]  │
│           [취소]  [추가]                   │
└───────────────────────────────────────────┘
```

추가 시 status = `.confirmed`, confidence = 1.0, source = "manual".

---

## 6. 빈 상태 / 에러 상태 / 로딩 상태

### 빈 상태
- **관심사 목록 비어있음**: 설정 뷰의 "수집된 관심사" 섹션에 빈 상태 텍스트 표시
  ```
  아직 수집된 관심사가 없습니다.
  대화를 통해 자동으로 관심사가 수집되거나,
  아래에서 직접 추가할 수 있습니다.
  ```
  폰트: `.caption`, 색상: `.secondary`

### 에러 상태
- **memory.md 파싱 실패**: `Log.storage.error`로 기록, 관심사 목록은 빈 상태로 표시. 기존 memory.md 내용 훼손하지 않음
- **LLM 호출 실패** (발굴 질문 생성): 무시하고 일반 대화 진행. 사용자에게 에러 표시하지 않음

### 로딩 상태
- 관심사 데이터는 memory.md에서 로드하므로 거의 즉시 완료. 별도 로딩 인디케이터 불필요
- 시스템 프롬프트에 관심사 섹션 추가도 동기적 처리

---

## 7. 키보드 단축키

별도 단축키 없음. 관심사 설정은 Cmd+K → "관심사" 검색으로 접근 가능.

---

## 8. 데이터 모델

### InterestEntry (Codable, Identifiable, Sendable)

```swift
struct InterestEntry: Identifiable, Codable, Sendable {
    let id: UUID
    var topic: String
    var status: InterestStatus
    var confidence: Double      // 0.0~1.0
    var source: String          // "onboarding", "conversation:{id}", "manual", "proactive"
    var firstSeen: Date
    var lastSeen: Date
    var tags: [String]
}

enum InterestStatus: String, Codable, Sendable {
    case confirmed
    case inferred
    case expired
}
```

### InterestProfile (메모리 내 관심사 컬렉션)

```swift
struct InterestProfile: Codable, Sendable {
    var interests: [InterestEntry]
    var lastDiscoveryDate: Date?
    var discoveryMode: DiscoveryMode  // .auto, .eager, .passive, .manual
}

enum DiscoveryMode: String, Codable, Sendable, CaseIterable {
    case auto     // 관심사 수에 따라 자동 결정
    case eager    // 항상 적극
    case passive  // 항상 수동
    case manual   // 발굴 비활성, 수동 추가만
}
```

### 저장 위치

InterestProfile은 별도 JSON 파일로 저장:
```
~/Library/Application Support/Dochi/interests/{userId}.json
```

memory.md와 별도로 저장하는 이유:
- 구조화된 데이터(JSON)와 자유 형식 텍스트(memory.md)를 분리
- InterestProfile은 앱이 프로그래밍적으로 관리하는 데이터
- memory.md의 "## 관심사" 섹션은 InterestProfile에서 **생성**되는 뷰 (읽기 전용 렌더링)

### memory.md 연동

InterestDiscoveryService가 관심사 변경 시 memory.md의 "## 관심사" 섹션을 자동 갱신:
```markdown
## 관심사
- [확인됨] Swift/SwiftUI macOS 앱 개발 (2024-02 ~)
- [확인됨] AI/LLM 활용 (2024-01 ~)
- [추정] Rust (신뢰도 70%, 2024-02-15 대화에서 언급)
```

이 섹션은 시스템 프롬프트 구성 시 참조됨.

---

## 9. 서비스 구조

### InterestDiscoveryService

새 파일: `Services/Context/InterestDiscoveryService.swift`

```swift
@MainActor
protocol InterestDiscoveryServiceProtocol {
    var profile: InterestProfile { get }
    var currentAggressiveness: DiscoveryAggressiveness { get }

    func loadProfile(userId: String)
    func saveProfile(userId: String)

    // 관심사 CRUD
    func addInterest(_ entry: InterestEntry)
    func updateInterest(id: UUID, topic: String?, tags: [String]?)
    func confirmInterest(id: UUID)
    func restoreInterest(id: UUID)
    func removeInterest(id: UUID)

    // 대화 분석
    func analyzeMessage(_ content: String, conversationId: UUID)
    func buildDiscoverySystemPromptAddition() -> String?

    // 만료 체크
    func checkExpirations()

    // memory.md 동기화
    func syncToMemory(contextService: ContextServiceProtocol, userId: String)
}
```

### DiscoveryAggressiveness (계산 프로퍼티)

```swift
enum DiscoveryAggressiveness: Sendable {
    case eager    // 0~2 confirmed
    case active   // 3~5 confirmed
    case passive  // 6+ confirmed
}
```

`currentAggressiveness`는 `profile.discoveryMode`가 `.auto`이면 confirmed 수로 계산, 그 외는 모드에 직접 매핑.

### 대화 분석 흐름

1. 사용자 메시지가 `DochiViewModel`에 도착
2. `InterestDiscoveryService.analyzeMessage()` 호출
3. 키워드 매칭 + 빈도 카운트로 새 관심사 힌트 감지
4. 감지된 힌트가 임계값(`minDetectionCount`) 이상이면 `.inferred` 관심사 등록
5. 다음 LLM 호출 시 `buildDiscoverySystemPromptAddition()`이 적극성 레벨에 따라 발굴 지시 반환
6. LLM 응답에 자연스럽게 발굴 질문이 포함됨

### 감지 트리거 키워드 패턴

```swift
// 관심 신호 키워드
let interestSignals = ["관심", "궁금", "배워", "해볼까", "좋아", "재미"]

// 감정 신호 + 주제 조합
let emotionSignals = ["재미있", "어렵", "좋다", "신기하"]

// 새 기술/도구 패턴
let techPatterns = ["~를 써볼까", "~에 대해", "~해보고 싶"]
```

---

## 10. ViewModel 연동

### DochiViewModel 추가 사항

```swift
// 프로퍼티
var interestDiscoveryService: InterestDiscoveryServiceProtocol?

// 메시지 전송 시
func sendMessage() {
    // ... 기존 로직 ...
    interestDiscoveryService?.analyzeMessage(text, conversationId: currentConversationId)
}

// 시스템 프롬프트 구성 시
func buildSystemPrompt() -> String {
    // ... 기존 로직 ...
    if let addition = interestDiscoveryService?.buildDiscoverySystemPromptAddition() {
        systemPrompt += "\n\n" + addition
    }
}
```

---

## 11. AppSettings 추가

```swift
// 관심사 발굴 활성화
var interestDiscoveryEnabled: Bool    // default: true
// 발굴 모드 (auto/eager/passive/manual)
var interestDiscoveryMode: String     // default: "auto"
// 만료 기간 (일)
var interestExpirationDays: Int       // default: 30
// 최소 감지 횟수
var interestMinDetectionCount: Int    // default: 3
// 시스템 프롬프트에 관심사 포함
var interestIncludeInPrompt: Bool     // default: true
```

---

## 12. SettingsSection 추가

```swift
case interest = "interest"

// title: "관심사"
// icon: "sparkle.magnifyingglass"
// group: .people
// searchKeywords: ["관심사", "관심", "interest", "발굴", "discovery", "프로필", "profile", "주제", "topic", "추정", "확인", "만료"]
```

---

## 13. 커맨드 팔레트 항목

| ID | title | category | action |
|----|-------|----------|--------|
| `settings.open.interest` | "관심사 설정 열기" | .settings | `.openSettingsSection(section: "interest")` |
| `interest.list` | "관심사 목록 보기" | .settings | `.openSettingsSection(section: "interest")` |

---

## 14. ProactiveSuggestionService 연동

K-2 ProactiveSuggestionService에 새 SuggestionType 추가는 **이 이슈 범위에 포함하지 않음**. 대신:

- InterestDiscoveryService의 `buildDiscoverySystemPromptAddition()`이 적극성에 따라 LLM에 발굴 질문 생성 지시
- K-2의 기존 `newsTrend`, `deepDive`, `relatedResearch` 등이 이미 관심사 기반 제안과 유사한 역할 수행
- 향후 K-2에서 InterestProfile을 참조하여 더 정밀한 제안 생성 가능 (별도 이슈)

---

## 15. HeartbeatService 연동

HeartbeatService의 주기적 tick에서 `InterestDiscoveryService.checkExpirations()` 호출하여 만료 체크 수행. 별도 타이머 불필요.

---

## 16. 기존 시스템 연동

| 시스템 | 연동 방법 |
|--------|----------|
| ContextService | memory.md "## 관심사" 섹션 읽기/쓰기 |
| MemoryConsolidator (I-2) | 관심사 섹션을 인식하고 정리 시 보존 |
| HeartbeatService | tick에서 만료 체크 트리거 |
| ProactiveSuggestionService (K-2) | 향후 InterestProfile 참조 (별도 이슈) |
| 시스템 프롬프트 | buildDiscoverySystemPromptAddition() 반영 |

---

## 17. 파일 목록

| 파일 | 상태 | 설명 |
|------|------|------|
| `Dochi/Models/InterestModels.swift` | 신규 | InterestEntry, InterestStatus, InterestProfile, DiscoveryMode, DiscoveryAggressiveness |
| `Dochi/Services/Context/InterestDiscoveryService.swift` | 신규 | 핵심 서비스 (프로토콜 + 구현) |
| `Dochi/Views/Settings/InterestSettingsView.swift` | 신규 | 관심사 설정 뷰 |
| `Dochi/Views/Settings/SettingsSidebarView.swift` | 수정 | `.interest` 섹션 추가, `.people` 그룹에 배치 |
| `Dochi/Views/SettingsView.swift` | 수정 | InterestSettingsView 라우팅 추가 |
| `Dochi/Models/AppSettings.swift` | 수정 | 5개 설정 추가 |
| `Dochi/Models/CommandPaletteItem.swift` | 수정 | 2개 팔레트 항목 추가 |
| `Dochi/ViewModels/DochiViewModel.swift` | 수정 | InterestDiscoveryService 연동 |
| `Dochi/App/DochiApp.swift` | 수정 | 서비스 생성 및 DI |
| `DochiTests/InterestDiscoveryTests.swift` | 신규 | 모델, 서비스, 분석, 만료 테스트 |
| `DochiTests/Mocks/MockServices.swift` | 수정 | MockInterestDiscoveryService 추가 |
| `spec/ui-inventory.md` | 수정 | K-3 항목 추가 |

---

## 18. 테스트 계획

| 테스트 | 커버리지 |
|--------|----------|
| InterestEntry Codable roundtrip | 모델 직렬화/역직렬화 |
| InterestStatus 전환 | confirmed → expired, inferred → confirmed |
| DiscoveryAggressiveness 계산 | confirmed 0/3/6개일 때 레벨 |
| analyzeMessage 키워드 감지 | 관심 신호 키워드 매칭 |
| 중복 관심사 방지 | 같은 토픽 재등록 시 lastSeen만 갱신 |
| checkExpirations | 30일 이상 미활동 시 expired 전환 |
| addInterest/removeInterest | CRUD 정상 동작 |
| confirmInterest/restoreInterest | 상태 전환 |
| buildDiscoverySystemPromptAddition | 적극성별 프롬프트 생성 |
| memory.md 동기화 | syncToMemory가 올바른 마크다운 생성 |
| 빈 프로필 시 빈 상태 | profile.interests 비어있을 때 |
| SettingsSection count | 기존 22 → 23개 확인 |
| SettingsSectionGroup people | family, agent, interest 포함 |
