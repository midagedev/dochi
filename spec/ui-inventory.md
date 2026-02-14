# UI 인벤토리

> 이 문서는 Dochi의 모든 화면, 컴포넌트, 데이터 흐름을 정리한다.
> UX 설계 시 코드 대신 이 문서를 참조한다.
> **기능 머지 시 반드시 업데이트할 것.**

---

## 앱 구조

```
DochiApp (entry point)
└── ContentView (NavigationSplitView)
    ├── [Sidebar] SidebarView
    │   ├── SidebarHeaderView — 워크스페이스/에이전트/사용자 전환
    │   ├── Section Picker — 대화 / 칸반 탭
    │   ├── 대화 검색 + 대화 목록 (List)
    │   └── SidebarAuthStatusView — Supabase 로그인 상태
    └── [Detail]
        ├── [대화 탭]
        │   ├── SystemHealthBarView — 시스템 상태 바 (모델/동기화/하트비트/토큰) [항상 표시]
        │   ├── StatusBarView — 상태/토큰 (처리 중에만 표시)
        │   ├── ToolConfirmationBannerView — 민감 도구 승인
        │   ├── ErrorBannerView — 에러 표시
        │   ├── AvatarView — 3D 아바타 (macOS 15+, 선택적)
        │   ├── EmptyConversationView — 빈 대화 시작 (카테고리 제안 + 카탈로그 링크)
        │   │   또는 ConversationView — 메시지 목록
        │   │       └── MessageBubbleView — 개별 메시지 버블
        │   │           └── MessageMetadataBadgeView — 모델/응답시간 배지 (assistant만, 호버 팝오버)
        │   ├── Divider
        │   └── InputBarView — 텍스트 입력 + 마이크 + 슬래시 명령
        │       └── SlashCommandPopoverView — / 자동완성 팝업
        └── [칸반 탭]
            └── KanbanWorkspaceView
                └── KanbanBoardView → KanbanColumnView → KanbanCardView
```

---

## 모든 화면 목록

### 메인 뷰

| 화면 | 파일 | 접근 방법 | 설명 |
|------|------|-----------|------|
| ContentView | `Views/ContentView.swift` | 앱 시작 | 메인 레이아웃 (사이드바 + 디테일) |
| SidebarView | `Views/ContentView.swift` | 항상 표시 | 대화 목록, 검색, 섹션 탭 |
| SidebarHeaderView | `Views/Sidebar/SidebarHeaderView.swift` | 사이드바 상단 | 워크스페이스/에이전트/사용자 드롭다운 |
| ConversationView | `Views/ConversationView.swift` | 대화 선택 시 | 메시지 스크롤 뷰 |
| MessageBubbleView | `Views/MessageBubbleView.swift` | 자동 | 개별 메시지 렌더링 (역할별 스타일) |
| EmptyConversationView | `Views/ContentView.swift` | 빈 대화 | 카테고리별 제안 프롬프트, "모든 기능 보기" 링크 |
| InputBarView | `Views/ContentView.swift` | 항상 표시 | 텍스트 입력, 마이크, 전송/취소 버튼, 슬래시 명령 |
| SystemHealthBarView | `Views/SystemHealthBarView.swift` | 항상 표시 | 현재 모델, 동기화 상태, 하트비트, 세션 토큰 (클릭 → 상세 시트) |
| MessageMetadataBadgeView | `Views/MessageBubbleView.swift` | assistant 메시지 자동 | 모델명·응답시간 배지, 호버 시 상세 팝오버 (토큰/프로바이더/폴백) |
| StatusBarView | `Views/ContentView.swift` | 처리 중 자동 | 상태 아이콘 + 텍스트 + 토큰 사용량 |
| AvatarView | `Views/AvatarView.swift` | 설정 활성화 시 | VRM 3D 아바타 (RealityKit, macOS 15+) |

### 칸반

| 화면 | 파일 | 접근 방법 | 설명 |
|------|------|-----------|------|
| KanbanWorkspaceView | `Views/KanbanWorkspaceView.swift` | 칸반 탭 | 보드 목록 + 보드 선택 |
| KanbanBoardView | `Views/KanbanBoardView.swift` | 보드 선택 | 컬럼 + 카드 (드래그 지원) |

### 시트/모달

| 화면 | 파일 | 접근 방법 | 설명 |
|------|------|-----------|------|
| SystemStatusSheetView | `Views/SystemStatusSheetView.swift` | 툴바 "상태" 버튼 (⌘⇧S) 또는 SystemHealthBar 클릭 | 3탭 상세: LLM 교환 이력, 하트비트 틱 기록, 클라우드 동기화 |
| CapabilityCatalogView | `Views/CapabilityCatalogView.swift` | 툴바 "기능" 버튼 (⌘⇧F) | 전체 도구 그룹별 카탈로그 |
| ContextInspectorView | `Views/ContextInspectorView.swift` | 툴바 "컨텍스트" 버튼 | 시스템 프롬프트 / 에이전트 / 메모리 탭 |
| OnboardingView | `Views/OnboardingView.swift` | 최초 실행 시 자동 | 6단계 초기 설정 위저드 |
| WorkspaceManagementView | `Views/Sidebar/WorkspaceManagementView.swift` | SidebarHeader 메뉴 | 워크스페이스 생성/삭제 |
| AgentCreationView | `Views/Sidebar/AgentCreationView.swift` | SidebarHeader 메뉴 | 에이전트 생성 폼 |
| AgentDetailView | `Views/Sidebar/AgentDetailView.swift` | SidebarHeader 메뉴 | 에이전트 편집 (설정/페르소나/메모리 3탭) |
| LoginSheet | `Views/Settings/LoginSheet.swift` | 계정 설정에서 | Supabase 로그인/가입 |

### 설정 (SettingsView — 9개 탭)

| 탭 | 파일 | 내용 |
|----|------|------|
| 일반 | `Views/SettingsView.swift` 내 | 폰트, 인터랙션 모드, 웨이크워드, 아바타, Heartbeat |
| AI 모델 | `Views/SettingsView.swift` 내 | 프로바이더/모델 선택, Ollama, 태스크 라우팅, 폴백 |
| API 키 | `Views/SettingsView.swift` 내 | OpenAI/Anthropic/Z.AI/Tavily/Fal.ai 키 관리 |
| 음성 | `Views/Settings/VoiceSettingsView.swift` | TTS 프로바이더, 음성, 속도/피치 |
| 가족 | `Views/Settings/FamilySettingsView.swift` | 사용자 프로필 CRUD |
| 에이전트 | `Views/Settings/AgentSettingsView.swift` | 에이전트 목록 + 인라인 생성 |
| 도구 | `Views/Settings/ToolsSettingsView.swift` | 도구 브라우저 (검색/필터/상세) |
| 통합 | `Views/Settings/IntegrationsSettingsView.swift` | 텔레그램, MCP, 채팅 매핑 |
| 계정 | `Views/Settings/AccountSettingsView.swift` | Supabase 인증, 동기화 |

---

## ViewModel 상태 (DochiViewModel)

### 핵심 상태

| 프로퍼티 | 타입 | 설명 | UI 사용처 |
|----------|------|------|-----------|
| `interactionState` | `InteractionState` | idle/listening/processing/speaking | StatusBar, InputBar, AvatarView |
| `sessionState` | `SessionState` | inactive/active/ending | StatusBar 배지 |
| `processingSubState` | `ProcessingSubState?` | streaming/toolCalling/toolError/complete | StatusBar 텍스트 |
| `currentConversation` | `Conversation?` | 현재 대화 | ConversationView |
| `conversations` | `[Conversation]` | 대화 목록 | SidebarView |
| `streamingText` | `String` | 스트리밍 중인 응답 | ConversationView |
| `inputText` | `String` | 입력 텍스트 | InputBarView |
| `errorMessage` | `String?` | 에러 메시지 | ErrorBannerView |
| `currentToolName` | `String?` | 실행 중인 도구 | StatusBarView |
| `partialTranscript` | `String` | STT 중간 결과 | StatusBarView |
| `pendingToolConfirmation` | `ToolConfirmation?` | 승인 대기 도구 | ToolConfirmationBannerView |
| `lastInputTokens` | `Int?` | 마지막 입력 토큰 | StatusBarView |
| `lastOutputTokens` | `Int?` | 마지막 출력 토큰 | StatusBarView |
| `contextWindowTokens` | `Int` | 모델 컨텍스트 윈도우 | StatusBarView |
| `metricsCollector` | `MetricsCollector` | LLM 교환 메트릭 수집 | SystemHealthBarView, SystemStatusSheetView |

### Message.metadata (UX-2 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `provider` | `String` | LLM 프로바이더명 |
| `model` | `String` | 사용된 모델명 |
| `inputTokens` | `Int?` | 입력 토큰 |
| `outputTokens` | `Int?` | 출력 토큰 |
| `totalLatency` | `TimeInterval?` | 응답 시간 |
| `wasFallback` | `Bool` | 폴백 모델 사용 여부 |

### 누락된 상태 (현재 UI에 노출 안 됨)

| 정보 | 소스 | 문제 |
|------|------|------|
| 연결된 디바이스 | DeviceHeartbeatService | 어떤 디바이스가 온라인인지 표시 없음 |

---

## 설정 (AppSettings)

| 그룹 | 주요 프로퍼티 |
|------|-------------|
| LLM | `llmProvider`, `llmModel`, `fallbackLLMProvider`, `fallbackLLMModel` |
| 태스크 라우팅 | `taskRoutingEnabled`, `lightModelProvider/Name`, `heavyModelProvider/Name` |
| 음성 | `ttsProvider`, `wakeWordEnabled`, `wakeWord`, `sttSilenceTimeout` |
| 통합 | `telegramEnabled`, `telegramStreamReplies`, `ollamaBaseURL` |
| Heartbeat | `heartbeatEnabled`, `heartbeatIntervalMinutes`, `heartbeatCheckCalendar/Kanban/Reminders` |
| 아바타 | `avatarEnabled` |
| 기타 | `chatFontSize`, `currentWorkspaceId`, `defaultUserId`, `activeAgentName` |

---

## 데이터 흐름

### 텍스트 메시지
```
InputBarView → viewModel.sendMessage() → interactionState=.processing
→ LLMService.stream() → streamingText 업데이트
→ 도구 호출 시: currentToolName 설정, ToolConfirmationBanner (민감 도구)
→ 완료: interactionState=.idle, 대화에 메시지 추가
```

### 음성 메시지
```
InputBarView 마이크 → viewModel.startListening() → interactionState=.listening
→ SpeechService → partialTranscript 업데이트 (StatusBar에 표시)
→ 묵음 감지 → handleSpeechFinalResult() → sendMessage() 흐름과 동일
```

### 워크스페이스/사용자/에이전트 전환
```
SidebarHeaderView 드롭다운 → viewModel.switchWorkspace/User/Agent()
→ sessionContext 업데이트 → conversations 재로드 → toolRegistry 리셋
```

---

## 키보드 단축키

| 단축키 | 동작 | 위치 |
|--------|------|------|
| ⌘N | 새 대화 | SidebarView 툴바 |
| ⌘⇧S | 시스템 상태 시트 | ContentView 툴바 |
| ⌘⇧F | 기능 카탈로그 | ContentView 툴바 |
| Escape | 요청 취소 | ContentView |
| Enter | 메시지 전송 | InputBarView |
| Shift+Enter | 줄바꿈 | InputBarView |

---

## 컴포넌트 스타일 패턴

| 패턴 | 사용처 | 설명 |
|------|--------|------|
| 배너 (HStack + 배경색) | StatusBar, ToolConfirmation, ErrorBanner, SystemHealthBar | 화면 상단 가로 바 |
| 시트 (sheet modifier) | ContextInspector, CapabilityCatalog, SystemStatus, AgentDetail 등 | 모달 오버레이 |
| 팝오버 (조건부 VStack) | SlashCommandPopover | 입력창 위에 떠오르는 리스트 |
| 배지 (Text + padding + 배경) | StatusBar 토큰, 연속대화 배지 | 작은 정보 칩 |
| 카드 (VStack + padding + 배경 + 라운드) | CapabilityCatalog 도구 카드, 칸반 카드 | 정보 블록 |
| 분할 뷰 (HSplitView / HStack) | CapabilityCatalog (목록+상세), ToolsSettings | 좌우 2패널 |

---

*최종 업데이트: 2026-02-15 (UX-2 머지 후)*
