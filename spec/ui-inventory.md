# UI 인벤토리

> 이 문서는 Dochi의 모든 화면, 컴포넌트, 데이터 흐름을 정리한다.
> UX 설계 시 코드 대신 이 문서를 참조한다.
> **기능 머지 시 반드시 업데이트할 것.**

---

## 앱 구조

```
DochiApp (entry point)
├── SpotlightIndexer (CoreSpotlight 인덱싱 서비스) (H-4)
│   ├── indexConversation/removeConversation — 대화 인덱싱/제거
│   ├── indexMemory/removeMemory — 메모리 인덱싱/제거
│   ├── rebuildAllIndices — 전체 재구축 (async, 진행률)
│   ├── clearAllIndices — 모든 인덱스 삭제
│   └── parseDeepLink(url:) — dochi:// URL 파싱
├── NotificationManager (UNUserNotificationCenterDelegate) (H-3)
│   ├── 4 카테고리: dochi-calendar (답장+열기), dochi-kanban (열기), dochi-reminder (답장+열기), dochi-memory (열기)
│   ├── 3 액션: reply (텍스트 입력), open-app (포그라운드), dismiss (파괴적)
│   └── 콜백: onReply → ViewModel.handleNotificationReply, onOpenApp → ViewModel.handleNotificationOpenApp
├── MenuBarManager (NSStatusItem + NSPopover) (H-1)
│   └── MenuBarPopoverView — 메뉴바 퀵 액세스 팝업 (380x480pt)
│       ├── 헤더 (36pt) — 에이전트 아이콘+이름, 워크스페이스명, 닫기 버튼
│       ├── 대화 영역 — 최근 메시지 10개 (컴팩트 버블), 스트리밍 표시
│       ├── 빈 상태 — 도치 아이콘 + "무엇이든 물어보세요" + 제안 칩 3개
│       ├── 입력바 (44pt) — TextField + 전송/중지 버튼
│       └── 푸터 (30pt) — 모델명, 새 대화 버튼, 메인 앱 열기 버튼
└── ContentView (NavigationSplitView + ZStack)
    ├── [Sidebar] SidebarView
    │   ├── SidebarHeaderView — 워크스페이스/에이전트/사용자 전환
    │   ├── Section Picker — 대화 / 칸반 탭
    │   ├── ConversationListHeaderView — 검색 + 필터 + 일괄선택 버튼
    │   ├── ConversationFilterChipsView — 활성 필터 칩 (가로 스크롤)
    │   ├── ConversationListView — 즐겨찾기/폴더/미분류 섹션 대화 목록
    │   ├── BulkActionToolbarView — 일괄 선택 모드 하단 툴바
    │   ├── 폴더/태그 관리 버튼
    │   └── SidebarAuthStatusView — Supabase 로그인 상태 + SyncState 표시 (G-3)
    ├── [Detail]
    │   ├── [대화 탭]
    │   │   ├── SystemHealthBarView — 시스템 상태 바 (개별 클릭 가능: 모델→QuickModel팝오버/동기화(SyncState 기반 인디케이터, 충돌→SyncConflictListView)/하트비트/토큰→상태시트, 로컬 프로바이더 아이콘, 오프라인 폴백 표시) [항상 표시] (G-3 업데이트)
    │   │   ├── StatusBarView — 상태/토큰 (처리 중에만 표시)
    │   │   ├── ToolConfirmationBannerView — 민감 도구 승인 (카운트다운 타이머, Enter/Escape 단축키)
    │   │   ├── OfflineFallbackBannerView — 오프라인 폴백 상태 배너 (로컬 모델 전환 알림 + 복구 버튼) (G-1)
    │   │   ├── TTSFallbackBannerView — TTS 오프라인 폴백 배너 (로컬 TTS 전환 알림 + 복구 버튼) (G-2)
    │   │   ├── SystemPromptBannerView — 시스템 프롬프트 접기/펼치기 배너 (UX-8)
    │   │   ├── MemoryConsolidationBannerView — 메모리 자동 정리 상태 배너 (analyzing/completed/conflict/failed, 15초 후 자동 소멸) (I-2)
    │   │   ├── ErrorBannerView — 에러 표시
    │   │   ├── AvatarView — 3D 아바타 (macOS 15+, 선택적)
    │   │   ├── EmptyConversationView — 빈 대화 시작 (카테고리 제안 + 카탈로그 링크 + 단축키 힌트 + 에이전트 힌트 카드 + 투어 리마인더 + 첫 대화 힌트)
    │   │   │   또는 ConversationView — 메시지 목록
    │   │   │       ├── MessageBubbleView — 개별 메시지 버블 (호버 시 복사 버튼)
    │   │   │       │   ├── MessageMetadataBadgeView — 모델/응답시간 배지 (assistant만, 호버 팝오버)
    │   │   │       │   ├── MemoryReferenceBadgeView — 메모리 참조 배지 (assistant만, 호버 팝오버) (UX-8)
    │   │   │       │   └── ToolExecutionRecordCardView — 과거 도구 실행 기록 카드 (접을 수 있음)
    │   │   │       ├── ToolExecutionCardView — 실시간 도구 실행 카드 (상태별 스타일, 접을 수 있음)
    │   │   │       └── ToolChainProgressView — 도구 체인 진행 표시 (2개 이상 도구 실행 시)
    │   │   ├── Divider
    │   │   └── InputBarView — 텍스트 입력 + 마이크 + 슬래시 명령
    │   │       └── SlashCommandPopoverView — / 자동완성 팝업
    │   └── [칸반 탭]
    │       └── KanbanWorkspaceView
    │           └── KanbanBoardView → KanbanColumnView → KanbanCardView
    ├── [Inspector] MemoryPanelView — 메모리 인스펙터 패널 (⌘I 토글) (UX-8)
    │   └── MemoryNodeView — 계층별 메모리 노드 (접기/펼치기 + 인라인 편집)
    ├── [Overlay] CommandPaletteView — ⌘K 커맨드 팔레트 (ZStack 오버레이)
    ├── [Overlay] SyncToastContainerView — 동기화 이벤트 토스트 (우측 하단, 메모리 토스트 위) (G-3)
    └── [Overlay] MemoryToastContainerView — 메모리 저장 토스트 (우측 하단) (UX-8)
```

---

## 모든 화면 목록

### 메인 뷰

| 화면 | 파일 | 접근 방법 | 설명 |
|------|------|-----------|------|
| MenuBarPopoverView | `Views/MenuBarPopoverView.swift` | 메뉴바 아이콘 클릭 또는 Cmd+Shift+D (글로벌) | 메뉴바 퀵 액세스 팝업 (380x480pt): 헤더+대화+입력+푸터 (H-1) |
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
| EmptyConversationView | `Views/ContentView.swift` | 빈 대화 | 카테고리별 제안 프롬프트, "모든 기능 보기" 링크, 단축키 힌트, 에이전트 0개 시 생성 힌트 카드, 투어 리마인더 배너, 첫 대화 힌트 버블 |
| InputBarView | `Views/ContentView.swift` | 항상 표시 | 텍스트 입력, 마이크, 전송/취소 버튼, 슬래시 명령 |
| SystemHealthBarView | `Views/SystemHealthBarView.swift` | 항상 표시 | 4개 독립 버튼: 모델(→QuickModelPopover), 동기화(SyncState 기반: idle→초록/syncing→파란pulse/conflict→주황+건수→SyncConflictListView/error→빨강/offline→회색), 하트비트(→상태시트), 토큰+비용(→상태시트, "1.2K 토큰 · $0.03" 형식). IndicatorButtonStyle 호버 (G-3, G-4 업데이트) |
| SyncToastView | `Views/SyncToastView.swift` | 동기화 이벤트 발생 시 자동 | 우측 하단 토스트: 방향 아이콘(수신↓/발신↑) + 엔티티 타입 + 제목 + 충돌 여부, 4초 자동 fade (G-3) |
| SyncToastContainerView | `Views/SyncToastView.swift` | 자동 | 여러 동기화 토스트 스택 관리 (G-3) |
| MessageMetadataBadgeView | `Views/MessageBubbleView.swift` | assistant 메시지 자동 | 모델명·응답시간 배지, 호버 시 상세 팝오버 (토큰/프로바이더/폴백) |
| StatusBarView | `Views/ContentView.swift` | 처리 중 자동 | 상태 아이콘 + 텍스트 + 토큰 사용량 |
| ToolExecutionCardView | `Views/ToolExecutionCardView.swift` | 도구 실행 시 자동 | 접을 수 있는 실시간 도구 실행 카드 (상태 아이콘, 도구명, 입력 요약, 소요 시간, 카테고리 배지) |
| ToolExecutionRecordCardView | `Views/ToolExecutionCardView.swift` | 과거 assistant 메시지 자동 | 아카이브된 도구 실행 기록 카드 (접힌 상태 기본) |
| ToolChainProgressView | `Views/ToolChainProgressView.swift` | 도구 2개 이상 실행 시 자동 | 단계별 원형 인디케이터 + 연결선 + 전체 소요 시간 |
| AvatarView | `Views/AvatarView.swift` | 설정 활성화 시 | VRM 3D 아바타 (RealityKit, macOS 15+) |
| MemoryPanelView | `Views/MemoryPanelView.swift` | 툴바 "메모리" 버튼 (⌘I) | 우측 인스펙터: 메모리 계층 트리 (5단계), 인라인 편집, 글자수/토큰 표시 |
| MemoryNodeView | `Views/MemoryPanelView.swift` | MemoryPanelView 내 자동 | 접기/펼치기 카드: 아이콘+제목+글자수+미리보기 / TextEditor+저장 |
| SystemPromptBannerView | `Views/SystemPromptBannerView.swift` | 대화 상단 항상 표시 | 접힌: 미리보기+편집 / 펼침: TextEditor+저장, UserDefaults 상태 기억 |
| MemoryToastView | `Views/MemoryToastView.swift` | save_memory/update_memory 도구 실행 시 자동 | 우측 하단 토스트: scope+action+미리보기+"보기" 버튼, 5초 자동 fade |
| MemoryToastContainerView | `Views/MemoryToastView.swift` | 자동 | 여러 토스트 스택 관리 |
| MemoryReferenceBadgeView | `Views/MemoryReferenceBadgeView.swift` | assistant 메시지 자동 | "메모리 N계층" 배지, 호버 시 계층별 글자수 팝오버 |

### 칸반

| 화면 | 파일 | 접근 방법 | 설명 |
|------|------|-----------|------|
| KanbanWorkspaceView | `Views/KanbanWorkspaceView.swift` | 칸반 탭 | 보드 목록 + 보드 선택 |
| KanbanBoardView | `Views/KanbanBoardView.swift` | 보드 선택 | 컬럼 + 카드 (드래그 지원) |

### 시트/모달

| 화면 | 파일 | 접근 방법 | 설명 |
|------|------|-----------|------|
| SystemStatusSheetView | `Views/SystemStatusSheetView.swift` | 툴바 "상태" 버튼 (⌘⇧S) 또는 SystemHealthBar 클릭 | 3탭 상세: LLM 교환 이력(세션 추정 비용 표시+"상세 대시보드 열기" 링크 G-4), 하트비트 틱 기록, 클라우드 동기화(상태 헤더+동기화 대상 요약+충돌 섹션+히스토리+수동/전체 동기화 버튼) (G-3 재설계) |
| CapabilityCatalogView | `Views/CapabilityCatalogView.swift` | 툴바 "기능" 버튼 (⌘⇧F) | 전체 도구 그룹별 카탈로그 |
| ContextInspectorView | `Views/ContextInspectorView.swift` | ⌘⌥I 또는 커맨드 팔레트 | 시스템 프롬프트 / 에이전트 / 메모리 탭 (시트) |
| KeyboardShortcutHelpView | `Views/KeyboardShortcutHelpView.swift` | ⌘/ 또는 커맨드 팔레트 | 4섹션 키보드 단축키 도움말 (480x520) |
| CommandPaletteView | `Views/CommandPaletteView.swift` | ⌘K | VS Code 스타일 커맨드 팔레트 오버레이 (퍼지 검색, 그룹 섹션) |
| QuickSwitcherView | `Views/QuickSwitcherView.swift` | ⌘⇧A / ⌘⇧W / ⌘⇧U | 에이전트/워크스페이스/사용자 빠른 전환 시트 |
| TagManagementView | `Views/Sidebar/TagManagementView.swift` | 사이드바 "태그" 버튼 또는 컨텍스트 메뉴 "태그 관리" | 태그 CRUD 시트 (360x400pt), 9색 팔레트, 사용 수 |
| QuickModelPopoverView | `Views/QuickModelPopoverView.swift` | SystemHealthBar 모델 클릭 또는 ⌘⇧M | 프로바이더 선택 (클라우드/로컬 그룹) + 모델 목록 (메타데이터 표시) + 자동 라우팅 토글 + 로컬 서버 연결 인디케이터 + 오프라인 폴백 정보 (320pt 폭) |
| OfflineFallbackBannerView | `Views/ContentView.swift` 내 | 오프라인 폴백 발동 시 자동 표시 | 오프라인 전환 안내 + 모델명 + "원래 모델로 복구" 버튼 (G-1) |
| TTSFallbackBannerView | `Views/ContentView.swift` 내 | TTS 오프라인 폴백 발동 시 자동 표시 | TTS 전환 안내 + 프로바이더명 + "원래 TTS로 복구" 버튼 (G-2) |
| ONNXModelManagerView | `Views/Settings/ONNXModelManagerView.swift` | VoiceSettingsView 내 ONNX 선택 시 인라인 | ONNX 모델 카탈로그, 다운로드/삭제, 설치된 모델 Picker (G-2) |
| OnboardingView | `Views/OnboardingView.swift` | 최초 실행 시 자동 | 6단계 초기 설정 위저드 + 기능 투어 연결 |
| FeatureTourView | `Views/Guide/FeatureTourViews.swift` | 온보딩 완료 후 / 설정 > 일반 > 가이드 / 커맨드 팔레트 | 4단계 기능 투어 (개요/대화/에이전트·워크스페이스/단축키) |
| WorkspaceManagementView | `Views/Sidebar/WorkspaceManagementView.swift` | SidebarHeader 메뉴 | 워크스페이스 생성/삭제 |
| AgentCreationView | `Views/Sidebar/AgentCreationView.swift` | (레거시 — AgentWizardView로 대체) | 에이전트 생성 폼 |
| AgentWizardView | `Views/Agent/AgentWizardView.swift` | SidebarHeader [+], 커맨드 팔레트, EmptyConversationView 힌트 카드 | 5단계 에이전트 생성 위저드 (560x520pt), 템플릿 선택 → 기본 정보 → 페르소나 → 모델/권한 → 요약 |
| AgentCardGridView | `Views/Agent/AgentCardGridView.swift` | 설정 > 에이전트 탭 | 2열 카드 그리드 (편집/복제/템플릿저장/삭제 메뉴), 빈 상태 안내 |
| AgentDetailView | `Views/Sidebar/AgentDetailView.swift` | SidebarHeader 메뉴, AgentCardGridView 편집 | 에이전트 편집 (설정/페르소나/메모리 3탭) |
| ExportOptionsView | `Views/ExportOptionsView.swift` | 툴바 "내보내기" 버튼 (⌘⇧E) 또는 커맨드 팔레트 | 4형식 선택(Md/JSON/PDF/텍스트), 3옵션 토글, 3액션(클립보드/공유/파일 저장), 400x480pt |
| SyncConflictListView | `Views/SyncConflictListView.swift` | SystemHealthBar 충돌 클릭 또는 AccountSettings "해결하기" | 동기화 충돌 목록 시트 (600x500pt), 일괄 해결 (로컬/원격), 개별 클릭→SyncConflictDetailView (G-3) |
| SyncConflictDetailView | `Views/SyncConflictDetailView.swift` | SyncConflictListView 항목 클릭 | 좌우 비교 (로컬 vs 원격), 메모리 충돌 시 수동 병합 TextEditor (600x500pt) (G-3) |
| InitialSyncWizardView | `Views/InitialSyncWizardView.swift` | AccountSettingsView "초기 업로드" | 3단계 위저드: 안내→진행률→완료 (480x420pt) (G-3) |
| LoginSheet | `Views/Settings/LoginSheet.swift` | 계정 설정에서 | Supabase 로그인/가입 |

### 설정 (SettingsView — NavigationSplitView, 15섹션 6그룹) (UX-10 리디자인, G-4, H-2, I-1 추가)

SettingsView는 좌측 사이드바(SettingsSidebarView) + 우측 콘텐츠의 NavigationSplitView 구조.
사이드바: 검색 필드 + 6개 그룹별 섹션 목록 (호버/선택 하이라이트).
창 크기: 780x540pt (이상), 680x440pt (최소). 사이드바 폭 180pt.

| 그룹 | 섹션 (rawValue) | 아이콘 | 파일 | 내용 |
|------|----------------|--------|------|------|
| AI | AI 모델 (`ai-model`) | brain | `Views/SettingsView.swift` 내 ModelSettingsView | 프로바이더/모델 선택 (클라우드/로컬 그룹), Ollama 설정, LM Studio 설정, 오프라인 폴백, 태스크 라우팅 |
| AI | API 키 (`api-key`) | key | `Views/SettingsView.swift` 내 APIKeySettingsView | OpenAI/Anthropic/Z.AI/Tavily/Fal.ai 키 관리 |
| AI | 사용량 (`usage`) | chart.bar.xaxis | `Views/Settings/UsageDashboardView.swift` | 기간별 사용량 (오늘/주/월/전체), 요약 카드 (교환수/토큰/비용), Swift Charts 일별 차트 (비용/토큰 모드), 모델별/에이전트별 분류 테이블, 예산 설정 (월 한도/알림/차단) (G-4) |
| AI | 문서 검색 (`rag`) | doc.text.magnifyingglass | `Views/Settings/RAGSettingsView.swift` | RAG 활성화, 임베딩 설정 (프로바이더/모델), 검색 설정 (자동/topK/최소유사도), 청킹 설정 (크기/오버랩), 문서 통계, 유지보수 (재인덱싱/초기화) (I-1) |
| AI | 메모리 정리 (`memory`) | brain.head.profile | `Views/Settings/MemorySettingsView.swift` | 자동 정리 활성화, 최소 메시지 수, 정리 모델 (경량/기본), 배너 표시, 크기 한도 (개인/워크스페이스/에이전트), 자동 아카이브, 변경 이력 (I-2) |
| 음성 | 음성 합성 (`voice`) | speaker.wave.2 | `Views/Settings/VoiceSettingsView.swift` | TTS 프로바이더 (시스템/Google Cloud/ONNX), 음성, 속도/피치, ONNX 모델 관리 (ONNXModelManagerView), 디퓨전 스텝, TTS 오프라인 폴백 |
| 일반 | 인터페이스 (`interface`) | paintbrush | `Views/SettingsView.swift` 내 InterfaceSettingsContent | 폰트, 인터랙션 모드, 아바타, Spotlight 검색 (H-4) |
| 일반 | 웨이크워드 (`wake-word`) | waveform | `Views/SettingsView.swift` 내 WakeWordSettingsContent | 웨이크워드 설정 |
| 일반 | 하트비트 (`heartbeat`) | heart.circle | `Views/SettingsView.swift` 내 HeartbeatSettingsContent | Heartbeat 간격, 캘린더/칸반/미리알림 체크, 알림 센터 설정 (권한 상태, 소리/답장 토글, 카테고리별 알림 토글) (H-3) |
| 사람 | 가족 (`family`) | person.2 | `Views/Settings/FamilySettingsView.swift` | 사용자 프로필 CRUD |
| 사람 | 에이전트 (`agent`) | person.crop.rectangle | `Views/Settings/AgentSettingsView.swift` → `Views/Agent/AgentCardGridView.swift` | 에이전트 카드 그리드 |
| 연결 | 도구 (`tools`) | wrench.and.screwdriver | `Views/Settings/ToolsSettingsView.swift` | 도구 브라우저 (검색/필터/상세) |
| 연결 | 통합 (`integrations`) | puzzlepiece | `Views/Settings/IntegrationsSettingsView.swift` | 텔레그램, MCP, 채팅 매핑 |
| 연결 | 단축어 (`shortcuts`) | square.grid.3x3.square | `Views/Settings/ShortcutsSettingsView.swift` | Apple Shortcuts/Siri 연동 상태, 4개 액션 카드, 실행 기록 (H-2) |
| 연결 | 계정 (`account`) | person.crop.circle | `Views/Settings/AccountSettingsView.swift` | Supabase 인증, 동기화(SyncState 표시+충돌 건수+수동/전체 동기화), 동기화 설정(자동/실시간/대상 선택/충돌 전략), 데이터 관리(초기 업로드) (G-3 확장) |
| 도움말 | 가이드 (`guide`) | play.rectangle | `Views/SettingsView.swift` 내 GuideSettingsContent | 투어/힌트 관리 |

지원 파일:
- `Views/Settings/SettingsSidebarView.swift` — SettingsSection enum, SettingsSectionGroup enum, SettingsSidebarView, SettingsSidebarRow
- `Models/UsageModels.swift` — UsageEntry, DailyUsageRecord, MonthlyUsageFile, MonthlyUsageSummary, ModelPricingTable (G-4)
- `Services/UsageStore.swift` — UsageStore (파일 기반 영구 저장, 5초 디바운스) (G-4)
- `Services/Protocols/UsageStoreProtocol.swift` — UsageStoreProtocol (G-4)
- `App/NotificationManager.swift` — NotificationManager (UNUserNotificationCenterDelegate, 알림 카테고리/액션 등록, 카테고리별 알림 발송, 사용자 응답 콜백) (H-3)
- `App/DochiAppIntents.swift` — 4개 AppIntent (AskDochiIntent, AddMemoIntent, CreateKanbanCardIntent, TodayBriefingIntent) (H-2)
- `App/DochiShortcuts.swift` — AppShortcutsProvider, Siri 문구 등록 (H-2)
- `Services/ShortcutService.swift` — DochiShortcutService 싱글턴, ShortcutError (H-2)
- `Models/ShortcutExecutionLog.swift` — ShortcutExecutionLog 모델, ShortcutExecutionLogStore (H-2)
- `Services/SpotlightIndexer.swift` — SpotlightIndexer (CoreSpotlight 인덱싱 + 딥링크 파싱) (H-4)
- `Services/Protocols/SpotlightIndexerProtocol.swift` — SpotlightIndexerProtocol (H-4)
- `Services/RAG/ChunkSplitter.swift` — 텍스트 청크 분할 (마크다운 섹션/문단, 오버랩) (I-1)
- `Services/RAG/VectorStore.swift` — SQLite 기반 벡터 저장소 (cosine similarity 검색) (I-1)
- `Services/RAG/EmbeddingService.swift` — OpenAI text-embedding API 호출 (I-1)
- `Services/RAG/DocumentIndexer.swift` — 문서 파싱/청킹/임베딩/인덱싱 오케스트레이터 (I-1)
- `Models/RAGModels.swift` — RAGDocument, RAGReference, RAGContextInfo, RAGIndexingState 등 (I-1)
- `Views/RAG/DocumentLibraryView.swift` — 문서 라이브러리 시트 (파일/폴더 추가, 인덱싱) (I-1)
- `Views/RAGContextBadgeView.swift` — assistant 메시지 "문서 N건 참조" 배지 (I-1)

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
| `metricsCollector` | `MetricsCollector` | LLM 교환 메트릭 수집, 세션 비용 추적, UsageStore 영구 기록, 예산 알림 (G-4) | SystemHealthBarView, SystemStatusSheetView, UsageDashboardView |
| `toolExecutions` | `[ToolExecution]` | 현재 턴 도구 실행 목록 | ConversationView (ToolExecutionCardView, ToolChainProgressView) |
| `allToolCardsCollapsed` | `Bool` | 도구 카드 일괄 접기/펼치기 상태 | ⌘⇧T 토글 |
| `memoryToastEvents` | `[MemoryToastEvent]` | 메모리 저장 토스트 이벤트 큐 | MemoryToastContainerView |
| `syncEngine` | `SyncEngine?` | 동기화 엔진 (G-3) | SystemHealthBarView, CloudSyncTabView, AccountSettingsView, SyncToastContainerView |
| `spotlightIndexer` | `SpotlightIndexerProtocol?` | Spotlight 인덱싱 서비스 (H-4) | InterfaceSettingsContent (Spotlight 섹션) |

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

### Message.memoryContextInfo (UX-8 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `memoryContextInfo` | `MemoryContextInfo?` | 이 응답 생성 시 사용된 메모리 계층 정보 (하위호환: decodeIfPresent) |

MemoryContextInfo 필드:
| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `systemPromptLength` | `Int` | 시스템 프롬프트 글자수 |
| `agentPersonaLength` | `Int` | 에이전트 페르소나 글자수 |
| `workspaceMemoryLength` | `Int` | 워크스페이스 메모리 글자수 |
| `agentMemoryLength` | `Int` | 에이전트 메모리 글자수 |
| `personalMemoryLength` | `Int` | 개인 메모리 글자수 |

### Message.ragContextInfo (I-1 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `ragContextInfo` | `RAGContextInfo?` | 이 응답 생성 시 참조된 RAG 문서 정보 (하위호환: decodeIfPresent) |

RAGContextInfo 필드:
| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `references` | `[RAGReference]` | 참조된 문서 목록 |
| `totalCharsInjected` | `Int` | 시스템 프롬프트에 주입된 총 글자수 |

RAGReference 필드:
| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `documentId` | `String` | 문서 UUID |
| `fileName` | `String` | 파일명 |
| `sectionTitle` | `String?` | 섹션 제목 |
| `similarity` | `Double` | 코사인 유사도 |
| `snippetPreview` | `String` | 참조 내용 미리보기 |

### MemoryToastEvent (UX-8 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `id` | `UUID` | 이벤트 ID |
| `scope` | `Scope` | workspace/personal/agent |
| `action` | `Action` | saved/updated |
| `contentPreview` | `String` | 저장 내용 미리보기 (80자 이내) |
| `timestamp` | `Date` | 발생 시각 |

### SyncEngine 상태 (G-3 추가)

| 프로퍼티 | 타입 | 설명 | UI 사용처 |
|----------|------|------|-----------|
| `syncState` | `SyncState` | idle/syncing/conflict/error/offline/disabled | SystemHealthBarView, SidebarAuthStatusView, CloudSyncTabView |
| `syncProgress` | `SyncProgress` | 동기화 진행률 | InitialSyncWizardView, CloudSyncTabView |
| `syncConflicts` | `[SyncConflict]` | 미해결 충돌 목록 | SyncConflictListView, CloudSyncTabView |
| `lastSuccessfulSync` | `Date?` | 마지막 동기화 시각 | CloudSyncTabView, AccountSettingsView |
| `pendingLocalChanges` | `Int` | 오프라인 큐 대기 건수 | AccountSettingsView |
| `syncHistory` | `[SyncHistoryEntry]` | 최근 20건 동기화 이력 | CloudSyncTabView |
| `syncToastEvents` | `[SyncToastEvent]` | 동기화 토스트 이벤트 큐 | SyncToastContainerView |

### SyncToastEvent (G-3 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `id` | `UUID` | 이벤트 ID |
| `direction` | `SyncDirection` | incoming/outgoing |
| `entityType` | `SyncEntityType` | conversation/memory/kanban/profile |
| `entityTitle` | `String` | 엔티티 이름 |
| `isConflict` | `Bool` | 충돌 여부 |
| `timestamp` | `Date` | 발생 시각 |

### TTS 폴백 상태 (G-2 추가)

| 프로퍼티 | 타입 | 설명 | UI 사용처 |
|----------|------|------|-----------|
| `isTTSFallbackActive` | `Bool` | TTS 오프라인 폴백 활성 여부 | TTSFallbackBannerView |
| `ttsFallbackProviderName` | `String?` | 폴백된 TTS 프로바이더 이름 | TTSFallbackBannerView |

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
| 음성 | `ttsProvider`, `wakeWordEnabled`, `wakeWord`, `sttSilenceTimeout`, `onnxModelId`, `ttsOfflineFallbackEnabled`, `ttsDiffusionSteps` |
| 통합 | `telegramEnabled`, `telegramStreamReplies`, `ollamaBaseURL` |
| Heartbeat | `heartbeatEnabled`, `heartbeatIntervalMinutes`, `heartbeatCheckCalendar/Kanban/Reminders` |
| 알림 센터 (H-3) | `notificationCalendarEnabled`, `notificationKanbanEnabled`, `notificationReminderEnabled`, `notificationMemoryEnabled`, `notificationSoundEnabled`, `notificationReplyEnabled` |
| 아바타 | `avatarEnabled` |
| 가이드 | `hintsEnabled`, `featureTourCompleted`, `featureTourSkipped`, `featureTourBannerDismissed` |
| 예산 (G-4) | `budgetEnabled`, `monthlyBudgetUSD`, `budgetAlert50`, `budgetAlert80`, `budgetAlert100`, `budgetBlockOnExceed` |
| 동기화 (G-3) | `autoSyncEnabled`, `realtimeSyncEnabled`, `syncConversations`, `syncMemory`, `syncKanban`, `syncProfiles`, `conflictResolutionStrategy` |
| 메뉴바 (H-1) | `menuBarEnabled`, `menuBarGlobalShortcutEnabled` |
| Spotlight (H-4) | `spotlightIndexingEnabled`, `spotlightIndexConversations`, `spotlightIndexPersonalMemory`, `spotlightIndexAgentMemory`, `spotlightIndexWorkspaceMemory` |
| RAG (I-1) | `ragEnabled`, `ragEmbeddingProvider`, `ragEmbeddingModel`, `ragTopK`, `ragMinSimilarity`, `ragAutoSearch`, `ragChunkSize`, `ragChunkOverlap` |
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
일괄 선택: 커맨드 팔레트/툴바 -> viewModel.toggleMultiSelectMode() -> BulkActionToolbar 표시
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

### 컨텍스트/메모리 관리 (UX-8 추가)
```
메모리 인스펙터: ⌘I -> showMemoryPanel 토글 -> .inspector modifier -> MemoryPanelView
  -> 계층 트리: 시스템프롬프트 / 에이전트페르소나 / 워크스페이스메모리 / 에이전트메모리 / 개인메모리
  -> 각 MemoryNodeView: 접기(미리보기) / 펼치기(TextEditor + 저장 버튼)
  -> 푸터: 총 N자 / ~M토큰
시스템프롬프트 배너: 대화 상단 SystemPromptBannerView
  -> 접힌: "시스템 프롬프트: 미리보기... [편집]" / 펼침: TextEditor + 저장
  -> UserDefaults로 접힌/펼친 상태 기억
메모리 토스트: save_memory/update_memory 도구 실행 -> MemoryToastEvent 생성
  -> viewModel.memoryToastEvents 배열에 추가
  -> MemoryToastContainerView (우측 하단): 5초 자동 fade + "보기" -> 메모리 패널 열기
메모리 참조 배지: appendAssistantMessage() -> buildMemoryContextInfo() -> Message.memoryContextInfo
  -> MessageBubbleView -> MemoryReferenceBadgeView: "메모리 N계층" 배지
  -> 호버 팝오버: 계층별 사용 여부 + 글자수
기존 컨텍스트 인스펙터: ⌘⌥I -> showContextInspector -> ContextInspectorView (시트)
```

### 모델 빠른 변경 (UX-10 추가)
```
SystemHealthBarView 모델 클릭 / ⌘⇧M -> showQuickModelPopover = true
  -> QuickModelPopoverView (320pt popover)
  -> 프로바이더 라디오 버튼 선택 (클라우드/로컬 그룹) -> settings.llmProvider 변경
  -> 로컬 프로바이더: 연결 상태 인디케이터 (초록/빨간 점)
  -> 모델 목록 선택 -> settings.llmModel 변경
  -> 로컬 모델: 파라미터 크기 + 파일 크기 + 도구 지원 아이콘 표시
  -> "자동 모델 선택" 토글 -> settings.taskRoutingEnabled 변경
  -> 오프라인 폴백 설정 정보 표시 (활성 시)

### 오프라인 폴백 (G-1 추가)
```
네트워크 에러 발생
  -> ModelRouter.isNetworkError() 판단
  -> settings.offlineFallbackEnabled 확인
  -> 로컬 서버 연결 확인
  -> DochiViewModel.activateOfflineFallback() -> 로컬 모델로 전환
  -> OfflineFallbackBannerView 표시
  -> SystemHealthBarView 아이콘/텍스트 변경 (주황색 "오프라인")
  -> "원래 모델로 복구" 클릭 -> DochiViewModel.restoreOriginalModel()
  -> "설정에서 더 보기" -> 설정 창 열기 (aiModel 섹션)
커맨드 팔레트: "모델 빠르게 변경" -> openQuickModelPopover 액션
  "AI 모델 설정 열기" / "API 키 설정 열기" / ... -> openSettingsSection(section:) 액션
```

### TTS 오프라인 폴백 (G-2 추가)
```
클라우드 TTS 실패 (네트워크 오류 등)
  -> settings.ttsOfflineFallbackEnabled 확인
  -> TTSRouter.activateOfflineFallback()
  -> ONNX 모델 설치 여부 확인 (settings.onnxModelId)
  -> ONNX 사용 가능: SupertonicService로 전환
  -> ONNX 불가: SystemTTSService로 전환
  -> TTSFallbackBannerView 표시 (보라색 배경)
  -> "원래 TTS로 복구" 클릭 -> viewModel.restoreTTSProvider()
ONNX 모델 관리:
  -> 설정 > 음성 합성 > ONNX 선택 -> ONNXModelManagerView 인라인
  -> ModelDownloadManager.loadCatalog() -> 하드코딩된 Piper 한국어 모델 목록
  -> 모델 다운로드 (ProgressView) / 취소 / 삭제
  -> 설치된 모델 Picker로 선택 -> settings.onnxModelId 변경
```

### 메뉴바 퀵 액세스 (H-1 추가)
```
메뉴바 아이콘 클릭 / ⌘⇧D (글로벌) → MenuBarManager.togglePopover()
  → NSPopover → MenuBarPopoverView (viewModel 공유)
  → 입력 → viewModel.inputText 설정 → viewModel.sendMessage()
  → 메인 앱에도 동일 대화 반영 (동일 참조)
  → 새 대화: viewModel.newConversation()
  → 메인 앱 열기: NSApp.activate() + 메인 윈도우 표시
설정: settings.menuBarEnabled → MenuBarManager.setup()/teardown()
  settings.menuBarGlobalShortcutEnabled → 글로벌 단축키 등록/해제
```

### Apple Shortcuts 연동 (H-2 추가)
```
AppIntents 프레임워크 등록 (앱 포함 시 자동)
  -> DochiShortcuts (AppShortcutsProvider) -> macOS Shortcuts 앱에 4개 액션 노출
  -> Siri 문구 등록: "도치에게 물어보기", "도치 메모 추가", "도치 칸반 카드 생성", "도치 오늘 브리핑"
액션 실행: Shortcuts 앱 / Siri -> AppIntent.perform()
  -> DochiShortcutService.shared 접근 (서비스 주입은 DochiApp.init()에서)
  -> AskDochiIntent: LLMService.send() (safe 도구만, 단일 턴)
  -> AddMemoIntent: ContextService.appendUserMemory() 또는 appendWorkspaceMemory()
  -> CreateKanbanCardIntent: KanbanManager.shared.addCard() (첫 번째 보드, 첫 번째 컬럼)
  -> TodayBriefingIntent: HeartbeatService 데이터 수집 + LLM 요약
  -> 실행 결과 -> ShortcutExecutionLogStore 기록 (FIFO, 최대 50건)
설정: 설정 > 연결 > 단축어 -> ShortcutsSettingsView
  -> 상태 표시 + Shortcuts/Siri 앱 열기 버튼
  -> 4개 액션 카드 (아이콘, 설명, Siri 문구)
  -> 최근 실행 기록 (최대 10건 표시, 성공/실패 배지)
커맨드 팔레트: "단축어 앱 열기" -> openShortcutsApp 액션
  "단축어 설정" -> openSettingsSection(section: "shortcuts")
```

### 알림 센터 연동 (H-3 추가)
```
HeartbeatService tick -> 카테고리별 컨텍스트 수집
  -> NotificationManager.sendCalendarNotification/sendKanbanNotification/sendReminderNotification/sendMemoryNotification
  -> 설정에 따라 필터링 (notificationCalendarEnabled 등)
  -> UNMutableNotificationContent (카테고리 식별자 + threadIdentifier + 소리 옵션)
  -> UNUserNotificationCenter.add()
사용자 응답:
  -> 답장 (reply 액션) -> NotificationManager.onReply
    -> DochiViewModel.handleNotificationReply(text:category:originalBody:)
    -> 대화에 알림 컨텍스트 주입 + sendMessage()
  -> 앱 열기 (open-app 액션 / 알림 탭) -> NotificationManager.onOpenApp
    -> DochiViewModel.handleNotificationOpenApp(category:)
    -> NSApp.activate() + 카테고리별 네비게이션
설정: 설정 > 일반 > 하트비트 > 알림 센터 섹션
  -> 권한 상태 표시 (초록/빨강/노랑 원)
  -> 소리/답장 토글, 캘린더/칸반/미리알림/메모리 카테고리별 토글
  -> 하트비트 비활성 시 전체 disabled
```

### 가이드/온보딩 (UX-9 추가)
```
기능 투어: 온보딩 완료 → "기능 둘러보기" 버튼 → FeatureTourView (4단계)
  → 완료/건너뛰기 → UserDefaults(featureTourCompleted/Skipped) 기록
투어 리마인더: EmptyConversationView → 투어 건너뛴 사용자에게 배너 표시
  → "둘러보기" → FeatureTourView / "X" → featureTourBannerDismissed
인앱 힌트: 뷰 진입 → HintBubbleModifier → HintManager.canShowHint() 확인
  → 1.5초 후 fadeIn → "확인"/닫기 → markHintSeen() → UserDefaults 기록
  → "다시 보지 않기" → disableAllHints() → 모든 힌트 전역 비활성화
설정 도움말: SettingsSectionHeader → SettingsHelpButton → 클릭 → 팝오버
가이드 관리: 설정 > 일반 > 가이드 섹션
  → "기능 투어 다시 보기" → FeatureTourView 시트
  → "인앱 힌트 초기화" → resetAllHints()
  → "인앱 힌트 표시" 토글 → hintsEnabled get/set
커맨드 팔레트: "기능 투어" → FeatureTourView 시트 / "인앱 힌트 초기화" → resetHints
```

### Spotlight 검색 (H-4 추가)
```
대화 저장 → saveConversation() → spotlightIndexer.indexConversation()
  → CSSearchableItem 생성 (uniqueId: dochi-conversation-{uuid})
  → CSSearchableIndex.indexSearchableItems()
대화 삭제 → deleteConversation() → spotlightIndexer.removeConversation()
메모리 인덱싱 → spotlightIndexer.indexMemory(scope:identifier:title:content:)
전체 재구축 → 설정 UI "인덱스 재구축" / 커맨드 팔레트 "Spotlight 인덱스 재구축"
  → spotlightIndexer.rebuildAllIndices() (async, rebuildProgress 0.0~1.0)
딥링크: Spotlight 결과 클릭 → dochi://conversation/{uuid} 또는 dochi://memory/...
  → .onOpenURL → viewModel.handleDeepLink(url:) → 대화 선택 또는 메모리 패널 표시
설정: 설정 > 일반 > 인터페이스 > Spotlight 검색
  → 활성화 토글, 범위 체크박스 (대화/개인메모리/에이전트메모리/워크스페이스메모리)
  → 인덱싱 상태 (N건), 재구축/초기화 버튼, 진행률 ProgressView
```

### RAG 문서 검색 (I-1 추가)
```
문서 추가: 커맨드 팔레트 "문서 라이브러리" → DocumentLibraryView 시트 (600x500pt)
  → 파일 추가 (PDF/MD/TXT) / 폴더 추가
  → DocumentIndexer.indexFile(at:) → 텍스트 추출 → ChunkSplitter → EmbeddingService → VectorStore
인덱싱 상태: DocumentIndexer.indexingState (@Observable) → RAGIndexingState
  → idle / indexing(progress, fileName) / completed / failed
대화 시 자동 검색: sendMessage() → processLLMLoop()
  → settings.ragEnabled && ragAutoSearch일 때
  → DocumentIndexer.search(query:) → VectorStore.search(queryEmbedding:topK:minSimilarity:)
  → 결과를 시스템 프롬프트 "## 참조 문서" 섹션으로 주입
  → 응답 완료 시 Message.ragContextInfo에 RAGContextInfo 저장
배지: MessageBubbleView → RAGContextBadgeView (파란색 "문서 N건 참조")
  → 호버 시 팝오버: 파일명, 섹션, 유사도, 스니펫 표시
설정: 설정 > AI > 문서 검색 (RAGSettingsView)
  → 활성화, 임베딩 모델, 자동 검색, topK, 최소 유사도, 청크 크기, 오버랩
  → 문서 통계, 재인덱싱/초기화 버튼
데이터: ~/Library/Application Support/Dochi/rag/{workspaceId}/vectors.sqlite
모델: RAGDocument, RAGReference, RAGContextInfo, RAGSearchResult, RAGFileType, RAGIndexingStatus, RAGIndexingState
커맨드 팔레트: "문서 라이브러리" / "문서 재인덱싱" / "문서 검색 설정"
```

### 메모리 자동 정리 (I-2 추가)
```
트리거: newConversation() / selectConversation(id:) 시 이전 대화에 assistant >= minMessages
  → MemoryConsolidator.consolidate(conversation:sessionContext:settings:)
  → fire-and-forget (대화 흐름 방해 없음)
수동 실행: 커맨드 팔레트 "메모리 자동 정리 실행"
정리 흐름:
  1. LLM 호출로 대화에서 사실/결정 추출 (JSON 형태)
  2. 현재 memory.md 로드 (ContextService)
  3. 중복 감지 (Jaccard 유사도 > 0.7)
  4. 모순 감지 (유사도 0.3~0.7 구간 + 주요 키워드 공유)
  5. memory.md 업데이트 (신규 추가, 중복 스킵)
  6. 크기 한도 초과 시 아카이브
  7. ConsolidationResult → changelog 기록
배너: MemoryConsolidationBannerView (ContentView chatDetailView 내)
  → idle: 미표시
  → analyzing: 보라색 + brain + 스피너
  → completed: 초록색 + checkmark + "N건 추가, M건 갱신" + 변경 내용 버튼
  → conflict: 주황색 + exclamationmark + "모순 N건" + 해결하기 버튼
  → failed: 빨간색 + xmark + 실패 메시지
  → 15초 후 자동 fade (analyzing 제외)
시트: MemoryDiffSheetView (560x480pt) — 변경 이력 diff, 되돌리기
시트: MemoryConflictResolverView (520x400pt) — 모순 해결 (기존 유지/새 항목 적용/둘 다 유지)
설정: 설정 > AI > 메모리 정리 (MemorySettingsView)
  → 활성화, 최소 메시지 수, 정리 모델, 배너 표시, 크기 한도, 자동 아카이브
데이터: ~/Library/Application Support/Dochi/memory_changelog.json (최대 100건 FIFO)
데이터: ~/Library/Application Support/Dochi/memory_archive/{scope}_{timestamp}.md
모델: ConsolidationState, ConsolidationResult, MemoryChange, MemoryConflict, MemoryConflictResolution, MemoryScope, ExtractedFact, ChangelogEntry
커맨드 팔레트: "메모리 자동 정리 실행" / "메모리 변경 이력" / "메모리 정리 설정"
AppSettings: memoryConsolidationEnabled, memoryConsolidationMinMessages, memoryConsolidationModel, memoryConsolidationBannerEnabled, memoryWorkspaceSizeLimit, memoryAgentSizeLimit, memoryPersonalSizeLimit, memoryAutoArchiveEnabled
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
| ⌘I | 메모리 인스펙터 패널 토글 | ContentView 툴바 (UX-8 변경) |
| ⌘⌥I | 컨텍스트 인스펙터 (시트) | ContentView hidden button (UX-8 신규) |
| ⌘, | 설정 | macOS 자동 (Settings scene) |
| ⌘⇧S | 시스템 상태 시트 | ContentView 툴바 |
| ⌘⇧F | 기능 카탈로그 | ContentView 툴바 |
| ⌘⇧A | 에이전트 빠른 전환 | ContentView (hidden button) |
| ⌘⇧W | 워크스페이스 빠른 전환 | ContentView (hidden button) |
| ⌘⇧U | 사용자 빠른 전환 | ContentView (hidden button) |
| ⌘⇧K | 칸반/대화 전환 | ContentView (onKeyPress) |
| ⌘⇧L | 즐겨찾기 필터 토글 | ContentView (onKeyPress) |
| ⌘⇧M | 모델 빠른 변경 (QuickModelPopover) | ContentView (onKeyPress) (UX-10 변경, 기존 일괄선택은 커맨드 팔레트/툴바로 접근) |
| ⌘⇧D | 메뉴바 퀵 액세스 토글 (글로벌) | MenuBarManager (NSEvent monitor) (H-1) |
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
| 인스펙터 (.inspector modifier) | MemoryPanelView | 우측 사이드 패널 (260~360pt) |
| 접기/펼치기 배너 (VStack + Button) | SystemPromptBannerView | 접힌: 미리보기, 펼침: TextEditor |
| 토스트 (HStack + material + shadow) | MemoryToastView | 우측 하단 알림 (5초 자동 fade) |
| 메모리 노드 카드 (VStack + chevron) | MemoryNodeView | 접기/펼치기 + 인라인 편집 + 저장 |
| 힌트 버블 (ViewModifier + material) | HintBubbleModifier | 일회성 맥락 힌트 (1.5초 후 fadeIn, 최대 1개, "다시 보지 않기") |
| 설정 도움말 버튼 (? + popover) | SettingsHelpButton | 섹션 헤더 "?" 아이콘, 클릭 시 설명 팝오버 (280pt) |
| 투어 단계 (step indicator + 콘텐츠) | FeatureTourView | 4단계 워크스루 (이전/다음/건너뛰기/시작) |
| 인디케이터 버튼 (ButtonStyle + onHover) | SystemHealthBarView | 호버 시 배경색 표시, 개별 클릭 영역 (UX-10) |
| 설정 사이드바 (List + 그룹 섹션) | SettingsSidebarView | 검색 필드 + 6그룹 14섹션, 호버/선택 하이라이트 (UX-10, H-2 추가) |
| 알림 권한 상태 (Circle + Text) | NotificationAuthorizationStatusView | 초록(허용)/빨강(거부)/노랑(미결정) 원 + 상태 텍스트 (H-3) |
| 액션 카드 (HStack + 아이콘 배경 + 제목/설명/Siri문구) | ShortcutsSettingsView | Shortcuts 액션 카드 (아이콘, 설명, Siri 문구 표시) (H-2) |

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
| 시스템 프롬프트 없음 | "시스템 프롬프트가 설정되지 않았습니다 [작성하기]" | SystemPromptBannerView |
| 메모리 노드 비어 있음 | 노드별 안내 문구 + "작성하기" 버튼 | MemoryNodeView |
| 개인 메모리 없음 (사용자 미설정) | "사용자가 설정되지 않아 표시할 수 없습니다" | MemoryPanelView |
| 투어 미완료 (건너뜀) | "도치의 주요 기능을 알아보세요" 배너 + "둘러보기" | EmptyConversationView |
| 첫 대화 힌트 | "첫 대화를 시작해보세요!" 힌트 버블 | EmptyConversationView |
| 메뉴바 빈 대화 | 도치 아이콘 + "무엇이든 물어보세요" + 제안 칩 3개 | MenuBarPopoverView |
| Shortcuts 실행 기록 없음 | 시계 아이콘 + "아직 실행 기록이 없습니다" + 안내 문구 | ShortcutsSettingsView |

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
| 사용량 데이터 | `~/Library/Application Support/Dochi/usage/{yyyy-MM}.json` | 월별 API 사용량/비용 기록 (G-4) |
| Shortcuts 실행 기록 | `~/Library/Application Support/Dochi/shortcut_logs.json` | Shortcuts/Siri 실행 기록 (최대 50건, FIFO) (H-2) |

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

### MemoryContextInfo (UX-8 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `systemPromptLength` | `Int` | 시스템 프롬프트 글자수 |
| `agentPersonaLength` | `Int` | 에이전트 페르소나 글자수 |
| `workspaceMemoryLength` | `Int` | 워크스페이스 메모리 글자수 |
| `agentMemoryLength` | `Int` | 에이전트 메모리 글자수 |
| `personalMemoryLength` | `Int` | 개인 메모리 글자수 |

### MemoryToastEvent (UX-8 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `id` | `UUID` | 이벤트 ID |
| `scope` | `Scope` | workspace/personal/agent |
| `action` | `Action` | saved/updated |
| `contentPreview` | `String` | 저장 내용 미리보기 (80자) |

### ShortcutExecutionLog (H-2 추가)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `id` | `UUID` | 실행 기록 ID |
| `actionName` | `String` | 실행된 액션 이름 |
| `timestamp` | `Date` | 실행 시각 |
| `success` | `Bool` | 성공 여부 |
| `resultSummary` | `String` | 결과 요약 (최대 200자) |
| `errorMessage` | `String?` | 오류 메시지 (실패 시) |

---

*최종 업데이트: 2026-02-15 (H-4 Spotlight/시스템 검색 연동 추가)*
