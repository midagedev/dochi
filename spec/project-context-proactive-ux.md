# Project Context + Proactive/Idle Token UX Spec (MVP)

작성일: 2026-02-18  
이슈: #244

## 1) 목적

현재 기능(프로액티브 제안, 유휴 토큰 최적화, Git 스캔 자동화)은 존재하지만 노출 지점이 분산되어 사용자가 상태를 즉시 파악하기 어렵다.

본 문서는 아래를 제품 메인 플로우에 자연스럽게 녹이는 UX MVP를 정의한다.

- 현재 작업 컨텍스트 (`workspace / project / branch`)
- 프로액티브 상태 (`idle / analyzing / cooldown`, 일일 잔여량)
- 유휴 토큰/낭비 위험 상태
- Git 스캔 후보와 즉시 액션

## 2) 정보 구조 (IA)

권장 컨텍스트 계층:

- `user -> workspace -> project(repo) -> agent`

UI 노출 우선순위:

1. 항상 보이는 정보 (상단 바)
2. 지금 액션 가능한 정보 (대화 하단 버블/카드)
3. 상세/설정 정보 (설정 화면)

## 3) 핵심 컴포넌트

### A. Project Context Strip (상단)

노출 위치:
- `SystemHealthBarView` 하단 또는 상태바 근접 위치 (상시)

표시 항목:
- workspace 이름
- project 이름(또는 repo basename)
- branch
- 동기화/스캔 최신성 배지 (`updated`, `stale`, `unknown`)

클릭 액션:
- Project Switcher 열기

Empty state:
- `프로젝트 미선택` + `프로젝트 선택` 버튼

Error state:
- repo 경로 접근 실패 시 `경로 확인 필요` 배지

### B. Idle Token Risk Widget (상단 또는 우측)

노출 위치:
- 상단 bar 축약 뷰 + 상세 popover

표시 항목:
- 구독명
- 사용량 비율
- 예상 미사용 비율
- 리셋까지 남은 일수
- 위험도 (`comfortable / caution / wasteRisk / normal`)

강조 규칙:
- `wasteRisk`: 빨강 + CTA 노출
- `caution`: 노랑 + 추천 CTA

Empty state:
- 등록된 구독 없음 -> `구독 추가` 링크

### C. Git Scan Candidate Card (대화 하단)

노출 조건:
- 현재 project가 Git repo
- 변경사항 존재 (`git diff --stat` non-empty)
- 자동 스캔 조건 충족 또는 수동 제안 조건 충족

표시 항목:
- 변경 파일 수/라인 요약
- 마지막 스캔 시각
- 위험도/우선순위
- 권장 실행 도구 (`coding.review`)

액션:
- `지금 스캔`
- `나중에`
- `이 저장소 제외`

Error state:
- git 명령 실패 -> 카드 내 원인 요약 + `터미널에서 열기`

### D. Proactive Status Capsule (상단)

표시 항목:
- 상태: `idle / analyzing / cooldown`
- 다음 제안 가능 시점(쿨다운 남은 시간)
- 일일 한도: `사용/총량`

행동 유도:
- `상세 설정` 바로가기
- `일시중지/재개`

### E. Unified Activity Timeline (설정/상세)

통합 대상:
- 프로액티브 제안 이력
- 자원 자동작업 큐/실행 결과
- Git 스캔 실행 결과

목표:
- “무엇이 왜 실행되었는지”를 한 타임라인에서 추적

## 4) 상태값 매핑

### 서비스 -> UI 매핑

- `ProactiveSuggestionService.state`
  - `disabled` -> 비활성
  - `idle` -> 대기
  - `analyzing` -> 분석 중
  - `hasSuggestion` -> 제안 있음
  - `cooldown` -> 쿨다운
  - `error` -> 오류 배지

- `ResourceUtilization.riskLevel`
  - `comfortable` -> 여유
  - `normal` -> 정상
  - `caution` -> 주의
  - `wasteRisk` -> 낭비 위험

- Git 스캔 상태 (신규 제안)
  - `notEligible` / `candidate` / `queued` / `running` / `done` / `failed`

### AppSettings 키 매핑 (구현 기준)

| UI 항목 | 설정 키 | 비고 |
|---|---|---|
| 프로액티브 활성화 | `proactiveSuggestionEnabled` | 마스터 토글 |
| 유휴 감지 분 | `proactiveSuggestionIdleMinutes` | `idle` 진입 임계값 |
| 쿨다운 분 | `proactiveSuggestionCooldownMinutes` | 제안 후 재생성 제한 |
| 일일 한도 | `proactiveDailyCap` | 0이면 생성 안 함 |
| 조용한 시간 적용 | `proactiveSuggestionQuietHoursEnabled` | 하트비트 조용한 시간 공유 |
| 제안 채널 | `suggestionNotificationChannel` | off/app/telegram/both |
| 메뉴바 노출 | `proactiveSuggestionMenuBarEnabled` | 메뉴바 카드 표시 |
| 자동작업 활성 | `resourceAutoTaskEnabled` | 자원 자동작업 마스터 토글 |
| 낭비위험만 실행 | `resourceAutoTaskOnlyWasteRisk` | 필터 토글 |
| 자동작업 타입 | `resourceAutoTaskTypes` | 선택된 작업 집합 |

## 5) UX 규칙

### 노출 최소 원칙

- 상단에는 "상태 요약"만, 상세는 popover/sheet에서 제공
- 대화 입력 영역을 가리지 않도록 하단 카드 1개 우선 노출
- 동일한 Git 스캔 제안은 동일 변경집합에서는 중복 노출 금지

### 피로도 제어

- `wasteRisk`가 아닌 경우 강한 경고색 최소화
- 쿨다운 중에는 CTA를 억제하고 상태만 표시
- dismiss/제외 선택은 프로젝트 단위로 기억

### Git 스캔 노출 억제 규칙 (우선순위)

1. 프로젝트 제외 정책이 있으면 항상 미노출
2. 동일 `repo+branch+headSHA+diffHash`가 최근 실행 이력에 있으면 미노출
3. 쿨다운 기간 내 동일 프로젝트 반복 노출 금지
4. 대규모 diff/바이너리 비중 초과 시 자동 후보 미노출 (수동 실행만 허용)

## 6) 이벤트/계측 (MVP)

필수 이벤트:
- `project_context_switched`
- `idle_token_widget_opened`
- `git_scan_candidate_shown`
- `git_scan_action_clicked` (now/later/exclude)
- `proactive_state_viewed`
- `proactive_action_clicked` (accept/defer/dismissType)

측정 지표:
- Git 스캔 제안 노출 대비 실행 전환율
- 위험 상태(`wasteRisk`) 대비 액션 전환율
- 제안 수락률 및 유형별 효용

## 7) 개발 연동 체크리스트

- [ ] `SessionContext`에 project 컨텍스트 필드 추가
- [ ] 프로젝트 선택/전환 API (`ContextService`) 정의
- [ ] SystemHealthBar에 Project/Proactive/Idle 요약 노출 훅 추가
- [ ] Git 스캔 후보 카드 UI + 액션 핸들러 추가
- [ ] 자동작업/제안 이력 통합 뷰 모델 추가
- [ ] 중복 노출 방지 키(`repo+branch+head+diffHash`) 적용

## 8) 비범위 (MVP)

- 다중 repo 동시 가시화
- 조직 단위 정책 템플릿
- 복잡한 브랜치 그래프 시각화
