# UX 명세: [J-3] 스케줄 기반 자동화 트리거

> 상태: 설계 완료
> 관련: HeartbeatService, WorkflowManager, NotificationManager

---

## 1. 개요

사용자가 크론식 스케줄을 등록하여 에이전트를 자동 실행하고, 결과를 알림으로 받는 기능.
기존 HeartbeatService의 "주기적 점검" 개념을 확장하여, **사용자 정의 시간에 사용자 정의 작업**을 실행하는 범용 자동화 시스템.

### 핵심 시나리오
- "매일 아침 9시에 오늘 일정과 미리알림을 정리해서 브리핑해줘"
- "매주 금요일 오후 5시에 칸반 보드 진행 상황 리포트 작성해줘"
- "매일 자정에 메모리 정리해줘"

---

## 2. 진입점 (Discoverability)

### 2-1. 설정 사이드바

| 위치 | 그룹 "일반" → 기존 "하트비트" 섹션 아래 |
|------|------|
| 섹션 이름 | `자동화` (rawValue: `automation`) |
| 아이콘 | `clock.arrow.2.circlepath` |
| 파일 | `Views/Settings/AutomationSettingsView.swift` (신규) |

SettingsSidebarView에 "일반" 그룹 내 "하트비트" 아래에 배치:
```
일반 그룹:
  인터페이스
  웨이크워드
  하트비트
  자동화        ← 신규
```

### 2-2. 커맨드 팔레트 (⌘K)

| 명령 | 동작 |
|------|------|
| "자동화 설정" | 설정 > 자동화 섹션 열기 |
| "새 자동화 추가" | AutomationSettingsView 열기 + 추가 시트 자동 표시 |
| "자동화 실행 기록" | AutomationSettingsView 열기 (실행 기록 섹션 스크롤) |

### 2-3. SystemHealthBarView 연동

기존 하트비트 인디케이터 옆에 **활성 스케줄 수** 표시 안 함 (복잡도 증가 대비 가치 낮음).
대신 하트비트 상태 시트(SystemStatusSheetView) 하트비트 탭에 "활성 자동화: N개" 요약 1줄 추가.

---

## 3. 데이터 모델

### 3-1. ScheduleEntry

파일: `Dochi/Models/ScheduleEntry.swift` (신규)

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `id` | `UUID` | 고유 ID |
| `name` | `String` | 스케줄 이름 (예: "아침 브리핑") |
| `icon` | `String` | SF Symbols 아이콘 |
| `cron` | `String` | 크론 표현식 (5필드: 분 시 일 월 요일) |
| `prompt` | `String` | 에이전트에게 전달할 프롬프트 |
| `agentName` | `String?` | 실행할 에이전트 (nil = 현재 활성 에이전트) |
| `workspaceId` | `UUID?` | 실행할 워크스페이스 (nil = 현재 활성) |
| `enabled` | `Bool` | 활성화 여부 |
| `notifyResult` | `Bool` | 결과를 알림으로 전송할지 (기본: true) |
| `saveToConversation` | `Bool` | 결과를 대화에 기록할지 (기본: true) |
| `templateId` | `String?` | 기본 템플릿 출처 ID (커스텀이면 nil) |
| `createdAt` | `Date` | 생성 시각 |
| `updatedAt` | `Date` | 수정 시각 |
| `lastRunAt` | `Date?` | 마지막 실행 시각 |
| `lastRunSuccess` | `Bool?` | 마지막 실행 성공 여부 |

### 3-2. ScheduleExecutionLog

| 프로퍼티 | 타입 | 설명 |
|----------|------|------|
| `id` | `UUID` | 실행 기록 ID |
| `scheduleId` | `UUID` | 스케줄 ID |
| `scheduleName` | `String` | 스케줄 이름 (삭제 후에도 표시) |
| `timestamp` | `Date` | 실행 시각 |
| `success` | `Bool` | 성공 여부 |
| `resultSummary` | `String` | 결과 요약 (최대 300자) |
| `errorMessage` | `String?` | 오류 메시지 |
| `durationSeconds` | `TimeInterval` | 소요 시간 |

### 3-3. ScheduleTemplate (기본 제공)

| templateId | 이름 | 아이콘 | 크론 | 프롬프트 |
|------------|------|--------|------|----------|
| `morning-briefing` | 아침 브리핑 | `sun.horizon` | `0 9 * * *` | 오늘 캘린더 일정, 미리알림, 날씨를 정리해서 브리핑해줘. |
| `weekly-report` | 주간 리포트 | `chart.bar.doc.horizontal` | `0 17 * * 5` | 이번 주 칸반 보드 진행 상황을 요약해서 리포트를 작성해줘. |
| `memory-cleanup` | 정기 메모리 정리 | `brain.head.profile` | `0 0 * * *` | 메모리를 정리하고 중복/오래된 항목을 아카이브해줘. |
| `daily-review` | 하루 리뷰 | `moon.stars` | `0 22 * * *` | 오늘 대화 내용을 돌아보고 중요한 사항을 메모리에 정리해줘. |

---

## 4. 뷰 설계

### 4-1. AutomationSettingsView (메인)

파일: `Views/Settings/AutomationSettingsView.swift`

```
┌──────────────────────────────────────────────────────┐
│  ⚙️ 자동화                                    [?]    │
├──────────────────────────────────────────────────────┤
│                                                      │
│  Section: 자동화 스케줄                               │
│  ┌──────────────────────────────────────────────────┐│
│  │  Toggle: 자동화 활성화                   [●━━━]  ││
│  │  (비활성 시 모든 스케줄 일시정지)                    ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  Section: 등록된 스케줄 (N개)            [+ 추가]     │
│  ┌──────────────────────────────────────────────────┐│
│  │  ☀️ 아침 브리핑           매일 09:00    [●]  ⋯   ││
│  │     다음 실행: 내일 09:00                         ││
│  ├──────────────────────────────────────────────────┤│
│  │  📊 주간 리포트          매주 금 17:00   [●]  ⋯   ││
│  │     마지막 실행: 2일 전 ✅                         ││
│  ├──────────────────────────────────────────────────┤│
│  │  🧠 정기 메모리 정리      매일 00:00    [○]  ⋯   ││
│  │     비활성                                        ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  Section: 최근 실행 기록                               │
│  ┌──────────────────────────────────────────────────┐│
│  │  ✅ 아침 브리핑  오늘 09:00  (2.3초)              ││
│  │  ✅ 주간 리포트  어제 17:00  (4.1초)              ││
│  │  ❌ 메모리 정리  2일 전     LLM 호출 실패          ││
│  │  ...                                              ││
│  │            [모두 지우기]                           ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  Section: HeartbeatService 연동                       │
│  ┌──────────────────────────────────────────────────┐│
│  │  ℹ️ 자동화 스케줄은 하트비트와 별도로 동작합니다.   ││
│  │  하트비트: [상태 표시] → [하트비트 설정 열기]       ││
│  └──────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────┘
```

#### 스케줄 행 상세

각 스케줄 행(ScheduleRowView)은:
- **좌측**: 아이콘 (28x28, 원형 배경)
- **중앙 상단**: 이름 + 크론 사람이 읽을 수 있는 설명 (예: "매일 09:00", "매주 금요일 17:00")
- **중앙 하단**: 상태 텍스트
  - 활성 + 실행 전: "다음 실행: {날짜시간}" (회색)
  - 활성 + 실행 후: "마지막 실행: {상대시간} {✅/❌}" (회색/빨강)
  - 비활성: "비활성" (회색 이탤릭)
  - 실행 중: "실행 중..." (파란색 + 스피너)
- **우측**: 활성화 토글 (Toggle, compact)
- **더보기 메뉴** (⋯): 편집 / 지금 실행 / 복제 / 삭제

#### 더보기 메뉴 동작

| 메뉴 | 동작 |
|------|------|
| 편집 | ScheduleEditSheet 열기 (기존 값 로드) |
| 지금 실행 | 스케줄 즉시 실행 (테스트용), 실행 중 스피너 표시 |
| 복제 | 동일 설정으로 새 스케줄 생성 (이름 뒤에 " (복사)" 추가) |
| 삭제 | 확인 Alert → 삭제 |

### 4-2. ScheduleEditSheet (추가/편집)

파일: `Views/Settings/AutomationSettingsView.swift` 내 하위 뷰

시트 크기: 520×560pt

```
┌──────────────────────────────────────────────────────┐
│  자동화 추가                               [X 닫기]  │
├──────────────────────────────────────────────────────┤
│                                                      │
│  Section: 템플릿으로 시작 (추가 모드에서만 표시)        │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐        │
│  │ ☀️     │ │ 📊     │ │ 🧠     │ │ 🌙     │        │
│  │ 아침   │ │ 주간   │ │ 메모리 │ │ 하루   │        │
│  │ 브리핑 │ │ 리포트 │ │ 정리   │ │ 리뷰   │        │
│  └────────┘ └────────┘ └────────┘ └────────┘        │
│  (선택 시 아래 필드 자동 채움, 미선택 시 빈 폼)         │
│                                                      │
│  Section: 기본 정보                                    │
│  ┌──────────────────────────────────────────────────┐│
│  │  이름:  [________________________]               ││
│  │  아이콘: [☀️ ▾] (SF Symbol Picker, 10개 후보)    ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  Section: 실행 시간                                    │
│  ┌──────────────────────────────────────────────────┐│
│  │  반복 주기: [● 매일 ○ 매주 ○ 매월 ○ 직접 입력]    ││
│  │                                                  ││
│  │  (매일 선택 시)                                   ││
│  │  시간: [09] : [00]                               ││
│  │                                                  ││
│  │  (매주 선택 시)                                   ││
│  │  요일: [월] [화] [수] [목] [금] [토] [일]          ││
│  │  시간: [17] : [00]                               ││
│  │                                                  ││
│  │  (매월 선택 시)                                   ││
│  │  일: [1 ▾]                                       ││
│  │  시간: [09] : [00]                               ││
│  │                                                  ││
│  │  (직접 입력 선택 시)                               ││
│  │  크론식: [_______________]                        ││
│  │  해석: "매일 오전 9시" (실시간 파싱 피드백)          ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  Section: 실행 내용                                    │
│  ┌──────────────────────────────────────────────────┐│
│  │  프롬프트:                                        ││
│  │  ┌──────────────────────────────────────────────┐││
│  │  │ TextEditor (4줄 높이, 플레이스홀더:            │││
│  │  │ "에이전트에게 전달할 메시지를 입력하세요")       │││
│  │  └──────────────────────────────────────────────┘││
│  │                                                  ││
│  │  에이전트: [현재 에이전트 (도치) ▾]                ││
│  │  (워크스페이스 내 에이전트 목록 Picker)             ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  Section: 옵션                                        │
│  ┌──────────────────────────────────────────────────┐│
│  │  Toggle: 결과 알림 전송               [●━━━]     ││
│  │  Toggle: 대화에 기록                  [●━━━]     ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
│  ┌──────────────────────────────────────────────────┐│
│  │                    [취소]    [저장] (파란 강조)     ││
│  └──────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────┘
```

#### 실행 시간 UI 상세

**반복 주기 선택** (Segmented Picker):
- `매일`: 시간 Picker만 (시:분)
- `매주`: 요일 다중선택 칩 (토글) + 시간 Picker
- `매월`: 일 드롭다운 (1~28, "마지막 날") + 시간 Picker
- `직접 입력`: 크론식 TextField + 실시간 해석 텍스트

**크론식 해석 피드백**:
- 유효한 크론: "매일 오전 9시" 등 사람이 읽을 수 있는 형태 (초록색)
- 유효하지 않은 크론: "유효하지 않은 크론 표현식입니다" (빨간색)
- 빈 칸: 안내 텍스트 "분 시 일 월 요일 (예: 0 9 * * *)" (회색)

**간편 모드 → 크론 변환**:
- 매일 09:00 → `0 9 * * *`
- 매주 월,금 17:00 → `0 17 * * 1,5`
- 매월 1일 09:00 → `0 9 1 * *`
- UI에서 선택 시 내부적으로 크론식 생성, "직접 입력" 전환 시 현재 값 표시

#### 유효성 검사

| 필드 | 검사 | 에러 메시지 |
|------|------|-------------|
| 이름 | 비어있으면 안 됨 | "이름을 입력해주세요" |
| 이름 | 중복 불가 | "같은 이름의 자동화가 이미 있습니다" |
| 크론 | 파싱 가능해야 함 | "유효하지 않은 크론 표현식입니다" |
| 프롬프트 | 비어있으면 안 됨 | "실행할 프롬프트를 입력해주세요" |
| 요일 (매주) | 최소 1개 선택 | "요일을 하나 이상 선택해주세요" |

저장 버튼: 모든 유효성 통과 시만 활성화.

### 4-3. 실행 기록 섹션 상세

최대 20건 표시 (FIFO). 각 행:
- 좌측: ✅ (성공, 초록) / ❌ (실패, 빨강)
- 이름 + 실행 시각 (상대 시간) + 소요 시간
- 실패 시: 에러 메시지 (빨간 서브텍스트)
- 행 클릭: 결과 요약 팝오버 (resultSummary 전체 표시)

---

## 5. 빈 상태 / 에러 상태 / 로딩 상태

### 5-1. 빈 상태

**스케줄 0개일 때** (등록된 스케줄 섹션):

```
┌──────────────────────────────────────────────────────┐
│       🕐                                              │
│  아직 등록된 자동화가 없습니다                           │
│  정해진 시간에 에이전트를 자동으로 실행해보세요            │
│                                                      │
│        [+ 템플릿으로 시작하기]  (파란색 버튼)            │
└──────────────────────────────────────────────────────┘
```

"템플릿으로 시작하기" 클릭 → ScheduleEditSheet 열기 (템플릿 섹션 강조).

**실행 기록 0개일 때**:

```
┌──────────────────────────────────────────────────────┐
│  🕐 아직 실행 기록이 없습니다                           │
│  스케줄이 실행되면 여기에 기록됩니다                      │
└──────────────────────────────────────────────────────┘
```

### 5-2. 에러 상태

**스케줄 실행 실패 시**:
- 해당 스케줄 행의 상태 텍스트: "마지막 실행: {시간} ❌ {에러 요약}" (빨간색)
- 실행 기록에 에러 메시지 기록
- `notifyResult`가 true면 알림도 발송 (실패 알림)

**크론 파싱 실패**:
- ScheduleEditSheet에서 실시간으로 크론식 아래에 빨간 텍스트 표시
- 저장 버튼 비활성화

**LLM 호출 실패 (실행 시)**:
- 결과를 "LLM 호출 실패: {에러}" 로 기록
- 3회 연속 실패 시 해당 스케줄 자동 비활성화 + 알림: "'{이름}' 자동화가 연속 실패로 비활성화되었습니다"

### 5-3. 로딩 상태

**스케줄 실행 중** (SchedulerService 내부, UI에는 간접 반영):
- 해당 스케줄 행: 이름 옆에 작은 스피너 (ProgressView), 상태 텍스트 "실행 중..." (파란색)
- "지금 실행" 메뉴로 수동 트리거한 경우에도 동일 표시

**자동화 전체 비활성→활성 전환 시**:
- 즉각 반영 (스케줄러 restart), 별도 로딩 없음

---

## 6. 데이터 흐름

### 6-1. 스케줄 CRUD

```
AutomationSettingsView → ScheduleEditSheet
  → 저장 → SchedulerService.addSchedule(entry)
  → schedules 배열 갱신 → 파일 저장 (schedules.json)
  → SchedulerService.rescheduleAll() → 다음 실행 시간 계산
편집: 행 더보기 > 편집 → ScheduleEditSheet (기존값) → updateSchedule()
삭제: 행 더보기 > 삭제 → 확인 Alert → removeSchedule(id:) → 파일 저장
토글: 행 토글 → updateSchedule(id:, enabled:) → rescheduleAll()
```

### 6-2. 스케줄 실행

```
SchedulerService (Timer loop, 1분 주기 체크)
  → 현재 시각이 어떤 스케줄의 다음 실행 시각과 매치?
  → 매치 시: executeSchedule(entry)
    1. entry.agentName으로 에이전트 컨텍스트 로드
    2. entry.prompt → LLMService.send() (safe 도구만, 단일 턴)
    3. 결과 수신
    4. entry.saveToConversation이면 → 전용 대화에 기록
    5. entry.notifyResult이면 → NotificationManager.sendScheduleNotification()
    6. ScheduleExecutionLog 기록
    7. entry.lastRunAt / lastRunSuccess 갱신
    8. 다음 실행 시각 재계산
```

### 6-3. HeartbeatService와의 관계

```
HeartbeatService               SchedulerService
  │ 주기적 점검 (N분 간격)          │ 크론식 스케줄 (정확한 시각)
  │ 시스템 데이터 수집              │ 사용자 정의 프롬프트 실행
  │ 알림 전송                     │ LLM 호출 + 알림 전송
  └───────────────┬───────────────┘
                  │
            별도 서비스로 독립 동작
            (HeartbeatService 비활성이어도 SchedulerService 동작 가능)
            Quiet Hours는 공유: settings.heartbeatQuietHoursStart/End 존중
```

---

## 7. AppSettings 확장

| 프로퍼티 | 타입 | 기본값 | 설명 |
|----------|------|--------|------|
| `automationEnabled` | `Bool` | `false` | 자동화 전체 활성화 |

> 개별 스케줄 on/off는 ScheduleEntry.enabled로 관리 (AppSettings 아님).

---

## 8. 저장 파일

| 파일 | 경로 | 설명 |
|------|------|------|
| 스케줄 목록 | `~/Library/Application Support/Dochi/schedules.json` | ScheduleEntry 배열 |
| 실행 기록 | `~/Library/Application Support/Dochi/schedule_logs.json` | ScheduleExecutionLog 배열 (FIFO 50건) |

---

## 9. 알림 연동

### 새 알림 카테고리

| 카테고리 ID | 액션 | 설명 |
|------------|------|------|
| `dochi-schedule` | open-app, dismiss | 스케줄 실행 결과 알림 |

알림 내용 형식:
- 제목: "{스케줄이름} 완료" 또는 "{스케줄이름} 실패"
- 본문: 결과 요약 (최대 200자)
- 스레드 ID: `schedule-{scheduleId}`

---

## 10. 커맨드 팔레트 명령

| 명령 | 동작 |
|------|------|
| `자동화 설정` | openSettingsSection(section: "automation") |
| `새 자동화 추가` | 자동화 설정 열기 + ScheduleEditSheet 표시 |
| `자동화 실행 기록` | 자동화 설정 열기 |

---

## 11. 키보드 단축키

전용 글로벌 단축키 없음 (설정 내 기능이므로 ⌘, → 자동화 탭 또는 ⌘K로 접근).

---

## 12. UI 인벤토리 업데이트 사항

### 앱 구조 트리에 추가

설정 테이블에 행 추가:
```
| 일반 | 자동화 (`automation`) | clock.arrow.2.circlepath | `Views/Settings/AutomationSettingsView.swift` | 스케줄 CRUD, 기본 템플릿, 실행 기록 |
```

### ViewModel 상태 추가 (DochiViewModel)

| 프로퍼티 | 타입 | 설명 | UI 사용처 |
|----------|------|------|-----------|
| `schedulerService` | `SchedulerService?` | 스케줄 기반 자동화 서비스 | AutomationSettingsView, SystemStatusSheetView |

### 빈 상태 추가

| 상황 | 메시지 | 위치 |
|------|--------|------|
| 자동화 0개 | 아이콘 + "아직 등록된 자동화가 없습니다" + "템플릿으로 시작하기" | AutomationSettingsView |
| 실행 기록 0개 | 시계 아이콘 + "아직 실행 기록이 없습니다" | AutomationSettingsView |

### 저장 파일 추가

| 파일 | 경로 | 설명 |
|------|------|------|
| 스케줄 목록 | `~/Library/Application Support/Dochi/schedules.json` | 스케줄 엔트리 |
| 실행 기록 | `~/Library/Application Support/Dochi/schedule_logs.json` | 실행 기록 (FIFO 50건) |

### AppSettings 추가

```
| 자동화 (J-3) | `automationEnabled` |
```

### 데이터 흐름 추가

```
### 스케줄 자동화 (J-3 추가)
스케줄 CRUD: 설정 > 자동화 > [+추가] → ScheduleEditSheet → SchedulerService.addSchedule()
  → schedules.json 저장 → rescheduleAll()
스케줄 실행: SchedulerService (1분 주기 체크) → 크론 매치 → executeSchedule()
  → LLMService.send() → 결과 수신
  → saveToConversation: 전용 대화에 기록
  → notifyResult: NotificationManager.sendScheduleNotification()
  → ScheduleExecutionLog 기록 (FIFO 50건)
  → 3회 연속 실패 시 자동 비활성화 + 알림
수동 실행: 행 더보기 > "지금 실행" → 동일 흐름
설정: settings.automationEnabled → SchedulerService.start()/stop()
  → Quiet Hours는 HeartbeatService와 공유
커맨드 팔레트: "자동화 설정" / "새 자동화 추가" / "자동화 실행 기록"
```

---

## 13. 구현 파일 목록

| 파일 | 유형 | 설명 |
|------|------|------|
| `Dochi/Models/ScheduleEntry.swift` | 신규 | ScheduleEntry, ScheduleExecutionLog, ScheduleTemplate 모델 |
| `Dochi/Services/SchedulerService.swift` | 신규 | 크론 파싱, 스케줄 CRUD, 1분 주기 체크, 실행 오케스트레이션 |
| `Dochi/Views/Settings/AutomationSettingsView.swift` | 신규 | 설정 UI (메인 + ScheduleEditSheet + ScheduleRowView) |
| `Dochi/Views/Settings/SettingsSidebarView.swift` | 수정 | SettingsSection enum에 `.automation` 추가 |
| `Dochi/Models/AppSettings.swift` | 수정 | `automationEnabled` 추가 |
| `Dochi/ViewModels/DochiViewModel.swift` | 수정 | schedulerService 프로퍼티, 초기화/연결 |
| `Dochi/App/DochiApp.swift` | 수정 | SchedulerService 생성 + ViewModel 연결 |
| `Dochi/App/NotificationManager.swift` | 수정 | `dochi-schedule` 카테고리 추가 |
| `Dochi/Views/CommandPaletteView.swift` | 수정 | 3개 자동화 명령 추가 |
| `Dochi/Views/SystemStatusSheetView.swift` | 수정 | 하트비트 탭에 "활성 자동화: N개" 표시 |
| `DochiTests/SchedulerServiceTests.swift` | 신규 | 크론 파싱, 스케줄 CRUD, 실행 로직 테스트 |
| `DochiTests/ScheduleEntryTests.swift` | 신규 | 모델 Codable roundtrip 테스트 |

---

## 14. 접근성

- 모든 토글, 버튼에 `accessibilityLabel` 부여
- 스케줄 행: VoiceOver에서 "아침 브리핑, 매일 오전 9시, 활성화됨, 다음 실행 내일 오전 9시" 읽기
- 아이콘 선택: 텍스트 대안 제공
- 실행 기록: 성공/실패 상태를 색상뿐 아니라 텍스트로도 표시 (✅/❌)

---

*최종 업데이트: 2026-02-15*
