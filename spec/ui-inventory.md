# UI 인벤토리

> 이 문서는 Dochi의 모든 화면, 컴포넌트, 데이터 흐름을 정리한다.
> UX 설계 시 코드 대신 이 문서를 참조한다.
> **기능 머지 시 반드시 업데이트할 것.**

---

## 앱 구조

```
DochiApp (entry point)
└── ContentView (NavigationSplitView + ZStack)
    ├── [Sidebar] SidebarView
    │   ├── SidebarHeaderView — 워크스페이스/에이전트/사용자 전환
    │   ├── Section Picker — 대화 / 칸반 탭
    │   ├── ConversationListHeaderView — 검색 + 필터 + 일괄선택 버튼
    │   ├── ConversationFilterChipsView — 활성 필터 칩 (가로 스크롤)
    │   ├── ConversationListView — 즐겨찾기/폴더/미분류 섹션 대화 목록
    │   ├── BulkActionToolbarView — 일괄 선택 모드 하단 툴바
    │   ├── 폴더/태그 관리 버튼
    │   └── SidebarAuthStatusView — Supabase 로그인 상태
    ├── [Detail]
    │   ├── [대화 탭]
    │   │   ├── SystemHealthBarView — 시스템 상태 바 (모델/동기화/하트비트/토큰) [항상 표시]
    │   │   ├── StatusBarView — 상태/토큰 (처리 중에만 표시)
    │   │   ├── ToolConfirmationBannerView — 민감 도구 승인 (카운트다운 타이머, Enter/Escape 단축키)
    │   │   ├── ErrorBannerView — 에러 표시
    │   │   ├── AvatarView — 3D 아바타 (macOS 15+, 선택적)
    │   │   ├── EmptyConversationView — 빈 대화 시작 (카테고리 제안 + 카탈로그 링크 + 단축키 힌트 + 에이전트 힌트 카드)
    │   │   │   또는 ConversationView — 메시지 목록
    │   │   │       ├── MessageBubbleView — 개별 메시지 버블 (호버 시 복사 버튼)
    │   │   │       │   ├── MessageMetadataBadgeView — 모델/응답시간 배지 (assistant만, 호버 팝오버)
    │   │   │       │   └── ToolExecutionRecordCardView — 과거 도구 실행 기록 카드 (접을 수 있음)
    │   │   │       ├── ToolExecutionCardView — 실시간 도구 실행 카드 (상태별 스타일, 접을 수 있음)
    │   │   │       └── ToolChainProgressView — 도구 체인 진행 표시 (2개 이상 도구 실행 시)
    │   │   ├── Divider
    │   │   └── InputBarView — 텍스트 입력 + 마이크 + 슬래시 명령
    │   │       └── SlashCommandPopoverView — / 자동완성 팝업
    │   └── [칸반 탭]
    │       └── KanbanWorkspaceView
    │           └── KanbanBoardView → KanbanColumnView → KanbanCardView
    └── [Overlay] CommandPaletteView — ⌘K 커맨드 팔레트 (ZStack 오버레이)
```

---

## 모든 화면 목록

### 메인 뷰

| 화면 | 파일 | 접근 방법 | 설명 |
|------|------|-----------|------|
| ContentView | `Views/ContentView.swift` | 앱 시작 | 메인 레이아웃 (사이드바 + 디테일 + 커맨드 팔레트 오버레이) |
| SidebarView | `Views/ContentView.swift` | 항상 표시 | 대화 목록, 검색, 필터, 섹션 탭 |
| SidebarHeaderView | `Views/Sidebar/SidebarHeaderView.swift` | 사이드바 상단 | 워크스페이스/에이전트/사용자 드롭다운 |
| ConversationListHeaderView | `Views/Sidebar/ConversationListHeaderView.swift` | 대화 탭 상단 | 검색 + 필터 버튼 + 일괄선택 버튼 |
| ConversationFilterView | `Views/Sidebar/ConversationFilterView.swift` | 필터 버튼 팝오버 | 즐겨찾기/태그/소스 필터 |
| ConversationFilterChipsView | `Views/Sidebar/ConversationFilterView.swift` | 활성 필터 시 자동 | 활성 필터 칩 가로 스크롤, 개별 제거 |
| ConversationListView | `Views/Sidebar/ConversationListView.swift` | 대화 탭 | 즐겨찾기/폴더/미분류 섹션별 대화 목록, 드래그앤드롭 |
| BulkActionToolbarView | `Views/Sidebar/ConversationListView.swift` | 일괄선택 모드 활성 시 | N개 선택 + 폴더/태그/내보내기/즐겨찾기/삭제 |
| ConversationView | `Views/ConversationView.swift` | 대화 선택 시 | 메시지 스크롤 뷰 |
| MessageBubbleView | `Views/MessageBubbleView.swift` | 자동 | 개별 메시지 렌더링 (역할별 스타일), 호버 시 복사 버튼 오버레이 |
| EmptyConversationView | `Views/ContentView.swift` | 빈 대화 | 카테고리별 제안 프롬프트, "모든 기능 보기" 링크, 단축키 힌트, 에이전트 0개 시 생성 힌트 카드 |
| InputBarView | `Views/ContentView.swift` | 항상 표시 | 텍스트 입력, 마이크, 전송/취소 버튼, 슬래시 명령 |
| SystemHealthBarView | `Views/SystemHealthBarView.swift` | 항상 표시 | 현재 모델, 동기화 상태, 하트비트, 세션 토큰 (클릭 → 상세 시트) |
| MessageMetadataBadgeView | `Views/MessageBubbleView.swift` | assistant 메시지 자동 | 모델명·응답시간 배지, 호버 시 상세 팝오버 (토큰/프로바이더/폴백) |
| StatusBarView | `Views/ContentView.swift` | 처리 중 자동 | 상태 아이콘 + 텍스트 + 토큰 사용량 |
| ToolExecutionCardView | `Views/ToolExecutionCardView.swift` | 도구 실행 시 자동 | 접을 수 있는 실시간 도구 실행 카드 (상태 아이콘, 도구명, 입력 요약, 소요 시간, 카테고리 배지) |
| ToolExecutionRecordCardView | `Views/ToolExecutionCardView.swift` | 과거 assistant 메시지 자동 | 아카이브된 도구 실행 기록 카드 (접힌 상태 기본) |
| ToolChainProgressView | `Views/ToolChainProgressView.swift` | 도구 2개 이상 실행 시 자동 | 단계별 원형 인디케이터 + 연결선 + 전체 소요 시간 |
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
| ContextInspectorView | `Views/ContextInspectorView.swift` | 툴바 "컨텍스트" 버튼 (⌘I) | 시스템 프롬프트 / 에이전트 / 메모리 탭 |
| KeyboardShortcutHelpView | `Views/KeyboardShortcutHelpView.swift` | ⌘/ 또는 커맨드 팔레트 | 4섹션 키보드 단축키 도움말 (480x520) |
| CommandPaletteView | `Views/CommandPaletteView.swift` | ⌘K | VS Code 스타일 커맨드 팔레트 오버레이 (퍼지 검색, 그룹 섹션) |
| QuickSwitcherView | `Views/QuickSwitcherView.swift` | ⌘⇧A / ⌘⇧W / ⌘⇧U | 에이전트/워크스페이스/사용자 빠른 전환 시트 |
| TagManagementView | `Views/Sidebar/TagManagementView.swift` | 사이드바 "태그" 버튼 또는 컨텍스트 메뉴 "태그 관리" | 태그 CRUD 시트 (360x400pt), 9색 팔레트, 사용 수 |
| OnboardingView | `Views/OnboardingView.swift` | 최초 실행 시 자동 | 6단계 초기 설정 위저드 |
| WorkspaceManagementView | `Views/Sidebar/WorkspaceManagementView.swift` | SidebarHeader 메뉴 | 워크스페이스 생성/삭제 |
| AgentCreationView | `Views/Sidebar/AgentCreationView.swift` | (레거시 — AgentWizardView로 대체) | 에이전트 생성 폼 |
| AgentWizardView | `Views/Agent/AgentWizardView.swift` | SidebarHeader [+], 커맨드 팔레트, EmptyConversationView 힌트 카드 | 5단계 에이전트 생성 위저드 (560x520pt), 템플릿 선택 → 기본 정보 → 페르소나 → 모델/권한 → 요약 |
| AgentCardGridView | `Views/Agent/AgentCardGridView.swift` | 설정 > 에이전트 탭 | 2열 카드 그리드 (편집/복제/템플릿저장/삭제 메뉴), 빈 상태 안내 |
| AgentDetailView | `Views/Sidebar/AgentDetailView.swift` | SidebarHeader 메뉴, AgentCardGridView 편집 | 에이전트 편집 (설정/페르소나/메모리 3탭) |
| ExportOptionsView | `Views/ExportOptionsView.swift` | 툴바 "내보내기" 버튼 (⌘⇧E) 또는 커맨드 팔레트 | 4형식 선택(Md/JSON/PDF/텍스트), 3옵션 토글, 3액션(클립보드/공유/파일 저장), 400x480pt |
| LoginSheet | `Views/Settings/LoginSheet.swift` | 계정 설정에서 | Supabase 로그인/가입 |

### 설정 (SettingsView — 9개 탭)

| 탭 | 파일 | 내용 |
|----|------|------|
| 일반 | `Views/SettingsView.swift` 내 | 폰트, 인터랙션 모드, 웨이크워드, 아바타, Heartbeat |
| AI 모델 | `Views/SettingsView.swift` 내 | 프로바이더/모델 선택, Ollama, 태스크 라우팅, 폴백 |
| API 키 | `Views/SettingsView.swift` 내 | OpenAI/Anthropic/Z.AI/Tavily/Fal.ai 키 관리 |
| 음성 | `Views/Settings/VoiceSettingsView.swift` | TTS 프로바이더, 음성, 속도/피치 |
| 가족 | `Views/Settings/FamilySettingsView.swift` | 사용자 프로필 CRUD |
| 에이전트 | `Views/Settings/AgentSettingsView.swift` → `Views/Agent/AgentCardGridView.swift` | 에이전트 카드 그리드 (편집/복제/템플릿저장/삭제 + 위저드로 생성) |
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
| `toolExecutions` | `[ToolExecution]` | 현재 턴 도구 실행 목록 | ConversationView (ToolExecutionCardView, ToolChainProgressView) |
| `allToolCardsCollapsed` | `Bool` | 도구 카드 일괄 접기/펼치기 상태 | ⌘⇧T 토글 |

### 대화 정리 상태 (UX-4 추가)

| 프로퍼티 | 타입 | 설명 | UI 사용처 |
|----------|------|------|-----------|
| `conversationTags` | `[ConversationTag]` | 전체 태그 목록 | ConversationFilterView, TagManagementView, 컨텍스트 메뉴 |
| `conversationFolders` | `[ConversationFolder]` | 전체 폴더 목록 | ConversationListView 섹션, 컨텍스트 메뉴 |
| `isMultiSelectMode` | `Bool` | 일괄 선택 모드 활성 여부 | ConversationListView 체크박스, BulkActionToolbar |
| `selectedConversationIds` | `Set<UUID>` | 선택된 대화 ID | BulkActionToolbar 카운트, 체크박스 |

### Conversation 모델 확장 (UX-4 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `isFavorite` | `Bool` | 즐겨찾기 여부 (기본: false) |
| `tags` | `[String]` | 태그 이름 목록 (기본: []) |
| `folderId` | `UUID?` | 소속 폴더 ID (기본: nil) |

### Message.metadata (UX-2 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `provider` | `String` | LLM 프로바이더명 |
| `model` | `String` | 사용된 모델명 |
| `inputTokens` | `Int?` | 입력 토큰 |
| `outputTokens` | `Int?` | 출력 토큰 |
| `totalLatency` | `TimeInterval?` | 응답 시간 |
| `wasFallback` | `Bool` | 폴백 모델 사용 여부 |

### Message.toolExecutionRecords (UX-7 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `toolExecutionRecords` | `[ToolExecutionRecord]?` | 이 메시지의 도구 실행 이력 (하위호환: decodeIfPresent) |

ToolExecutionRecord 필드:
| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `toolName` | `String` | 도구 이름 |
| `displayName` | `String` | 도구 설명 (표시용) |
| `inputSummary` | `String` | 입력 요약 (80자 이내, 비밀값 마스킹) |
| `isError` | `Bool` | 오류 여부 |
| `durationSeconds` | `TimeInterval?` | 소요 시간 |
| `resultSummary` | `String?` | 결과 요약 |

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
InputBarView -> viewModel.sendMessage() -> interactionState=.processing
-> LLMService.stream() -> streamingText 업데이트
-> 도구 호출 시: currentToolName 설정, ToolConfirmationBanner (민감 도구)
-> 완료: interactionState=.idle, 대화에 메시지 추가
```

### 음성 메시지
```
InputBarView 마이크 -> viewModel.startListening() -> interactionState=.listening
-> SpeechService -> partialTranscript 업데이트 (StatusBar에 표시)
-> 묵음 감지 -> handleSpeechFinalResult() -> sendMessage() 흐름과 동일
```

### 워크스페이스/사용자/에이전트 전환
```
SidebarHeaderView 드롭다운 -> viewModel.switchWorkspace/User/Agent()
-> sessionContext 업데이트 -> conversations 재로드 -> toolRegistry 리셋
또는
QuickSwitcherView (⌘⇧A/W/U) -> 동일 흐름
또는
CommandPaletteView (⌘K) -> executePaletteAction() -> 동일 흐름
```

### 대화 정리 (UX-4 추가)
```
즐겨찾기: 컨텍스트 메뉴 -> viewModel.toggleFavorite() -> 대화 저장 -> 목록 리로드
태그: 컨텍스트 메뉴/TagManagementView -> viewModel.toggleTagOnConversation() -> 대화 저장
폴더: 컨텍스트 메뉴/드래그앤드롭 -> viewModel.moveConversationToFolder() -> 대화 저장
일괄 선택: ⌘⇧M -> viewModel.toggleMultiSelectMode() -> BulkActionToolbar 표시
  -> bulkDelete/bulkMoveToFolder/bulkSetFavorite/bulkAddTag
필터: 필터 버튼 -> ConversationFilterView 팝오버 -> filter 바인딩 -> filteredConversations 업데이트
```

### 에이전트 생성 (UX-6 추가)
```
SidebarHeaderView [+] / 커맨드 팔레트 "새 에이전트 생성" / EmptyConversationView 힌트 카드
  -> AgentWizardView 시트 열기
  -> Step 0: 템플릿 선택 (5종 기본 + blank + 커스텀)
  -> Step 1: 이름 + 웨이크워드 + 설명 (이름 중복 검사)
  -> Step 2: 페르소나 (TextEditor + 추천 칩)
  -> Step 3: 모델 선택 + 권한 토글 (safe/sensitive/restricted)
  -> Step 4: 요약 확인 + "커스텀 템플릿으로 저장" 체크박스
  -> "생성" -> contextService.saveAgentConfig() + 페르소나 저장 + switchAgent()
설정 > 에이전트 탭 -> AgentCardGridView (2열 카드 그리드)
  -> 더보기 메뉴: 편집(AgentDetailView) / 복제 / 템플릿으로 저장 / 삭제
```

### 도구 실행 피드백 (UX-7 추가)
```
도구 실행 시작: processLLMLoop() -> ToolExecution 생성 -> toolExecutions 배열에 추가
  -> ConversationView에서 ToolExecutionCardView로 실시간 표시 (상태: running/blue/스피너)
  -> 완료/실패 시: execution.complete()/fail() -> 카드 상태 갱신 (success/green, error/red)
  -> 도구 2개 이상: ToolChainProgressView 자동 표시 (단계별 인디케이터 + 전체 소요 시간)
턴 완료 시: toolExecutions -> ToolExecutionRecord로 변환 -> Message.toolExecutionRecords에 아카이브
과거 메시지 표시: MessageBubbleView에서 ToolExecutionRecordCardView (접힌 상태 기본)
민감 도구 확인: ToolConfirmationBannerView + 30초 카운트다운 타이머 + Enter(허용)/Escape(거부) 단축키
```

### 내보내기/공유 (UX-5 추가)
```
빠른 내보내기: ⌘E -> viewModel.exportConversation(format: .markdown) -> NSSavePanel
내보내기 시트: ⌘⇧E / 툴바 / 커맨드 팔레트 -> ExportOptionsView 시트
  -> 형식 선택 (Markdown/JSON/PDF/텍스트)
  -> 옵션 (시스템 메시지/도구 호출/메타데이터 포함 여부)
  -> 클립보드 복사 / macOS 공유 / 파일 저장
메시지 복사: 호버 -> 복사 버튼 클릭 -> NSPasteboard -> 체크마크 피드백 1초
사이드바 내보내기: 컨텍스트 메뉴 -> Md/JSON/PDF/텍스트 파일 저장 또는 클립보드 복사
일괄 내보내기: BulkActionToolbar 내보내기 메뉴 -> 개별 파일 / 합치기(Markdown)
```

---

## 키보드 단축키

| 단축키 | 동작 | 위치 |
|--------|------|------|
| ⌘K | 커맨드 팔레트 열기/닫기 | ContentView (onKeyPress) |
| ⌘/ | 키보드 단축키 도움말 | ContentView (hidden button) |
| ⌘N | 새 대화 | SidebarView 툴바 |
| ⌘1~9 | N번째 대화 선택 | ContentView (onKeyPress) |
| ⌘E | 현재 대화 빠른 내보내기 (Markdown) | ContentView (hidden button) |
| ⌘⇧E | 내보내기 옵션 시트 | ContentView 툴바 |
| ⌘I | 컨텍스트 인스펙터 | ContentView 툴바 |
| ⌘, | 설정 | macOS 자동 (Settings scene) |
| ⌘⇧S | 시스템 상태 시트 | ContentView 툴바 |
| ⌘⇧F | 기능 카탈로그 | ContentView 툴바 |
| ⌘⇧A | 에이전트 빠른 전환 | ContentView (hidden button) |
| ⌘⇧W | 워크스페이스 빠른 전환 | ContentView (hidden button) |
| ⌘⇧U | 사용자 빠른 전환 | ContentView (hidden button) |
| ⌘⇧K | 칸반/대화 전환 | ContentView (onKeyPress) |
| ⌘⇧L | 즐겨찾기 필터 토글 | ContentView (onKeyPress) |
| ⌘⇧M | 일괄 선택 모드 토글 | ContentView (onKeyPress) |
| ⌘⇧T | 도구 카드 일괄 접기/펼치기 | ContentView (hidden button) |
| Escape | 요청 취소 / 확인 배너 거부 / 팔레트 닫기 | ContentView (onKeyPress) |
| Enter | 확인 배너 허용 / 메시지 전송 | ContentView (onKeyPress) / InputBarView |
| ⇧Enter | 줄바꿈 | InputBarView |

---

## 컴포넌트 스타일 패턴

| 패턴 | 사용처 | 설명 |
|------|--------|------|
| 배너 (HStack + 배경색) | StatusBar, ToolConfirmation, ErrorBanner, SystemHealthBar | 화면 상단 가로 바 |
| 시트 (sheet modifier) | ContextInspector, CapabilityCatalog, SystemStatus, AgentDetail, AgentWizard, ShortcutHelp, QuickSwitcher, TagManagement, ExportOptions 등 | 모달 오버레이 |
| 오버레이 (ZStack) | CommandPaletteView | 앱 위에 떠오르는 팔레트 (배경 딤 + 검색 + 목록) |
| 팝오버 (popover modifier) | SlashCommandPopover, ConversationFilterView | 컨트롤 근처에 떠오르는 패널 |
| 배지 (Text + padding + 배경) | StatusBar 토큰, 연속대화 배지, 태그 칩 | 작은 정보 칩 |
| 카드 (VStack + padding + 배경 + 라운드) | CapabilityCatalog 도구 카드, 칸반 카드, ExportOptions 형식 카드 | 정보 블록 |
| 호버 오버레이 (overlay + onHover) | MessageBubbleView 복사 버튼 | 호버 시 나타나는 액션 버튼 |
| 분할 뷰 (HSplitView / HStack) | CapabilityCatalog (목록+상세), ToolsSettings | 좌우 2패널 |
| 키캡 (Text + 둥근 테두리) | KeyboardShortcutHelpView | 단축키 키 표시 |
| FlowLayout (커스텀 Layout) | ConversationFilterView 태그 칩 | 줄바꿈 가능한 가로 배치 |
| 접을 수 있는 카드 (VStack + Button + chevron) | ToolExecutionCardView, ToolExecutionRecordCardView | 상태별 색상, 클릭 접기/펼치기 |
| 진행 체인 (HStack + Circle + Rectangle) | ToolChainProgressView | 단계별 아이콘 + 연결선 |

---

## 빈 상태 (Empty States)

| 상황 | 메시지 | 위치 |
|------|--------|------|
| 대화 없음 | 카테고리별 제안 프롬프트 | EmptyConversationView |
| 폴더 안 대화 0개 | "대화를 여기로 드래그하세요" | ConversationListView 폴더 섹션 |
| 태그 0개 | "태그를 추가하여 대화를 분류하세요" | TagManagementView |
| 필터 결과 0개 | "조건에 맞는 대화가 없습니다" + 필터 초기화 | ConversationListView |
| 에이전트 0개 | "에이전트가 없습니다" + 생성 버튼 | AgentCardGridView |
| 에이전트 0개 (대화) | 에이전트 생성 힌트 카드 | EmptyConversationView |

---

## 저장 파일

| 파일 | 경로 | 설명 |
|------|------|------|
| 시스템 프롬프트 | `~/Library/Application Support/Dochi/system_prompt.md` | 기본 시스템 프롬프트 |
| 프로필 | `~/Library/Application Support/Dochi/profiles.json` | 사용자 프로필 |
| 대화 | `~/Library/Application Support/Dochi/conversations/{id}.json` | 개별 대화 |
| 사용자 메모리 | `~/Library/Application Support/Dochi/memory/{userId}.md` | 사용자별 메모리 |
| 대화 태그 | `~/Library/Application Support/Dochi/conversation_tags.json` | 태그 정의 |
| 대화 폴더 | `~/Library/Application Support/Dochi/conversation_folders.json` | 폴더 정의 |
| 칸반 보드 | `~/Library/Application Support/Dochi/kanban/{boardId}.json` | 칸반 데이터 |
| 워크스페이스 | `~/Library/Application Support/Dochi/workspaces/{wsId}/` | 워크스페이스 데이터 |
| 에이전트 템플릿 | `~/Library/Application Support/Dochi/agent_templates.json` | 커스텀 에이전트 템플릿 |

---

## 모델

### AgentTemplate (UX-6 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `id` | `String` | 고유 ID |
| `name` | `String` | 템플릿 이름 |
| `icon` | `String` | SF Symbols 아이콘 |
| `description` | `String` | 짧은 설명 |
| `detailedDescription` | `String` | 상세 설명 |
| `suggestedPersona` | `String` | 추천 페르소나 |
| `suggestedModel` | `String?` | 추천 모델 |
| `suggestedPermissions` | `[String]` | 추천 권한 |
| `suggestedTools` | `[String]` | 추천 도구 |
| `isBuiltIn` | `Bool` | 기본 제공 여부 |
| `accentColor` | `String` | 강조 색상 |

기본 제공: coding-assistant, researcher, scheduler, writer, kanban-manager + blank

---

*최종 업데이트: 2026-02-15 (UX-7 머지 후)*
