# UX-9: 온보딩 2.0 — 기능 투어 & 단계별 가이드

> 상태: UX 설계 완료 / 구현 대기
> 관련 이슈: #137
> 의존: 현재 온보딩(OnboardingView.swift), EmptyConversationView, CapabilityCatalogView

---

## 1. 설계 목표

현재 온보딩은 API 키 입력과 프로필 설정만 다루며, 사용자는 도치의 풍부한 기능(35개 도구, 칸반, 에이전트, 워크스페이스, 메모리 등)을 스스로 발견해야 한다. 이 UX는 세 가지 계층으로 발견성을 높인다:

| 계층 | 언제 | 무엇을 |
|------|------|--------|
| A. 온보딩 확장 | 최초 설정 직후 (1회) | 선택적 기능 투어 |
| B. 인앱 힌트 | 기능 첫 진입 시 (1회) | 맥락 힌트 버블 |
| C. 설정 도움말 | 설정 탐색 시 (항상) | "?" 팝오버 |

설계 원칙:
- **비차단(non-blocking)**: 모든 가이드는 건너뛸 수 있다. 사용자의 작업 흐름을 방해하지 않는다.
- **1회 표시 + 다시 보지 않기**: UserDefaults 플래그로 관리. 설정에서 전체 리셋 가능.
- **점진적 공개**: 필수 정보만 먼저, 상세는 탭/클릭으로 확장.

---

## 2. A. 온보딩 확장 — 기능 투어

### 2.1 진입 조건

현재 온보딩 6단계(welcome → provider → apiKey → profile → agent → complete) 완료 후, `completeStep`에서 "시작하기" 버튼 대신 두 가지 선택지를 제공:

```
[시작하기]  (바로 앱 진입)
[기능 둘러보기]  (기능 투어 시작, 3~4분 소요)
```

### 2.2 기능 투어 흐름

기존 OnboardingStep enum에 투어 단계를 추가한다. 투어는 **선택적**이며 언제든 "건너뛰기"로 종료 가능.

#### 투어 단계 정의

| 단계 | ID | 제목 | 내용 |
|------|----|------|------|
| T1 | `tourOverview` | 도치가 할 수 있는 것 | 도구 카테고리 8개를 아이콘 + 한 줄 설명으로 소개 |
| T2 | `tourConversation` | 대화의 기본 | 텍스트 입력, 슬래시 명령, 음성 입력 설명 |
| T3 | `tourAgentWorkspace` | 에이전트 & 워크스페이스 | 에이전트 개념, 워크스페이스 분리, 전환 방법 |
| T4 | `tourShortcuts` | 빠른 조작법 | 핵심 단축키 5개 + 커맨드 팔레트 소개 |

#### T1: 도구 카테고리 소개

**레이아웃**: 2열 4행 그리드 (480px 폭 내).

| 아이콘 | 카테고리 | 한 줄 설명 |
|--------|----------|------------|
| `calendar` | 일정 & 미리알림 | 캘린더 조회/추가, 미리알림 관리, 타이머 |
| `rectangle.3.group` | 칸반 보드 | 프로젝트를 칸반으로 시각화하고 관리 |
| `magnifyingglass` | 웹 검색 | 실시간 웹 검색과 정보 수집 |
| `doc.text` | 파일 & 클립보드 | 파일 탐색, 읽기/쓰기, 클립보드 |
| `terminal` | 개발 도구 | Git, GitHub, 셸 명령 실행 |
| `music.note` | 미디어 | 음악 제어, 이미지 생성, 스크린샷 |
| `brain` | 메모리 | 대화 내용 기억, 개인 정보 관리 |
| `puzzlepiece` | 확장 (MCP) | 외부 도구 서버 연결 |

각 카테고리 카드:
- 40x40pt 아이콘 원형 배경 (카테고리별 고유 색상, opacity 0.1)
- 카테고리명 (13pt, semibold)
- 한 줄 설명 (11pt, secondary)
- 카드 전체 클릭 시 → 해당 카테고리의 대표 프롬프트 3개를 팝오버로 표시 (선택 시 대화에 자동 입력, 투어 종료)

하단: "모든 도구 보기" 링크 → 투어 종료 + CapabilityCatalogView 열기

#### T2: 대화의 기본

**레이아웃**: 세로 3섹션, 각 섹션에 모의 UI 스크린샷 스타일 일러스트.

| 섹션 | 아이콘 | 제목 | 설명 |
|------|--------|------|------|
| 1 | `text.bubble` | 텍스트 입력 | 하단 입력창에 메시지를 입력하면 AI가 답변합니다. Shift+Enter로 줄바꿈. |
| 2 | `slash.circle` | 슬래시 명령 | / 를 입력하면 명령 목록이 나타납니다. 빠르게 기능을 실행할 수 있습니다. |
| 3 | `mic` | 음성 대화 | 마이크 버튼을 누르거나 웨이크워드("{wakeWord}")를 말하면 음성으로 대화합니다. |

각 섹션:
- 좌측: SF Symbol 아이콘 (24pt, accentColor)
- 우측: 제목 (13pt, semibold) + 설명 (12pt, secondary)
- 섹션 간 얇은 Divider

하단 보조 텍스트: "도치는 필요한 도구를 자동으로 선택합니다. 별도로 도구를 지정할 필요 없어요."

#### T3: 에이전트 & 워크스페이스

**레이아웃**: 좌우 2컬럼.

**좌측 — 에이전트**:
- 아이콘: `person.crop.rectangle.stack` (36pt)
- 제목: "에이전트"
- 설명: "목적에 맞는 AI 비서를 만들 수 있습니다. 코딩, 리서치, 일정 관리 등 템플릿으로 빠르게 시작하세요."
- 시각: 템플릿 아이콘 5개를 가로 나열 (coding `chevron.left.slash.chevron.right`, researcher `magnifyingglass`, scheduler `calendar`, writer `pencil.line`, kanban `rectangle.3.group`)
- 하단: "에이전트 만들기 →" 텍스트 버튼 (투어 종료 + AgentWizardView 열기)

**우측 — 워크스페이스**:
- 아이콘: `square.stack.3d.up` (36pt)
- 제목: "워크스페이스"
- 설명: "프로젝트별로 독립된 공간을 만들 수 있습니다. 각 워크스페이스에 별도 메모리와 에이전트를 설정합니다."
- 시각: 워크스페이스 전환 드롭다운 모의 이미지 (HStack: "기본" / "프로젝트 A" / "+" 아이콘)
- 하단: "⌘⇧W로 빠르게 전환" 키캡 힌트

#### T4: 빠른 조작법

**레이아웃**: 5행 테이블 스타일.

| 단축키 | 동작 | 설명 |
|--------|------|------|
| ⌘K | 커맨드 팔레트 | 무엇이든 빠르게 찾고 실행 |
| ⌘N | 새 대화 | 새 대화 시작 |
| ⌘I | 메모리 패널 | AI가 기억하는 정보 확인/편집 |
| ⌘⇧A | 에이전트 전환 | 다른 에이전트로 빠르게 전환 |
| ⌘/ | 단축키 도움말 | 전체 단축키 목록 보기 |

각 행:
- 좌측: 키캡 스타일 텍스트 (KeyboardShortcutHelpView의 기존 키캡 패턴 재사용)
- 중앙: 동작명 (13pt, medium)
- 우측: 설명 (12pt, secondary)

하단: "전체 단축키는 ⌘/ 로 언제든 볼 수 있습니다." (11pt, tertiary)

### 2.3 투어 네비게이션

```
[건너뛰기]                    ● ● ○ ○                    [다음]
(좌측, plain 스타일)    (중앙, 단계 인디케이터)      (우측, borderedProminent)
```

- 마지막 단계(T4)의 "다음" 버튼 → "시작하기"로 변경
- "건너뛰기" → 즉시 투어 종료, 앱 진입
- 투어 중 뒤로 가기: 좌측에 "이전" 버튼 (T1 제외)
- 투어 진행 상태는 별도 저장 불필요 (완료 또는 건너뛰기만 기록)

### 2.4 투어 완료 상태 저장

```swift
// UserDefaults 키
"featureTourCompleted"  // Bool — 투어 완료 또는 건너뛰기 시 true
"featureTourSkipped"    // Bool — 건너뛰기로 종료 시 true (나중에 다시 보기 제안에 활용)
```

### 2.5 투어 다시 보기

투어를 건너뛴 사용자를 위한 재진입:
- **설정 > 일반 > "기능 투어 다시 보기" 버튼** (featureTourCompleted를 false로 리셋 후 투어 시트 표시)
- **커맨드 팔레트(⌘K)**: "기능 투어" 항목 추가 (항상 표시)
- **EmptyConversationView**: featureTourSkipped == true인 경우, 카테고리 제안 영역 상단에 한 번 "기능 투어를 아직 보지 않았어요. [둘러보기]" 배너 표시 (닫으면 `featureTourBannerDismissed = true`)

---

## 3. B. 인앱 힌트 — 첫 진입 가이드

### 3.1 힌트 시스템 설계

**HintBubble 컴포넌트** (신규): 특정 UI 요소 근처에 말풍선 형태로 나타나는 일회성 가이드.

#### 시각 스펙

```
┌─────────────────────────────────┐
│ ℹ️  [제목]                   ✕  │
│  설명 텍스트...                  │
│                    [확인] [다시 보지 않기] │
└──────────△──────────────────────┘
           ▽ (화살표: 대상 UI 요소를 가리킴)
```

- 배경: `.background(.regularMaterial)` (vibrancy 효과)
- 모서리: cornerRadius 10
- 그림자: `.shadow(color: .black.opacity(0.1), radius: 8, y: 4)`
- 최대 너비: 320pt
- 화살표(삼각형): 대상 요소 방향으로 (위/아래/좌/우)
- 제목: 13pt, semibold
- 설명: 12pt, secondary
- "확인" 버튼: plain 스타일, accentColor (힌트 닫기)
- "다시 보지 않기": 11pt, tertiary (모든 힌트 비활성화)
- 닫기(✕): 우측 상단 9pt 버튼

#### 구현 패턴

```swift
// HintBubble을 ViewModifier로 구현
.hintBubble(
    id: "firstConversation",
    title: "첫 대화를 시작해보세요",
    message: "아래 제안을 클릭하거나, 궁금한 것을 자유롭게 입력하세요.",
    edge: .bottom,           // 화살표 방향
    condition: { isFirstConversation }  // 표시 조건
)
```

#### UserDefaults 관리

```swift
// 개별 힌트 키: "hint_seen_{id}" = Bool
// 전역 비활성화: "hintsGloballyDisabled" = Bool
```

### 3.2 힌트 목록

| ID | 대상 뷰 | 트리거 조건 | 위치 | 제목 | 메시지 |
|----|---------|------------|------|------|--------|
| `firstConversation` | EmptyConversationView | 첫 대화 화면 진입 (conversations.count == 0) | 제안 프롬프트 영역 상단 | 첫 대화를 시작해보세요 | 아래 제안을 클릭하거나, 궁금한 것을 자유롭게 입력하세요. /로 시작하면 명령 목록도 볼 수 있어요. |
| `firstKanban` | KanbanWorkspaceView | 칸반 탭 첫 진입 (boards.count == 0) | "보드 추가" 버튼 근처 | 칸반 보드로 프로젝트 관리 | "+"를 눌러 보드를 만들거나, 대화에서 "프로젝트 보드 만들어줘"라고 말해보세요. |
| `firstAgent` | AgentWizardView | 에이전트 위저드 첫 열기 | 템플릿 선택 영역 상단 | 템플릿으로 빠르게 시작 | 미리 준비된 템플릿을 선택하면 이름과 페르소나가 자동으로 채워집니다. 나중에 언제든 수정할 수 있어요. |
| `firstMemoryPanel` | MemoryPanelView | 메모리 패널 첫 열기 | 패널 상단 | AI의 기억을 확인하세요 | 여기서 도치가 기억하는 정보를 계층별로 확인하고 직접 편집할 수 있습니다. |
| `firstToolExecution` | ToolExecutionCardView | 첫 도구 실행 시 | 도구 카드 상단 | 도구가 실행되고 있어요 | 도치가 자동으로 필요한 도구를 선택했습니다. 카드를 클릭하면 상세 내용을 볼 수 있어요. |
| `firstSlashCommand` | SlashCommandPopoverView | / 첫 입력 시 | 팝오버 상단 | 슬래시 명령 | 자주 쓰는 기능을 빠르게 실행할 수 있습니다. 입력을 계속하면 필터링됩니다. |
| `firstCommandPalette` | CommandPaletteView | 커맨드 팔레트 첫 열기 | 검색 입력 필드 하단 | 무엇이든 빠르게 | 기능, 에이전트 전환, 설정 등 거의 모든 동작을 여기서 실행할 수 있습니다. |
| `firstExport` | ExportOptionsView | 내보내기 시트 첫 열기 | 형식 선택 영역 상단 | 대화를 다양한 형식으로 | Markdown, JSON, PDF, 텍스트 4가지 형식으로 내보낼 수 있습니다. ⌘E로 빠른 내보내기도 가능해요. |
| `firstSystemPrompt` | SystemPromptBannerView | 시스템 프롬프트 배너 첫 표시 | 배너 우측 | 시스템 프롬프트 커스터마이징 | AI의 기본 행동을 여기서 설정할 수 있습니다. 클릭해서 편집해보세요. |

### 3.3 힌트 표시 규칙

1. **동시 표시 최대 1개**: 여러 힌트 조건이 동시에 충족되면 우선순위(위 테이블 순서) 기준 1개만 표시.
2. **표시 지연**: 대상 뷰 진입 후 1.5초 후 fadeIn 애니메이션으로 표시 (즉시 나타나면 정신 없음).
3. **자동 숨김 없음**: 사용자가 "확인" 또는 ✕를 누를 때까지 유지.
4. **"다시 보지 않기" 전역 적용**: 클릭 시 `hintsGloballyDisabled = true` → 모든 힌트 비활성화. 설정에서 리셋 가능.
5. **처리 중 비표시**: `interactionState != .idle`이면 힌트를 표시하지 않음 (스트리밍 중 방해 방지).

### 3.4 "다시 보지 않기" 리셋

설정 > 일반 > 하단:

```
섹션: "가이드"
├── [기능 투어 다시 보기] 버튼
├── [인앱 힌트 초기화] 버튼  ← 모든 hint_seen_ 키 삭제 + hintsGloballyDisabled = false
└── Toggle: "인앱 힌트 표시" (hintsGloballyDisabled의 반전 바인딩)
```

---

## 4. C. 설정 내 도움말

### 4.1 섹션 도움말 ("?" 버튼)

각 설정 섹션 헤더 우측에 `questionmark.circle` 아이콘 버튼을 추가한다. 클릭 시 popover로 설명 표시.

#### 구현 패턴

```swift
Section {
    // 기존 설정 항목들...
} header: {
    HStack {
        Text("섹션 제목")
        Spacer()
        SettingsHelpButton(content: "이 섹션에 대한 설명 텍스트")
    }
}
```

#### SettingsHelpButton 시각 스펙

- 아이콘: `questionmark.circle` (12pt, secondary)
- 호버 시: accentColor로 변경
- 클릭 → popover:
  - 최대 너비 280pt
  - 패딩 12pt
  - 텍스트: 12pt, .secondary
  - 배경: 기본 popover 스타일

### 4.2 섹션별 도움말 내용

#### 일반 설정 (GeneralSettingsView)

| 섹션 | 도움말 |
|------|--------|
| 글꼴 | 대화 영역의 글꼴 크기를 조절합니다. 시스템 설정의 접근성 글꼴과 독립적입니다. |
| 상호작용 모드 | "음성 + 텍스트"는 마이크 버튼과 웨이크워드를 활성화합니다. "텍스트 전용"은 음성 기능을 비활성화합니다. |
| 웨이크워드 | 지정한 단어를 말하면 자동으로 음성 입력이 시작됩니다. "항상 대기 모드"를 켜면 앱이 활성화된 동안 계속 감지합니다. |
| 아바타 | VRM 형식의 3D 아바타를 대화 영역 위에 표시합니다. macOS 15 이상에서 사용 가능합니다. Resources/Models/에 VRM 파일이 필요합니다. |
| 하트비트 | 주기적으로 캘린더, 칸반, 미리알림을 점검하여 알려줄 내용이 있으면 자동으로 메시지를 보냅니다. 조용한 시간 동안에는 알림을 보내지 않습니다. |

#### AI 모델 설정 (ModelSettingsView)

| 섹션 | 도움말 |
|------|--------|
| LLM 프로바이더 | AI 응답을 생성하는 서비스를 선택합니다. 각 프로바이더는 다른 모델과 가격 체계를 갖고 있습니다. API 키가 필요합니다. |
| 컨텍스트 | 모델이 한 번에 처리할 수 있는 텍스트 양(토큰)입니다. 대화가 길어지면 오래된 메시지는 자동으로 압축됩니다. |
| 용도별 모델 라우팅 | 메시지 복잡도를 자동으로 판단하여 간단한 질문은 빠른 모델에, 복잡한 작업은 고급 모델에 보냅니다. 비용 절약과 속도 개선에 유용합니다. |

#### API 키 설정 (APIKeySettingsView)

| 섹션 | 도움말 |
|------|--------|
| (전체) | API 키는 macOS 키체인에 암호화되어 저장됩니다. 각 프로바이더 웹사이트에서 키를 발급받을 수 있습니다. 키를 입력하지 않은 프로바이더의 모델은 사용할 수 없습니다. |

#### 음성 설정 (VoiceSettingsView)

| 섹션 | 도움말 |
|------|--------|
| TTS 프로바이더 | 텍스트를 음성으로 변환하는 엔진을 선택합니다. "시스템 TTS"는 추가 설정 없이 사용 가능하며, Google Cloud TTS와 Supertonic은 더 자연스러운 음성을 제공합니다. |
| Supertonic | 로컬에서 실행되는 고품질 TTS입니다. 인터넷 연결 없이 작동하지만, ONNX 모델 파일이 필요합니다. |

#### 가족 설정 (FamilySettingsView)

| 섹션 | 도움말 |
|------|--------|
| (전체) | 여러 사용자가 하나의 도치를 공유할 수 있습니다. 각 사용자는 별도의 메모리와 대화 기록을 가집니다. 사이드바 상단이나 ⌘⇧U로 사용자를 전환할 수 있습니다. |

#### 에이전트 설정 (AgentSettingsView)

| 섹션 | 도움말 |
|------|--------|
| (전체) | 에이전트는 특정 목적에 맞게 설정된 AI 비서입니다. 각 에이전트는 고유한 페르소나, 모델, 도구 권한을 가집니다. 템플릿으로 빠르게 만들거나, 기존 에이전트를 복제/편집할 수 있습니다. |

#### 도구 설정 (ToolsSettingsView)

| 섹션 | 도움말 |
|------|--------|
| (전체) | 도치가 사용할 수 있는 35개 내장 도구 목록입니다. "기본 제공" 도구는 항상 사용 가능하고, "조건부" 도구는 AI가 필요할 때 자동으로 활성화합니다. 권한 등급(safe/sensitive/restricted)에 따라 승인이 필요할 수 있습니다. |

#### 통합 설정 (IntegrationsSettingsView)

| 섹션 | 도움말 |
|------|--------|
| 텔레그램 | 텔레그램 봇을 연결하면 텔레그램 DM으로도 도치와 대화할 수 있습니다. @BotFather에서 봇을 만들고 토큰을 입력하세요. |
| MCP | Model Context Protocol 서버를 추가하면 외부 도구를 도치에 연결할 수 있습니다. 데이터베이스, 사내 API 등을 AI가 직접 사용합니다. |

#### 계정 설정 (AccountSettingsView)

| 섹션 | 도움말 |
|------|--------|
| Supabase 연결 | 클라우드 동기화를 위한 Supabase 서버를 연결합니다. 대화, 메모리, 설정을 여러 기기에서 동기화할 수 있습니다. 자체 Supabase 프로젝트를 만들어 사용합니다. |

### 4.3 주요 설정 항목 인라인 설명

복잡하거나 자주 혼동되는 설정 항목에는 `.help()` modifier가 아닌 **인라인 캡션**을 추가한다 (`.help()`은 마우스 호버 시만 나타나 발견성이 낮음).

| 설정 항목 | 인라인 캡션 |
|-----------|------------|
| 자동 모델 선택 토글 | "메시지 복잡도에 따라 경량/고급 모델을 자동 선택합니다" (이미 있음 — `.help()` → 인라인으로 변경) |
| 하트비트 활성화 토글 | "주기적으로 일정과 할 일을 점검하여 자동 알림" |
| 항상 대기 모드 토글 | "앱이 활성화되어 있는 동안 항상 웨이크워드를 감지합니다" (이미 있음 — `.help()` → 인라인으로 변경) |
| 3D 아바타 표시 토글 | "VRM 3D 아바타를 대화 영역 위에 표시합니다 (macOS 15+)" (이미 있음 — `.help()` → 인라인으로 변경) |
| 텔레그램 스트리밍 응답 토글 | "응답을 점진적으로 전송합니다 (API 호출 증가)" |

인라인 캡션 스타일:
```swift
Text("설명 텍스트")
    .font(.caption)
    .foregroundStyle(.secondary)
```

기존 `.help()` modifier는 제거하지 않고 유지 — 인라인 캡션과 중복 표시되더라도 접근성(VoiceOver) 측면에서 `.help()`도 가치가 있다.

---

## 5. 데이터 모델

### 5.1 UserDefaults 키 (신규)

| 키 | 타입 | 기본값 | 설명 |
|----|------|--------|------|
| `featureTourCompleted` | Bool | false | 기능 투어 완료/건너뛰기 |
| `featureTourSkipped` | Bool | false | 건너뛰기로 종료한 경우 |
| `featureTourBannerDismissed` | Bool | false | EmptyConversationView 재안내 배너 닫음 |
| `hint_seen_firstConversation` | Bool | false | 각 힌트별 표시 여부 |
| `hint_seen_firstKanban` | Bool | false | |
| `hint_seen_firstAgent` | Bool | false | |
| `hint_seen_firstMemoryPanel` | Bool | false | |
| `hint_seen_firstToolExecution` | Bool | false | |
| `hint_seen_firstSlashCommand` | Bool | false | |
| `hint_seen_firstCommandPalette` | Bool | false | |
| `hint_seen_firstExport` | Bool | false | |
| `hint_seen_firstSystemPrompt` | Bool | false | |
| `hintsGloballyDisabled` | Bool | false | 모든 힌트 비활성화 |

### 5.2 AppSettings 확장 (선택)

투어 및 힌트 상태를 AppSettings에 통합할 수도 있지만, 이들은 **UI 상태**이지 **앱 설정**이 아니므로 UserDefaults 직접 접근을 권장한다. 다만, 설정 UI에서 리셋 기능을 제공해야 하므로 편의 메서드를 추가한다:

```swift
// AppSettings 확장
extension AppSettings {
    var hintsEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "hintsGloballyDisabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "hintsGloballyDisabled") }
    }

    func resetAllHints() {
        let hintKeys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("hint_seen_") }
        hintKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserDefaults.standard.set(false, forKey: "hintsGloballyDisabled")
    }

    func resetFeatureTour() {
        UserDefaults.standard.set(false, forKey: "featureTourCompleted")
        UserDefaults.standard.set(false, forKey: "featureTourSkipped")
        UserDefaults.standard.set(false, forKey: "featureTourBannerDismissed")
    }
}
```

---

## 6. 뷰 구조 변경

### 6.1 OnboardingView 변경

```
OnboardingView
├── [기존 6단계 그대로 유지]
│   ├── welcome
│   ├── provider
│   ├── apiKey
│   ├── profile
│   ├── agent
│   └── complete  ← 수정: "시작하기" + "기능 둘러보기" 2버튼
└── [신규 투어 단계]
    ├── tourOverview     (T1)
    ├── tourConversation (T2)
    ├── tourAgentWorkspace (T3)
    └── tourShortcuts    (T4)
```

OnboardingStep enum 확장:
```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case provider
    case apiKey
    case profile
    case agent
    case complete
    // 기능 투어 (선택적)
    case tourOverview
    case tourConversation
    case tourAgentWorkspace
    case tourShortcuts
}
```

`complete` 단계에서 "기능 둘러보기" 선택 시 `step = .tourOverview`로 전환. 투어 단계에서 네비게이션 바는 투어 전용 프로그레스 인디케이터(4개)를 표시한다 (기존 6단계 인디케이터와 분리).

### 6.2 신규 파일

| 파일 | 설명 |
|------|------|
| `Dochi/Views/Guide/HintBubbleModifier.swift` | HintBubble ViewModifier + HintManager |
| `Dochi/Views/Guide/SettingsHelpButton.swift` | 설정 섹션 도움말 "?" 버튼 |
| `Dochi/Views/Guide/FeatureTourViews.swift` | 투어 단계 T1~T4 개별 뷰 |

### 6.3 기존 파일 수정

| 파일 | 변경 |
|------|------|
| `Views/OnboardingView.swift` | OnboardingStep enum 확장, completeStep UI 수정, 투어 단계 추가 |
| `Views/ContentView.swift` | EmptyConversationView에 투어 재안내 배너 추가, HintBubble 적용 |
| `Views/KanbanWorkspaceView.swift` | firstKanban 힌트 적용 |
| `Views/Agent/AgentWizardView.swift` | firstAgent 힌트 적용 |
| `Views/MemoryPanelView.swift` | firstMemoryPanel 힌트 적용 |
| `Views/ToolExecutionCardView.swift` | firstToolExecution 힌트 적용 |
| `Views/CommandPaletteView.swift` | 커맨드 팔레트에 "기능 투어" 항목 추가, firstCommandPalette 힌트 적용 |
| `Views/ExportOptionsView.swift` | firstExport 힌트 적용 |
| `Views/SystemPromptBannerView.swift` | firstSystemPrompt 힌트 적용 |
| `Views/SettingsView.swift` | 섹션별 SettingsHelpButton 추가, 일반 탭에 가이드 섹션 추가 |
| `Views/Settings/VoiceSettingsView.swift` | SettingsHelpButton 추가 |
| `Views/Settings/IntegrationsSettingsView.swift` | SettingsHelpButton 추가 |
| `Views/Settings/AccountSettingsView.swift` | SettingsHelpButton 추가 |
| `Views/Settings/ToolsSettingsView.swift` | SettingsHelpButton 추가 |
| `Views/Settings/FamilySettingsView.swift` | SettingsHelpButton 추가 |
| `Views/Settings/AgentSettingsView.swift` | SettingsHelpButton 추가 |
| `Models/AppSettings.swift` | hintsEnabled, resetAllHints(), resetFeatureTour() 추가 |
| `Models/CommandPaletteItem.swift` | "기능 투어" 항목 추가 |

---

## 7. 커맨드 팔레트 확장

CommandPaletteView의 항목 목록에 추가:

| 그룹 | 명령 | 아이콘 | 동작 |
|------|------|--------|------|
| 도움말 | 기능 투어 | `questionmark.circle` | featureTourCompleted를 false로 리셋, 투어 시트 열기 |
| 도움말 | 인앱 힌트 초기화 | `arrow.counterclockwise` | resetAllHints() 호출 + 토스트 피드백 |

---

## 8. 접근성

- **VoiceOver**: 모든 힌트 버블과 투어 단계에 적절한 `.accessibilityLabel` / `.accessibilityHint` 적용
- **키보드 내비게이션**: 힌트 버블은 Tab 포커스 가능. "확인" 버튼이 기본 포커스. Escape로 닫기 가능.
- **모션 감소**: `@Environment(\.accessibilityReduceMotion)`이 true이면 fadeIn 애니메이션 대신 즉시 표시

---

## 9. 테스트 계획

### 9.1 단위 테스트

| 테스트 | 검증 내용 |
|--------|----------|
| `HintManagerTests` | hint_seen 키 읽기/쓰기, 전역 비활성화, 리셋 |
| `AppSettingsGuideTests` | hintsEnabled, resetAllHints(), resetFeatureTour() |
| `OnboardingStepTests` | 투어 단계 전환 로직, 건너뛰기 시 상태 저장 |

### 9.2 스모크 테스트 확장

`SmokeTestReporter`에 추가 항목:
- `featureTourCompleted` 값
- `hintsGloballyDisabled` 값

### 9.3 수동 검증 체크리스트

- [ ] 최초 설치 → 온보딩 완료 → "기능 둘러보기" 선택 → T1~T4 정상 표시
- [ ] 투어 중 "건너뛰기" → featureTourSkipped = true, 앱 진입
- [ ] 투어 완료 후 재실행 → 투어 표시 안 됨
- [ ] EmptyConversationView → 투어 미완료 시 재안내 배너 표시
- [ ] 첫 칸반 진입 → 힌트 버블 표시 → "확인" → 재진입 시 미표시
- [ ] "다시 보지 않기" → 이후 모든 힌트 미표시
- [ ] 설정 > 일반 > 인앱 힌트 초기화 → 힌트 다시 표시
- [ ] 설정 > 일반 > 기능 투어 다시 보기 → 투어 시트 열림
- [ ] 각 설정 섹션 "?" 버튼 → 팝오버 표시
- [ ] 커맨드 팔레트 "기능 투어" 항목 → 투어 열림

---

## 10. 구현 순서 (권장)

| 순서 | 작업 | 예상 난이도 |
|------|------|------------|
| 1 | HintBubbleModifier + HintManager 구현 | 중 |
| 2 | SettingsHelpButton 컴포넌트 + 설정 도움말 적용 (C) | 하 |
| 3 | 투어 단계 뷰 T1~T4 구현 (A) | 중 |
| 4 | OnboardingView 확장 (complete 단계 분기 + 투어 통합) | 중 |
| 5 | 인앱 힌트 각 뷰에 적용 (B) | 하 |
| 6 | 설정 > 일반 > 가이드 섹션 추가 | 하 |
| 7 | 커맨드 팔레트 확장 | 하 |
| 8 | 단위 테스트 작성 | 중 |
| 9 | EmptyConversationView 재안내 배너 | 하 |
| 10 | 인라인 캡션 변환 (.help → 인라인) | 하 |

---

## 11. ui-inventory.md 업데이트 사항

머지 시 아래 항목 추가:

### 모든 화면 목록 > 시트/모달 행 추가

```
| 기능 투어 (OnboardingView 내) | Views/OnboardingView.swift | 최초 온보딩 완료 후 선택 / 설정 > 일반 / 커맨드 팔레트 | 4단계 기능 소개 투어 |
```

### 컴포넌트 스타일 패턴 행 추가

```
| 힌트 버블 (.hintBubble modifier) | 각 뷰 첫 진입 시 | material 배경 + 화살표 + 1회 표시 |
| 설정 도움말 팝오버 (SettingsHelpButton) | 설정 섹션 헤더 | "?" 아이콘 → 설명 팝오버 |
```

### 빈 상태 행 추가

```
| 투어 미완료 재안내 | "기능 투어를 아직 보지 않았어요. [둘러보기]" | EmptyConversationView 상단 |
```

### 키보드 단축키 (변경 없음)

커맨드 팔레트 항목 추가로 ⌘K → "기능 투어" 접근 가능. 별도 단축키는 불필요.

---

*최종 업데이트: 2026-02-15*
