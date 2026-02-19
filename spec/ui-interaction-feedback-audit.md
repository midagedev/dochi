# UI Interaction Feedback Audit

작성일: 2026-02-18  
기준: `Dochi/Views`, `Dochi/Views/Settings` 중심 정적 점검

## 요약

- 총 점검 항목: **13개**
- P0 (사용자 체감상 "버튼이 안 먹는" 수준): **2개**
- P1 (실패 원인 미노출/무반응): **8개**
- P2 (저빈도/저영향이지만 피드백 누락): **3개**

## 상세 목록

| ID | 우선순위 | 인터랙션 | 현재 문제 | 코드 위치 | 권장 리액션 |
|---|---|---|---|---|---|
| UIF-01 | P0 | 도구 탭 상세의 `세션 시작` 버튼 | `try?`로 에러를 버리고, 시작 성공 후에도 선택 상태를 세션으로 전환하지 않아 화면이 그대로여서 "무반응"처럼 보임 | `Dochi/Views/ContentView.swift:642`, `Dochi/Views/ContentView.swift:654` | `do/catch`로 실패 배너 표시 + 성공 시 `selectedToolSessionId`로 전환 |
| UIF-02 | P0 | 좌측 도구 리스트 컨텍스트 메뉴 `시작` | `try?`로 실패 원인 미노출, 시작 후 선택 상태도 그대로라 사용자에게 시작 여부가 즉시 전달되지 않음 | `Dochi/Views/Sidebar/ExternalToolListView.swift:223`, `Dochi/Views/Sidebar/ExternalToolListView.swift:224` | 시작 중 상태 표시 + 성공 시 해당 세션 자동 선택 + 실패 메시지 표시 |
| UIF-03 | P1 | 외부 도구 대시보드 `재시작` | 로딩 스피너는 보이지만 실패 원인은 전혀 노출되지 않음 (`try?`) | `Dochi/Views/ExternalToolDashboardView.swift:117`, `Dochi/Views/ExternalToolDashboardView.swift:119` | 실패 시 배너/인라인 오류 텍스트 표시 |
| UIF-04 | P1 | 외부 도구 대시보드 커맨드 전송 | 입력을 먼저 지운 뒤 `try?` 실행. 실패 시 사용자는 전송 실패를 모르고 입력도 복구되지 않음 | `Dochi/Views/ExternalToolDashboardView.swift:245`, `Dochi/Views/ExternalToolDashboardView.swift:247` | 실패 시 입력 복원 + 오류 메시지 표시 |
| UIF-05 | P1 | 문서 라이브러리 개별 `재인덱싱` | 하단 오류 영역이 있음에도 해당 경로는 `try?`라 실패가 표시되지 않음 | `Dochi/Views/RAG/DocumentLibraryView.swift:117`, `Dochi/Views/RAG/DocumentLibraryView.swift:119` | `catch`에서 `errorMessage` 설정 |
| UIF-06 | P1 | 시스템 상태 시트(legacy 경로) `수동 동기화` | `syncContext/syncConversations`를 `try?` 처리해 실패가 UI에 반영되지 않음 | `Dochi/Views/SystemStatusSheetView.swift:571`, `Dochi/Views/SystemStatusSheetView.swift:573` | 완료/실패 상태 텍스트 추가 |
| UIF-07 | P1 | 계정 설정 `로그아웃` | `try? await service.signOut()` 실패 시 무반응 | `Dochi/Views/Settings/AccountSettingsView.swift:68`, `Dochi/Views/Settings/AccountSettingsView.swift:70` | 로그아웃 실패 메시지/토스트 추가 |
| UIF-08 | P1 | 텔레그램 토큰 `저장` | Keychain save/delete를 `try?`로 무시해 저장 실패가 숨겨짐 | `Dochi/Views/Settings/IntegrationsSettingsView.swift:195`, `Dochi/Views/Settings/IntegrationsSettingsView.swift:198` | 저장 성공/실패 상태 라벨 추가 |
| UIF-09 | P1 | 텔레그램 웹훅 시작/중지 | `startWebhook/stopWebhook` 실패를 `try?`로 무시. 연결 상태 빨간 점만으로 원인 파악 불가 | `Dochi/Views/Settings/IntegrationsSettingsView.swift:217`, `Dochi/Views/Settings/IntegrationsSettingsView.swift:230` | 오류 문자열 상태(`botCheckError` 유사)로 원인 노출 |
| UIF-10 | P1 | 온보딩 API 키 확인 단계 | Keychain 저장 실패를 무시한 채 다음 단계로 진행됨 | `Dochi/Views/OnboardingView.swift:452`, `Dochi/Views/OnboardingView.swift:453` | 저장 실패 시 다음 단계 진행 차단 + 인라인 오류 |
| UIF-11 | P2 | 이미지 첨부(파일 선택/붙여넣기/드롭) | 파일 읽기 실패(`Data(contentsOf:)`)가 조용히 무시되어 일부/전체 첨부 실패 시 이유를 알 수 없음 | `Dochi/Views/ContentView.swift:1750`, `Dochi/Views/ContentView.swift:1780`, `Dochi/Views/ContentView.swift:1809` | 실패 파일 개수/이름을 배너로 안내 |
| UIF-12 | P2 | 외부 앱 열기(Shortcuts/Siri/플러그인 폴더) | `NSWorkspace.shared.open(...)` 반환값 미확인으로 실행 실패 시 무반응 | `Dochi/Views/ContentView.swift:918`, `Dochi/Views/Settings/ShortcutsSettingsView.swift:164`, `Dochi/Views/Settings/PluginSettingsView.swift:47` | open 실패 시 "앱을 열 수 없음" 토스트 표시 |
| UIF-13 | P2 | MCP 서버 저장 후 UserDefaults 직렬화 | JSON encode 실패가 무시되어 저장 누락 가능성이 UI에 드러나지 않음 | `Dochi/Views/Settings/MCPServerEditView.swift:229`, `Dochi/Views/Settings/MCPServerEditView.swift:231` | 직렬화 실패 시 `errorMessage` 표시 |

## 공통 개선 가이드

1. 사용자 액션 경로에서 `try?` 금지: `do/catch` + 사용자 가시 피드백(배너/인라인 상태) 사용.
2. 액션 즉시 반응 제공: 로딩 상태, 성공 확인, 실패 이유 3단계 피드백 표준화.
3. 성공 후 상태 전환 보장: 데이터 변경뿐 아니라 선택 상태/포커스도 함께 갱신.
4. 실패 로그만 남기지 말고 노출: `Log.*`는 개발자용, 사용자용 상태 문자열을 별도로 유지.
