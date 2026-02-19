# Built-in Tool & Major Feature UI Inventory

작성일: 2026-02-18
기준 코드: `Dochi/Services/Tools/*.swift`, `Dochi/Views/*`, `Dochi/Views/Settings/*`, `Dochi/Models/FeatureSuggestion.swift`

## 1) 현황 요약

- Built-in tool 정의: **126개**
- Baseline(항상 노출): **46개**
- Conditional(조건부 노출): **80개**
- 권한 카테고리 분포: `safe` 65 / `sensitive` 52 / `restricted` 9
- MCP 동적 툴(`mcp_{server}_{tool}`)은 연결된 서버 상태에 따라 런타임에 추가되며 위 126개에는 미포함

## 2) 현재 사용 가능한 경로

- 대화창 자연어 요청: LLM이 자동으로 툴 선택/실행
- 슬래시 커맨드(`/<기능>`): 예시 프롬프트를 입력 후 즉시 전송
- 기능 카탈로그(`⌘⇧F`): 그룹별 툴 탐색 + "사용해보기" 프롬프트 주입
- 설정 > 도구: 전체 툴 검색/필터/파라미터 확인
- 설정 > 프로액티브 제안: 유휴 감지/쿨다운/유형/채널/기록 관리
- 설정 > 사용량 대시보드: 구독 플랜 사용률, 낭비 위험, 자동 작업 설정
- 대화 화면: 프로액티브 제안 버블 + 제안 토스트 + 하트비트 할거리 버블
- 민감/제한 툴 승인 배너: `sensitive/restricted` 실행 시 사용자 승인 플로우
- CLI(개발 경로): `dochi dev tool <tool_name> <json>` 형태로 직접 호출 가능

## 3) Built-in Tool 그룹별 UI 커버리지

| 도메인 | 포함 그룹 | 현재 사용 방식 | 현재 UI 상태 | 추가 UI 필요도 |
|---|---|---|---|---|
| 툴 메타 | `tools` | 자연어, 슬래시, 설정 | 도구 브라우저/카탈로그 있음 | 낮음 |
| 일정/할 일 | `calendar`, `reminders`, `timer`, `alarm` | 자연어, 슬래시 | 전용 통합 일정 UI 없음 (대화 중심) | **높음** |
| 칸반 | `kanban` | 자연어, 슬래시, 전용 화면 | 보드/카드 UI 존재 | 낮음 |
| 워크플로우 | `workflow` | 자연어, 슬래시 | 빌더/실행 모니터 전용 UI 없음 | **높음** |
| 메모리/프로필/컨텍스트 | `memory`, `profile`, `context` | 자연어, 슬래시, 일부 패널 | 메모리 패널은 있음, profile/context 고급 작업 UI는 제한적 | 중간 |
| 에이전트 | `agent` | 자연어, 슬래시, 설정 | 생성/편집 UI 있음, 위임 실행 모니터는 대화 중심 | 중간 |
| 워크스페이스 | `workspace` | 자연어, 사이드바 일부 | 생성/삭제/전환 일부 UI, 초대코드/조인 관리 UI 약함 | **높음** |
| 통합 | `telegram`, `settings.mcp_*` | 자연어, 설정 | Telegram/MCP 설정 UI 있음 | 낮음 |
| 파일/OS 연동 | `file`, `finder`, `clipboard`, `screenshot` | 자연어, 슬래시 | 파일 작업 전용 Explorer/작업 이력 UI 없음 | **높음** |
| 개발 실행 | `shell`, `terminal`, `git`, `github`, `coding` | 자연어, 슬래시, 터미널 패널(일부) | 터미널 UI는 있음, Git/GitHub/Coding 전용 대시보드 없음 | **높음** |
| 미디어/유틸 | `image`, `music`, `search`, `contacts`, `calculator`, `datetime`, `url`, `app.guide` | 자연어, 슬래시 | 대부분 대화형 사용에 적합, 필수 전용 UI는 아님 | 낮음 |
| 외부 도구 브리지 | `external_tool`, `dochi.*` | 자연어, 설정, 도구 대시보드 | 외부 도구 세션 UI 존재, bridge 전용 가시화는 제한적 | 중간 |

## 4) 주요 피처(비-툴 중심) UI 상태

| 주요 피처 | 현재 UI 상태 | 추가 UI 필요도 | 코멘트 |
|---|---|---|---|
| 프로액티브 제안(K-2) | 설정 화면 + 대화 버블/토스트 존재 | **높음** | 기능은 있으나 상시 상태 가시성(현재 상태/다음 제안 시점/일일 잔여 한도)이 약함 |
| 유휴자원/구독 최적화(J-5) | 사용량 대시보드 내 구독 카드/자동작업 토글 존재 | **높음** | 핵심 정보(낭비 위험/잔여 토큰/자동작업 큐)가 메인 화면에서 거의 보이지 않음 |
| 하트비트 자원 자동작업 파이프라인 | Heartbeat 주기 평가 + 큐잉 동작 존재 | **높음** | \"무엇이 언제 큐잉되었는지\"에 대한 작업 피드백 UI가 부족함 |
| 에이전트 관리 | 성숙 (Wizard/Grid/Detail) | 낮음 | 툴 연계는 충분 |
| 칸반 워크스페이스 | 성숙 (Board/Workspace) | 낮음 | 툴/수동 조작 모두 가능 |
| 터미널 | 성숙 (Panel/Session + 설정) | 낮음 | LLM 연동 제어도 설정에 존재 |
| 외부 도구(K-4) | 성숙 (목록/대시보드/설정/프로파일) | 낮음 | bridge 특화 모니터는 보강 가능 |
| 통합(Telegram/MCP) | 성숙 (설정/편집) | 낮음 | 운영 로그 UI는 별도 검토 가능 |
| 자동화(Scheduler) | 설정 UI 있음 | 중간 | 실행 추적/디버깅 뷰 강화 여지 |
| RAG/문서 검색 | 설정+문서 라이브러리 UI 있음 | 중간 | 검색 결과 설명성/디버깅 UX 보강 여지 |
| 동기화/충돌해결 | 전용 시트 존재 | 낮음 | 운영 지표 대시보드 정도만 확장 여지 |
| 플러그인 | 설정/상세 UI 있음 | 중간 | 툴 권한/샌드박스 시각화 강화 여지 |

## 5) UI 추가 우선순위 제안 (프로액티브/유휴자원 중심)

### 5-1. 최우선: \"보이게 만드는\" UI

1. 메인 화면 상단 `프로액티브 상태 스트립` 추가
- 노출: `idle/analyzing/cooldown`, 다음 제안까지 남은 시간, 일일 한도 사용량
- 목적: 설정 화면을 열지 않아도 현재 동작 상태를 즉시 인지

2. `유휴 토큰/낭비위험` 상시 위젯 추가 (SystemHealthBar 또는 우측 패널)
- 노출: 구독별 사용률, 리셋일까지 남은 일수, 예상 미사용 비율, 위험 등급
- 목적: \"현재 내 코딩 플랜 토큰이 놀고 있는지\"를 대화 중에도 즉시 확인

3. `자동작업 큐/실행 피드` UI 추가
- 노출: 하트비트 평가 시각, 큐잉된 작업 타입, 구독 연계 정보, 실행 결과/실패 사유
- 목적: 자동화가 실제로 일하고 있는지 가시화

4. `지금 실행` 퀵 액션 추가 (구독 카드/제안 버블)
- 동작: 자료조사/메모리정리/문서요약/칸반정리 즉시 실행
- 목적: 유휴 토큰 소진을 수동 트리거로 빠르게 연결

5. 프로액티브 제안 `히스토리/효율` 대시보드 추가
- 노출: 제안 생성 수, 수락률, 유형별 성과, 중복 차단/쿨다운 지표
- 목적: 노이즈 줄이고 실제 효용 높은 제안만 남기기

### 5-2. 그다음 순위 (기존 Backlog)

1. 워크플로우 빌더/런 모니터 화면
- 대상: `workflow.*`
- 이유: 현재 텍스트 도구 중심이라 단계 편집/재실행/히스토리 비교가 불편함

2. 일정 통합 허브 (Calendar + Reminders + Timer/Alarm)
- 대상: `calendar.*`, `*_reminder`, `*_timer`, `*_alarm`
- 이유: 시간축/우선순위 관점의 시각화 부재

3. 파일 작업 패널 (탐색 + 변경내역 + 승인큐)
- 대상: `file.*`, `finder.*`, `clipboard.*`, `screenshot.capture`
- 이유: 파일성 작업의 결과/리스크를 대화 텍스트만으로 추적하기 어려움

4. 개발 작업 허브 (Git/GitHub/Coding Session)
- 대상: `git.*`, `github.*`, `coding.*`, `shell.execute`, `terminal.run`
- 이유: PR/커밋/리뷰/세션 상태를 단일 화면에서 추적 필요

5. 워크스페이스 초대/조인 관리 화면
- 대상: `workspace.join_by_invite`, `workspace.regenerate_invite_code`
- 이유: 협업 온보딩 플로우가 툴 호출 기반이라 진입장벽이 높음

6. 에이전트 위임 모니터
- 대상: `agent.delegate_task`, `agent.delegation_status`, `agent.check_status`
- 이유: 위임 큐/진행상태/결과를 구조적으로 보기 어려움

### 5-3. 정책 고도화 (유휴 토큰 감지 + Git 스캔 연동)

1. 유휴 구독 토큰 감지 정책을 단순 임계치에서 `예측 기반`으로 전환
- 현재 한계: `usageRatio` + `remainingRatio` 중심의 정적 판정
- 개선 방향: 최근 7일 소모 속도(일평균), 리셋일까지 예상 소진량, 최소 보존 버퍼(예: 10~15%)를 함께 반영
- 결과: \"토큰이 남아보여도 실제로는 필요한\" 케이스 오탐 감소

2. 구독/워크스페이스/브랜치 단위의 정책 분리
- 현재 한계: provider 단위 집계로 실제 작업 컨텍스트 구분이 약함
- 개선 방향: `subscription + workspace + repo + branch` 단위 리스크 평가
- 결과: 실제 코딩 작업중인 저장소에 우선 배분 가능

3. Git 스캔을 자원 자동작업 파이프라인의 1급 작업으로 편입
- 신규 자동작업 타입 제안: `git_scan_review`
- 기본 실행 체인: `git.status` -> `git.diff --stat` -> 조건 충족 시 `coding.review`
- 트리거 예시:
  - 유휴 토큰 리스크가 `wasteRisk` 또는 `caution`
  - 최근 변경 파일 존재 (`git diff --stat` non-empty)
  - 대규모 변경(예: 너무 큰 diff) 또는 바이너리 위주 변경은 제외

4. 중복 실행 방지 키를 \"날짜\"에서 \"변경 집합\" 중심으로 강화
- 현재 한계: 같은 날 1회 제한만 존재
- 개선 방향: `repo + branch + headSHA + diffHash + taskType` 기반 dedupe
- 결과: 같은 변경에 대한 중복 스캔 감소, 새로운 변경에는 즉시 재평가 가능

5. Git 스캔 연동 UI 요구사항 (필수)
- 메인에 \"Git 스캔 후보\" 카드 노출: 변경 파일 수, 마지막 스캔 시각, 위험도
- `지금 스캔` / `나중에` / `이 저장소 자동 제외` 액션 제공
- 자동 스캔 결과를 프로액티브 히스토리와 같은 타임라인에 통합 표시

## 6) 컨텍스트 레이어 확장 제안 (Git Repo Project Layer)

현재 컨텍스트는 사실상 `user -> workspace -> agent` 구조이며, Git 관련 실행 컨텍스트는 툴 호출 인자(`repo_path`)에 분산되어 있다.  
코딩 자동화/유휴 토큰 정책/프로액티브 제안을 안정적으로 묶기 위해 `project(repo)` 레이어를 추가하는 것을 권장한다.

권장 계층:
- `user -> workspace -> project(repo) -> agent`

### 6-1. 왜 필요한가

1. 정책 일관성
- 유휴 토큰 감지와 Git 스캔 트리거를 repo 단위로 묶어야 오탐/중복 실행을 줄일 수 있음

2. 실행 재현성
- 어떤 브랜치/HEAD/diff 상태에서 제안/리뷰가 생성됐는지 추적 가능

3. UI 가시성
- \"현재 프로젝트\"가 없으면 프로액티브/자동작업 카드의 의미가 약해짐

### 6-2. 최소 데이터 모델 (초안)

- `projectId`: 안정 식별자 (`repoRootRealpath` 해시 권장)
- `workspaceId`: 상위 워크스페이스
- `repoRootPath`: 로컬 저장소 루트
- `defaultBranch`: 기본 브랜치
- `lastScannedHeadSHA`: 마지막 스캔 기준 커밋
- `scanPolicy`: 자동 스캔 on/off, 제외 경로, diff 상한
- `projectMemory`: repo 전용 메모리/코딩 컨벤션/주의사항

저장 경로 예시:
- `~/Library/Application Support/Dochi/workspaces/{wsId}/projects/{projectId}/`
  - `project.json`
  - `memory.md`
  - `scan_policy.json`
  - `scan_history.json`

### 6-3. 서비스/도구 연동 포인트

1. `SessionContext` 확장
- `currentProjectId`, `currentRepoPath`, `currentBranch` 추가

2. `ContextService` 확장
- `loadProjectMemory/saveProjectMemory`
- `loadProjectPolicy/saveProjectPolicy`
- `listProjects/registerProject/switchProject`

3. Git/코딩 도구 기본값 변경
- `git.*`, `coding.review`, `coding.run_task`가 `repo_path/work_dir` 미입력 시 `SessionContext.currentRepoPath`를 기본 사용

4. 자원 자동작업/프로액티브 연동
- 유휴 토큰 배분 판단과 Git 스캔 dedupe 키를 `projectId` 기준으로 계산

### 6-4. UI 최소 요구사항

1. 전역 프로젝트 컨텍스트 표시
- 상단 바에 `현재 workspace / project / branch` 노출

2. 프로젝트 선택기
- 최근 repo 목록, 현재 브랜치, 마지막 스캔 상태 표시

3. 프로젝트별 자동화 카드
- 유휴 토큰 기반 스캔/리뷰 제안이 \"어느 repo에 대한 것인지\" 명시

4. 스캔 제외/정책 편집 UI
- 대규모 모노레포, 바이너리 중심 repo 등을 프로젝트별로 제외 가능

## 7) 그룹별 전체 툴 목록 (현재 코드 기준)

### agent (17)
`agent.check_status`, `agent.config_get`, `agent.config_update`, `agent.create`, `agent.delegate_task`, `agent.delegation_status`, `agent.list`, `agent.memory_append`, `agent.memory_get`, `agent.memory_replace`, `agent.memory_update`, `agent.persona_delete_lines`, `agent.persona_get`, `agent.persona_replace`, `agent.persona_search`, `agent.persona_update`, `agent.set_active`

### alarm (3)
`cancel_alarm`, `list_alarms`, `set_alarm`

### app (1)
`app.guide`

### calculator (1)
`calculate`

### calendar (3)
`calendar.create_event`, `calendar.delete_event`, `calendar.list_events`

### clipboard (2)
`clipboard.read`, `clipboard.write`

### coding (6)
`coding.review`, `coding.run_task`, `coding.session_end`, `coding.session_pause`, `coding.session_start`, `coding.sessions`

### contacts (2)
`contacts.get_detail`, `contacts.search`

### context (1)
`context.update_base_system_prompt`

### datetime (1)
`datetime`

### dochi (5)
`dochi.bridge_open`, `dochi.bridge_read`, `dochi.bridge_send`, `dochi.bridge_status`, `dochi.log_recent`

### external_tool (6)
`external_tool.dispatch`, `external_tool.read_output`, `external_tool.register`, `external_tool.start`, `external_tool.status`, `external_tool.stop`

### file (7)
`file.copy`, `file.delete`, `file.list`, `file.move`, `file.read`, `file.search`, `file.write`

### finder (3)
`finder.get_selection`, `finder.list_dir`, `finder.reveal`

### git (5)
`git.branch`, `git.commit`, `git.diff`, `git.log`, `git.status`

### github (4)
`github.create_issue`, `github.create_pr`, `github.list_issues`, `github.view`

### image (2)
`generate_image`, `print_image`

### kanban (8)
`kanban.add_card`, `kanban.card_history`, `kanban.create_board`, `kanban.delete_card`, `kanban.list`, `kanban.list_boards`, `kanban.move_card`, `kanban.update_card`

### memory (2)
`save_memory`, `update_memory`

### music (4)
`music.next`, `music.now_playing`, `music.play_pause`, `music.search_play`

### profile (5)
`profile.add_alias`, `profile.create`, `profile.merge`, `profile.rename`, `set_current_user`

### reminders (3)
`complete_reminder`, `create_reminder`, `list_reminders`

### screenshot (1)
`screenshot.capture`

### search (1)
`web_search`

### settings (6)
`settings.get`, `settings.list`, `settings.mcp_add_server`, `settings.mcp_remove_server`, `settings.mcp_update_server`, `settings.set`

### shell (1)
`shell.execute`

### telegram (6)
`telegram.enable`, `telegram.get_me`, `telegram.send_media_group`, `telegram.send_message`, `telegram.send_photo`, `telegram.set_token`

### terminal (1)
`terminal.run`

### timer (3)
`cancel_timer`, `list_timers`, `set_timer`

### tools (4)
`tools.enable`, `tools.enable_ttl`, `tools.list`, `tools.reset`

### url (1)
`open_url`

### workflow (6)
`workflow.add_step`, `workflow.create`, `workflow.delete`, `workflow.history`, `workflow.list`, `workflow.run`

### workspace (5)
`workspace.create`, `workspace.join_by_invite`, `workspace.list`, `workspace.regenerate_invite_code`, `workspace.switch`

## 8) 근거 파일

- 툴 정의/등록: `Dochi/Services/Tools/BuiltInToolService.swift`, `Dochi/Services/Tools/ToolRegistry.swift`, `Dochi/Services/Tools/*.swift`
- 동적 추가(런타임): `Dochi/App/DochiApp.swift` (`ExternalToolTools.register`, `DochiDevBridgeTools.register`)
- UI/탐색 진입점: `Dochi/Views/Settings/ToolsSettingsView.swift`, `Dochi/Views/CapabilityCatalogView.swift`, `Dochi/Views/SlashCommandPopoverView.swift`, `Dochi/Models/FeatureSuggestion.swift`
- 민감 도구 승인 UX: `Dochi/Views/ContentView.swift` (`ToolConfirmationBannerView`)
- 프로액티브 제안: `Dochi/Services/ProactiveSuggestionService.swift`, `Dochi/Views/Settings/ProactiveSuggestionSettingsView.swift`, `Dochi/Views/SuggestionBubbleView.swift`, `Dochi/Views/SuggestionToastView.swift`
- 유휴자원/구독 최적화: `Dochi/Services/ResourceOptimizerService.swift`, `Dochi/Models/ResourceOptimizerModels.swift`, `Dochi/Views/Settings/UsageDashboardView.swift`, `Dochi/Services/HeartbeatService.swift`
