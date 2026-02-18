# Dochi Execution Context (Issue-Driven)

## Meta
- DRI: @hckim
- 상태: Active
- 생성: 2026-02-18
- 갱신: 2026-02-18
- 목적: 매 이슈 작업 시 코드베이스 전체 재탐색 없이 바로 실행 가능한 단일 컨텍스트 문서

---

## 0. 문서 사용 규칙

이 문서는 `실행용 정본`이다.

1. 구현 완료 내용은 짧게 유지한다.
2. 구현할 내용은 이슈 단위로 상세하게 유지한다.
3. 이슈 생성/작업/리뷰는 이 문서 기준으로 진행한다.
4. 전략/비전 문서는 참고용이고, 실행 우선순위는 여기서 결정한다.

---

## 1. 현재 상태 (축약)

## 1.1 동작 중인 핵심
1. 텍스트 채팅: SSE 스트리밍 + 다중 LLM 프로바이더
2. 음성 상호작용: STT/웨이크워드/barge-in 기본 플로우
3. 도구 실행: 카테고리 기반 권한 + 확인 UX
4. 기본 프로액티브: Heartbeat/ProactiveSuggestion/알림/메뉴바 노출
5. 설정/사이드바/대화/칸반/터미널/MCP 등 주요 UI 뼈대

## 1.2 미완/정리 필요 핵심
1. 온보딩 이후 활성화 루프 부족
2. 가족형 홈 어시스턴트 운영 정책 미완성
3. 프로액티브 정책/설정 모델 이중화
4. 설정 UX 일관성 결함
5. 일부 고급 기능(동기화 실체, TTS ONNX 실운영) 마무리 필요

---

## 2. 작업 시작 전 최소 컨텍스트

각 이슈 시작 시 아래만 확인하면 된다.

1. 아키텍처 진입점
   - `Dochi/App/DochiApp.swift`
   - `Dochi/ViewModels/DochiViewModel.swift`
   - `Dochi/Models/AppSettings.swift`
2. 프로액티브/하트비트
   - `Dochi/Services/ProactiveSuggestionService.swift`
   - `Dochi/Services/HeartbeatService.swift`
   - `Dochi/App/NotificationManager.swift`
3. UX 핵심 화면
   - `Dochi/Views/OnboardingView.swift`
   - `Dochi/Views/ContentView.swift`
   - `Dochi/Views/SuggestionBubbleView.swift`
   - `Dochi/Views/SettingsView.swift`
   - `Dochi/Views/Settings/ProactiveSuggestionSettingsView.swift`
4. 테스트 기준
   - `DochiTests/ProactiveSuggestionTests.swift`
   - `DochiTests/OnboardingGuideTests.swift`
   - `DochiTests/NotificationCenterTests.swift`

---

## 3. UX 일관성 계약 (반드시 준수)

## 3.1 운영 원칙
1. 기본 프로필은 `가족 홈 어시스턴트형`
2. 제안은 적극적으로, 실행은 허락 기반으로
3. 설정 부족은 앱이 먼저 알려주고 복구 동선을 제공
4. 같은 의미의 설정은 한 곳에서만 최종 제어

## 3.2 제안 UX
1. 제안 카드에는 근거(왜 지금) 1줄 표시
2. 액션은 항상 `지금 하기 / 나중에 / 유형 끄기`
3. 동일 source의 중복 제안은 24시간 내 금지
4. 야간 시간은 요약형 제안만 허용

## 3.3 설정 UX
1. 마스터 토글이 포함된 섹션은 마스터 자체가 disabled 되면 안 된다.
2. 채널 설정은 단일 정책으로 통합되어야 한다.
3. 사용자가 “왜 비활성인지”를 UI에서 즉시 이해할 수 있어야 한다.

## 3.4 가족 UX
1. 아동 프로필은 제안 빈도/범위를 보수적으로
2. 민감 작업은 보호자 확인 필수
3. 리마인더/칸반 등록 시 대상자(누구를 위한 항목) 표기

---

## 4. 이슈 운영 방식 (GitHub)

## 4.1 이슈 템플릿
제목 규칙:
- `[P{0|1|2}][영역] 한 줄 목적`
- 예: `[P0][Proactive] 일일 캡 정책 실적용`

본문 템플릿:
1. Problem
2. Scope
3. Out of Scope
4. Files to Touch
5. Acceptance Criteria
6. Test Plan
7. UX Notes
8. Risk / Rollback

## 4.2 라벨 규칙
1. Priority: `p0`, `p1`, `p2`
2. Domain: `onboarding`, `proactive`, `heartbeat`, `settings`, `family`, `sync`, `tts`
3. Type: `feature`, `fix`, `refactor`, `test`, `docs`

## 4.3 완료 조건 (Definition of Done)
1. 수용 기준 충족
2. 관련 테스트 추가/수정
3. UX 계약 위반 없음
4. 문서(이 파일) 업데이트

---

## 5. 실행 백로그 (상세, 이슈 바로 생성 가능)

## EPIC A — Activation & Family Profile

### A1. [P0][Onboarding] 운영 프로필 선택 + 기본값 가족형
- Problem: 온보딩 완료 후 행동 모드가 불명확
- Scope:
  1. 온보딩 단계에 운영 프로필 선택 추가
  2. 기본 선택을 가족 홈 어시스턴트형으로 지정
- Files:
  - `Dochi/Views/OnboardingView.swift`
  - `Dochi/Models/AppSettings.swift`
- Acceptance Criteria:
  1. 신규 사용자 첫 실행 시 프로필 선택을 거친다.
  2. 미선택 시 가족형이 기본 저장된다.
  3. 설정에서 프로필 변경 가능하다.
- Test Plan:
  - 온보딩 저장 테스트, 기본값 테스트

### A2. [P0][Onboarding] Quick Seed (리마인더/칸반/자동화 1개)
- Problem: 설치 직후 앱이 움직일 재료가 부족
- Scope:
  1. 온보딩에서 최소 1개 seed 항목 생성
  2. 실패 시 재시도 카드 제공
- Files:
  - `Dochi/Views/OnboardingView.swift`
  - `Dochi/Services/Tools/RemindersTool.swift`
  - `Dochi/Services/Tools/KanbanTool.swift`
  - `Dochi/Services/SchedulerService.swift`
- Acceptance Criteria:
  1. 온보딩 종료 시 seed 리소스 최소 1개 보유
  2. 생성 실패는 온보딩 블로킹 없이 복구 가능
- Test Plan:
  - 시딩 성공/실패 경로 테스트

### A3. [P1][Activation] Setup Health Score + 복구 배너
- Problem: 설정 미흡 상태를 사용자가 파악하기 어려움
- Scope:
  1. Health Score 계산 모델 추가
  2. 부족 설정 배너 + 원클릭 이동
- Files:
  - `Dochi/Models/AppSettings.swift`
  - `Dochi/Views/ContentView.swift`
  - `Dochi/Views/SettingsView.swift`
- Acceptance Criteria:
  1. 점수(0~100) 표시
  2. required 미충족 시 배너 노출
  3. 클릭 시 관련 설정 섹션 이동

---

## EPIC B — Proactive Policy Integrity

### B1. [P0][Proactive] 일일 캡 실적용
- Problem: `todaySuggestionCount`는 증가만 하고 제한이 없음
- Scope:
  1. `proactiveDailyCap` 설정 추가
  2. 캡 도달 시 생성 중단 + 상태 기록
- Files:
  - `Dochi/Models/AppSettings.swift`
  - `Dochi/Services/ProactiveSuggestionService.swift`
- Acceptance Criteria:
  1. 캡 도달 후 같은 날 신규 제안 생성 안 됨
  2. 자정 이후 카운트 리셋
  3. 설정에서 캡 변경 가능
- Test Plan:
  - 캡 전/후/자정 리셋 테스트

### B2. [P0][Proactive] 활동 신호 확장
- Problem: activity 리셋이 메시지 전송 중심
- Scope:
  1. 대화 선택/입력 포커스/명령 실행 등에서 activity 기록
  2. 유휴 판정 정확도 개선
- Files:
  - `Dochi/ViewModels/DochiViewModel.swift`
  - `Dochi/Views/ContentView.swift`
  - `Dochi/Services/ProactiveSuggestionService.swift`
- Acceptance Criteria:
  1. 주요 상호작용이 idle timer에 반영
  2. 오탐 제안 감소

### B3. [P0][Settings] 프로액티브 알림 정책 단일화
- Problem: `suggestionNotificationChannel` vs `notificationProactiveSuggestionEnabled` 이중 정책
- Scope:
  1. 정책 소스 단일화
  2. UI와 런타임 로직 동일 규칙 적용
- Files:
  - `Dochi/Models/AppSettings.swift`
  - `Dochi/App/DochiApp.swift`
  - `Dochi/App/NotificationManager.swift`
  - `Dochi/Services/Telegram/TelegramProactiveRelay.swift`
  - `Dochi/Views/Settings/ProactiveSuggestionSettingsView.swift`
- Acceptance Criteria:
  1. 앱/텔레그램/둘다/끄기의 동작이 예측 가능
  2. 중복 토글 제거 또는 명확한 종속 설명

---

## EPIC C — Settings UX Consistency

### C1. [P0][Settings] 마스터 토글 disabled 결함 수정
- Problem: 프로액티브 마스터 토글이 off 상태에서 눌리지 않는 UX 결함
- Scope:
  1. 섹션 disabled 범위 재조정
- Files:
  - `Dochi/Views/SettingsView.swift`
- Acceptance Criteria:
  1. 마스터 토글은 항상 인터랙션 가능
  2. 하위 옵션만 조건부 disabled
- Test Plan:
  - UI 상태 전환 테스트

### C2. [P1][Settings] 프로액티브 설정 진입점 정리
- Problem: 일반 설정/전용 설정 화면 중복으로 책임 불명확
- Scope:
  1. 단일 주 설정 화면을 정함
  2. 나머지는 링크/요약 역할로 축소
- Files:
  - `Dochi/Views/SettingsView.swift`
  - `Dochi/Views/Settings/ProactiveSuggestionSettingsView.swift`
- Acceptance Criteria:
  1. 사용자 입장에서 설정 위치가 한 번에 이해됨
  2. 동일 설정이 두 화면에서 충돌하지 않음

---

## EPIC D — Heartbeat to TaskOpportunity

### D1. [P1][Heartbeat] TaskOpportunity 모델 도입
- Problem: Heartbeat가 알림 생성에 머물고 행동 단위가 약함
- Scope:
  1. 점검 결과를 행동 후보로 표준화
  2. 제안 카드로 연결
- Files:
  - `Dochi/Services/HeartbeatService.swift`
  - `Dochi/Models/*` (TaskOpportunity 신규)
  - `Dochi/Views/SuggestionBubbleView.swift`
- Acceptance Criteria:
  1. Heartbeat 결과가 최소 1개 구조화된 후보로 생성 가능
  2. 후보에서 리마인더/칸반 등록 제안 가능

---

## EPIC E — Foundation Completion (기존 TODO 마무리)

### E1. [P1][Sync] 동기화 실체 구현
### E2. [P1][TTS] ONNX 모델 실운영 경로
### E3. [P2][Telegram] 스트리밍 응답 편집
### E4. [P2][Device] 디바이스 상태 관리 UI/heartbeat

상세 스펙은 기존 문서 링크:
- `spec/supabase.md`
- `spec/voice-and-audio.md`
- `spec/tech-spec.md`

---

## EPIC F — CLI & Debugging Control Plane

목적: Dochi를 GUI와 동등한 **정식 CLI 인터페이스**로 제공하고, 개발 디버깅 생산성도 함께 개선한다.

### F0. 아키텍처 결정 (ADR)
- 결론:
  1. CLI는 디버깅 부가 기능이 아니라 Phase 6의 정식 인터페이스로 취급한다.
  2. 단순 파일 조회/설정 편집은 API 없이 가능하지만, `세션 관리/채팅/도구 실행/실시간 로그`는 앱 프로세스 상태 접근이 필요하다.
  3. 따라서 앱 로컬 API(Control Plane)는 디버깅뿐 아니라 정식 CLI UX를 위해 필요하다.
  4. 원격 서버형 API는 범위 밖. macOS 로컬 전용으로 시작한다.
- 전송 방식:
  1. 1차는 Unix Domain Socket (`~/Library/Application Support/Dochi/run/dochi.sock`) + JSON-RPC 스타일
  2. TCP/HTTP 공개 포트는 초기 범위에서 제외
- 운영 모드:
  1. App-Connected 모드(기본): 실행 중인 Dochi 앱과 연결, 로컬 컨텍스트/도구/세션 활용
  2. Standalone 모드(제한): 앱 미실행 시 직접 LLM 질의 등 제한 기능만 허용
- 언어 결정:
  1. 1차 구현은 기존 `DochiCLI`(Swift) 확장으로 간다.
  2. Go 재작성은 CLI 요구가 안정화된 뒤(명령/프로토콜 고정 이후) 재평가한다.

### F1. [P0][CLI] 명령 표면 재정의 (사용자/개발 공용)
- Problem: 현재 `DochiCLI/main.swift`는 단발 질의 중심이며 설정 명령 일부가 실제 구현과 불일치.
- Scope:
  1. 사용자 명령 체계 고정: `chat`, `ask`, `session`, `conversation`, `context`, `config`
  2. 개발/운영 명령은 별도 네임스페이스: `dev tool`, `dev log`, `dev bridge`, `doctor`
  3. App-Connected 모드/Standalone 모드에서 각 명령의 지원 범위를 명확히 정의
  4. 모든 명령에 `--json` 출력 옵션 추가
  5. 에러 코드 정책 표준화 (사용자 입력 오류/연결 오류/권한 오류)
- Files:
  - `DochiCLI/main.swift`
  - `DochiCLI/*` (파서 분리 시)
- Acceptance Criteria:
  1. `dochi --help`가 실제 구현된 명령만 노출
  2. 설정 명령(`config set/show`)이 정상 동작
  3. 사용자 명령과 개발 명령이 도움말에서 명확히 분리 표시
  4. CI에서 기본 명령 스모크 테스트 통과

### F2. [P0][App] 로컬 Control Plane v0
- Problem: CLI가 앱 내부 상태(세션/도구/로그)에 접근할 경로가 없음.
- Scope:
  1. 앱 부팅 시 로컬 소켓 서버 시작/종료
  2. v0 메서드 제공:
     - `app.ping`
     - `session.list`
     - `chat.send` (single-shot)
     - `tool.execute`
     - `log.recent`
     - `bridge.open`, `bridge.status`, `bridge.send`, `bridge.read`
  3. 요청/응답에 `request_id` 포함
- Files:
  - `Dochi/App/DochiApp.swift`
  - `Dochi/ViewModels/DochiViewModel.swift`
  - `Dochi/Services/*` (Control Plane 신규)
- Acceptance Criteria:
  1. 앱 실행 중 CLI에서 `app.ping` 성공
  2. `tool.execute`로 기존 도구 1개 이상 호출 가능
  3. 실패 시 구조화된 에러 코드/메시지 반환
- 상태: done (2026-02-18)
- 구현 파일:
  - `Dochi/App/DochiApp.swift`
  - `Dochi/ViewModels/DochiViewModel.swift`
  - `Dochi/Services/ControlPlane/LocalControlPlaneService.swift`
- 테스트:
  - `DochiTests/LocalControlPlaneServiceTests.swift`

### F3. [P0][CLI] 앱 연결 모드 + graceful fallback
- Problem: 앱 미실행/권한 미설정 상태에서 실패 원인 파악이 어렵다.
- Scope:
  1. 기본 모드: 앱 연결 시 Control Plane 사용
  2. 앱 미실행 시: 명확한 오류 + 실행 가이드
  3. `doctor` 명령에서 연결 상태 및 권한 점검
- Files:
  - `DochiCLI/main.swift`
  - `DochiCLI/*`
- Acceptance Criteria:
  1. 앱 미실행 시 3초 내 실패 + 안내 출력
  2. `dochi doctor`로 최소 점검 항목 5개 출력
  3. 재현 가능한 종료 코드 체계 유지

### F4. [P1][Debug] 실시간 이벤트/로그 스트림
- Problem: 현재는 단발 로그 조회 중심이라 디버깅 루프가 느림.
- Scope:
  1. `chat.stream` 이벤트 스트림(부분 응답/도구 호출/완료)
  2. `log.tail` (category/level/filter)
  3. 이벤트 correlation id 부여
- Files:
  - `Dochi/ViewModels/DochiViewModel.swift`
  - `Dochi/Utilities/Log.swift`
  - `DochiCLI/*`
- Acceptance Criteria:
  1. CLI에서 스트림 모드로 응답 진행률 확인 가능
  2. 도구 실행 이벤트와 로그를 동일 ID로 추적 가능

### F5. [P1][Security] 로컬 API 접근 제어
- Problem: 로컬 소켓이라도 동일 사용자 세션 내 오용 가능성 존재.
- Scope:
  1. 소켓 파일 권한 엄격화 (`0600`)
  2. 로컬 세션 토큰(회전 가능) 검증
  3. 민감/제한 도구에 기존 사용자 확인 정책 재사용
- Files:
  - `Dochi/Services/*` (Control Plane)
  - `Dochi/Services/Tools/BuiltInToolService.swift`
- Acceptance Criteria:
  1. 권한 없는 요청 거부
  2. 민감 도구 호출 시 앱 정책과 동일한 확인 흐름 보장

---

## 6. 스프린트 제안 (작업 순서)

1. Sprint 0 (CLI Debug Track): F1, F2, F3
2. Sprint 1: A1, B1, C1, B3
3. Sprint 2: A2, A3, B2, C2
4. Sprint 3: D1 + E1 착수
5. Sprint 4 (CLI 확장): F4, F5

이 순서를 유지하면 UX 일관성과 활성화 지표를 빠르게 개선할 수 있다.

---

## 7. 변경 관리

각 이슈 완료 후 이 문서에서 다음 2가지만 갱신:
1. 해당 항목 상태 (`todo` -> `done`)
2. 구현 파일/테스트 링크

문서 분산을 막기 위해, 실행 관련 신규 문서 추가는 원칙적으로 금지한다.
