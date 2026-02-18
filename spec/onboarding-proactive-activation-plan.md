# 온보딩 · 프로액티브 활성화 전략 (v1)

> 참고: 실행 우선순위와 이슈 단위 작업 관리의 정본은 `spec/execution-context.md`입니다.  
> 본 문서는 온보딩/프로액티브 전략 배경과 설계 상세를 설명하는 참고 문서입니다.

## Meta
- DRI: @hckim
- 상태: Draft
- 생성: 2026-02-18
- 갱신: 2026-02-18
- 범위: macOS Dochi (온보딩, 프로액티브 제안, 하트비트, 자동화)

---

## 1) 한 줄 목표

설치만으로도 Dochi가 사용자의 의도를 빠르게 파악하고, **지시 대기형**이 아니라 **허락 기반 제안형**으로 지속적으로 가치를 만들게 한다. 동시에 토큰/리소스 낭비를 구조적으로 제한한다.

---

## 2) 현재 상태 진단 (코드 근거)

| 관찰 | 근거 | 사용자 체감 |
|------|------|------------|
| 온보딩이 설정 입력 중심이고 행동 계약(프로액티브/자동화/권한)이 없음 | `Dochi/Views/OnboardingView.swift:21`, `Dochi/Views/OnboardingView.swift:329` | 완료 후 “그래서 지금 뭐 하지?” 상태 |
| 온보딩 완료 조건이 단일 bool이라 재활성화 설계가 약함 | `Dochi/Views/OnboardingView.swift:345`, `Dochi/App/DochiApp.swift:281` | 초기 온보딩 품질이 낮으면 장기적으로 회복 어려움 |
| 프로액티브/하트비트/자동화 핵심 기능이 기본 OFF | `Dochi/Models/AppSettings.swift:224`, `Dochi/Models/AppSettings.swift:254`, `Dochi/Models/AppSettings.swift:554` | 앱이 스스로 시작할 동력이 없음 |
| 프로액티브 제안의 콜드스타트 소스가 약함(최근 대화 title 의존) | `Dochi/Services/ProactiveSuggestionService.swift:292`, `Dochi/Services/ProactiveSuggestionService.swift:313`, `Dochi/Services/ProactiveSuggestionService.swift:329` | 신규 유저는 제안 품질이 낮거나 제안이 잘 안 뜸 |
| 일일 제안 카운트 변수는 있으나 캡 정책이 없음 | `Dochi/Services/ProactiveSuggestionService.swift:38`, `Dochi/Services/ProactiveSuggestionService.swift:208` | 과다 제안/피로도 리스크 |
| 사용자 활동 기록이 사실상 `sendMessage`에만 연결 | `Dochi/ViewModels/DochiViewModel.swift:423`, `Dochi/ViewModels/DochiViewModel.swift:755` | 실제 사용 패턴 대비 유휴 판정이 부정확 |
| 프로액티브 알림은 추가 토글 + 앱 비활성 조건까지 걸려 노출이 제한적 | `Dochi/Models/AppSettings.swift:594`, `Dochi/App/DochiApp.swift:575` | 사용자가 “기능 존재” 자체를 잘 인지 못함 |
| 빈 화면 제안은 정적 프롬프트 중심 | `Dochi/Views/ContentView.swift:1700`, `Dochi/Models/FeatureSuggestion.swift:104` | ‘맞춤 제안’보다 ‘샘플 문구’ 느낌 |
| 설정 UX에 정책/상태 불일치가 일부 존재 | `Dochi/Views/SettingsView.swift:735`, `Dochi/Views/SettingsView.swift:778`, `Dochi/Views/Settings/ProactiveSuggestionSettingsView.swift:14` | 사용자 입장에서는 “왜 여기서 안 켜지지?” 혼란 |

---

## 3) 제품 원칙 (성공한 서비스 관점)

1. **Activation First**: 첫 10분 안에 “실제 가치 1회”를 반드시 만든다.
2. **Permission-First Proactivity**: 실행보다 제안을 먼저, 제안보다 허락을 먼저.
3. **Progressive Trust**: 한번에 많은 권한을 받지 않고, 성공 경험마다 권한 레벨을 확장.
4. **No Silent Burn**: 사용자가 모르는 토큰/리소스 소모를 만들지 않는다.
5. **Continuous Onboarding**: 첫 온보딩이 실패해도 앱이 스스로 재온보딩 루프를 건다.

---

## 4) 타겟 경험 (North Star Journey)

### 설치 후 3분
1. 사용자가 역할(예: 개발/운영/개인)과 우선 목표를 고른다.
2. 앱이 “오늘 바로 쓸 수 있는 3개 자동 제안”을 미리 보여준다.
3. 첫 제안은 반드시 `허락 요청 카드`로 들어오고, 1클릭으로 실행된다.

### 첫 24시간
1. 하루 1~3회, 맥락 있는 제안을 보낸다(과도하지 않게).
2. 제안은 항상 “왜 지금 이걸 제안하는지” 근거를 보여준다.
3. 수락/연기/유형 끄기 학습으로 제안 품질이 눈에 띄게 올라간다.

### 첫 7일
1. 사용자 맥락(관심사, 일정, 칸반, 메모리) 기반으로 제안 정확도가 개선된다.
2. 자동화 1개 이상 활성화되어 앱이 스스로 리듬을 만든다.
3. “지시를 기다리는 앱”에서 “허락을 구하고 일하는 앱”으로 인식 전환.

---

## 5) 전략 설계

### 5.1 온보딩 v2: Setup Wizard → Activation Contract

기존 6단계 온보딩 뒤에 아래 4단계를 추가한다.

1. **프로액티브 운영 프로필 선택**
   - `조용한 동행형`: 요청 중심 + 낮은 빈도의 리마인드만
   - `가족 홈 어시스턴트형(권장)`: 생활 루틴 제안 + 등록 전 허락
   - `개인 생산성형`: 업무/학습 중심 적극 제안
   - `자동형-안전범위`: safe 읽기/요약 자동 실행 + 나머지 허락
2. **리소스 가드레일 설정**
   - 월 예산(기본값 제안)
   - 프로액티브 일일 횟수(기본 3)
   - 프로액티브 토큰 예산(월 예산의 10~20%)
3. **스타터 자동화 선택**
   - 아침 브리핑, 주간 리포트, 메모리 정리 템플릿 중 체크
   - 저장 즉시 `disabled`가 아니라 `허락 완료된 활성` 상태로 시작
4. **첫 성공 시뮬레이션**
   - 실제 제안 카드 1개를 즉시 띄워 수락/연기/거절을 경험시킴

### 5.2 연속 온보딩: Activation Orchestrator

새 서비스(`ActivationOrchestratorService`)를 두고 앱 시작/매일 첫 포그라운드에서 체크리스트를 점검한다.

- 체크리스트 예시
  - 첫 제안 수락 완료
  - 알림 권한 설정 완료
  - 자동화 1개 활성화
  - 관심사/메모리 시드 확보
- 미완료 항목이 있으면 단 한 개의 “다음 행동 카드”만 제시한다.
- 카드 UX: “지금 하기”, “나중에”, “다시 묻지 않기(기간 제한)”

### 5.3 프로액티브 엔진 재설계: Suggestion → Permission → Execute

제안과 실행을 분리해 신뢰를 확보한다.

1. **Candidate 생성(저비용, 로컬 우선)**
   - 일정/칸반/메모리/최근 대화/시간대 기반 룰
2. **스코어링**
   - `impact`(가치), `confidence`(정확도), `intrusiveness`(방해도), `costRisk`(비용)
3. **정책 게이팅**
   - 모드/시간대/쿨다운/일일캡/예산 상태
4. **노출**
   - 카드 + 근거 + 예상 비용(있으면)
5. **허락 시 실행**
   - 실행 전 확인이 필요한 액션은 기존 tool confirmation 체계 재사용

점수 예시:

```text
score = 0.40*impact + 0.30*confidence + 0.20*freshness - 0.10*costRisk
```

최저 점수 미만은 제안하지 않는다.

### 5.4 콜드스타트 개선 (데이터 없는 유저)

초기엔 대화 이력이 부족하므로 다음 소스를 우선 사용한다.

1. 시간대 기반 미션(아침/오후/저녁)
2. 기본 캘린더/리마인더 점검
3. 온보딩에서 선택한 역할 기반 템플릿 제안
4. 스타터 자동화 결과를 재료로 한 후속 질문

### 5.5 생활 리소스 시딩 온보딩 (Reminders/Kanban 중심)

온보딩에서 “앱이 당장 움직일 재료”를 직접 심는다.

1. **Quick Seed 단계 추가**
   - `리마인더 1개 만들기` (예: 오늘 마감 1건)
   - `칸반 카드 1개 만들기` (예: 이번 주 핵심 작업)
   - `자동화 1개 시작` (아침 브리핑 기본)
2. **UI 원칙**
   - 기본은 체크 ON, 사용자가 해제 가능
   - 생성 전 미리보기와 수정 가능(제목/시간/보드)
3. **실행 방식**
   - 온보딩 완료 직전 일괄 적용
   - 실패해도 온보딩은 완료하고, 실패 항목만 재시도 카드로 남김
4. **수용 기준**
   - 신규 사용자 70% 이상이 온보딩 종료 시 최소 1개 리소스(리마인더/칸반/스케줄)를 보유

### 5.6 Heartbeat를 “할거리 생성 엔진”으로 전환

현재 Heartbeat는 알림 중심이다. 이를 “제안 가능한 할거리 생성”까지 확장한다.

1. **기존 점검 결과를 TaskOpportunity로 표준화**
   - 입력: 일정/칸반/리마인더/메모리/관심사
   - 출력: `{title, reason, source, suggestedAction, costRisk, expiresAt}`
2. **행동 싱크(Sink)**
   - 채팅 제안 카드
   - 리마인더 등록 제안
   - 칸반 카드 등록 제안
3. **허락 기반 처리**
   - “지금 등록”, “오늘은 스킵”, “유형 끄기”
4. **중복/피로 제어**
   - 동일 source hash 24h 중복 금지
   - 하루 최대 등록 제안 N회

### 5.7 관심 주제 가져오기 (Interest Intake Pipeline)

관심 주제는 내부 맥락 + 외부 신호를 함께 사용한다.

1. **내부 신호**
   - `InterestDiscoveryService` 결과
   - 최근 수락/연기 제안 유형
   - 최근 대화 주제
2. **외부 신호**
   - 가능하면 저비용 트렌드 소스(뉴스 요약/키워드 feed)에서 상위 주제만 수집
   - 외부 소스 실패 시 내부 신호만으로 fallback
3. **노출 규칙**
   - “왜 이 주제를 추천하는지”를 한 줄 근거로 표시
   - 바로 실행보다 “관심 저장/나중에 보기/무시”를 먼저 제공

### 5.8 설정 완성도 프레임워크 (Setup Health Score)

설정 부족을 사용자 책임으로 두지 않고 앱이 찾아서 채우게 만든다.

1. **설정 상태 모델**
   - `required`: 핵심 기능에 필수
   - `recommended`: 품질 개선
   - `optional`: 고급
2. **Setup Health Score (0~100)**
   - 예: API 키, 알림 권한, 프로액티브 모드, 자동화 1개, 사용자 프로필 등
3. **복구 UX**
   - 상단 배너: “설정 2개만 완료하면 자동 제안이 안정화됩니다”
   - 원클릭 이동: 해당 설정 섹션으로 딥링크
4. **운영 원칙**
   - 기능이 비활성인 이유를 항상 설명
   - “자동으로 고칠 수 있는 것”은 버튼 한 번으로 해결

### 5.9 기존 구현 미흡 마무리 (Closure Sprint)

코드 기준으로 우선 마무리할 항목:

1. **프로액티브 일일 캡 미적용**
   - `todaySuggestionCount`가 증가만 하고 상한 정책 부재
   - 근거: `Dochi/Services/ProactiveSuggestionService.swift:38`, `Dochi/Services/ProactiveSuggestionService.swift:208`
2. **활동 기록 신호 부족**
   - activity 리셋이 사실상 메시지 전송 중심
   - 근거: `Dochi/ViewModels/DochiViewModel.swift:423`, `Dochi/ViewModels/DochiViewModel.swift:755`
3. **설정 정책 이중화**
   - `suggestionNotificationChannel`과 `notificationProactiveSuggestionEnabled` 동시 존재로 정책 해석 혼선
   - 근거: `Dochi/Models/AppSettings.swift:659`, `Dochi/App/NotificationManager.swift:186`, `Dochi/Services/Telegram/TelegramProactiveRelay.swift:93`
4. **Heartbeat 설정 내 프로액티브 토글 UX 결함**
   - 마스터 토글이 포함된 섹션 자체가 off 상태에서 disabled
   - 근거: `Dochi/Views/SettingsView.swift:735`, `Dochi/Views/SettingsView.swift:778`
5. **설정 진입점 중복**
   - 일반 설정과 전용 프로액티브 설정이 중복되며 책임 경계 불명확
   - 근거: `Dochi/Views/SettingsView.swift:735`, `Dochi/Views/Settings/ProactiveSuggestionSettingsView.swift:14`

### 5.10 가족 홈 어시스턴트 운영 모델 (극단 회피)

양극단(완전 수동 vs 과도 자동화) 대신, 가족 시나리오용 중간 운영층을 기본으로 둔다.

1. **루틴 중심**
   - 아침: 일정/등교/출근 준비 체크
   - 저녁: 남은 할 일/가족 공용 미리알림 정리
2. **행동 단위**
   - “바로 실행”보다 “등록 제안”이 기본
   - 리마인더/칸반 등록 시 항상 누가 위한 항목인지 명시
3. **가족 안전 정책**
   - 민감 작업은 보호자 확인 필수
   - 아동 프로필에는 제안 빈도와 범위를 더 보수적으로 적용
4. **소음 제어**
   - 동일 주제 반복 제안 억제
   - 야간 시간대는 요약형 알림만 허용
5. **수용 기준**
   - 가족형 프로필에서 “불필요 알림” 피드백 비율 감소
   - “등록 제안 수락률”이 단순 대화 제안보다 높아야 함

---

## 6) 낭비 없는 동작 정책 (Token/Resource Efficiency)

### 6.1 3단계 비용 방화벽

1. **Stage A: 0-token 룰 평가**
   - 로컬 데이터/설정만으로 후보 선별
2. **Stage B: 저비용 문구 생성**
   - 템플릿 중심, 필요시 경량 모델
3. **Stage C: 고비용 실행**
   - 반드시 사용자 허락 후

### 6.2 하드 가드레일

- `proactiveDailyCap` 기본 3회
- `proactiveCooldownMinutes` 동적 조정(수락률 낮으면 자동 증가)
- 월 예산 80% 이상 시 프로액티브를 “요약형/저비용 모드”로 강등
- 월 예산 100% + 차단 설정 시 실행형 제안 중단

### 6.3 품질 가드레일

- 7일 이동 수락률 < 15%면 빈도 50% 감축
- 같은 소스 컨텍스트 중복 제안 24h 금지
- 조용한 시간 + 집중 상태(처리 중)에는 제안 표시 금지

---

## 7) 구현 청사진 (현재 구조 기준)

| 영역 | 변경 제안 | 대상 파일 |
|------|----------|----------|
| 온보딩 확장 | 프로액티브 모드/가드레일/스타터 자동화/첫 성공 단계 추가 | `Dochi/Views/OnboardingView.swift` |
| 설정 모델 | 모드/일일캡/예산비율/연속온보딩 상태 키 추가 | `Dochi/Models/AppSettings.swift` |
| 연속 온보딩 | 체크리스트 오케스트레이터 신설, 시작 시 트리거 | `Dochi/App/DochiApp.swift`, `Dochi/Services/ActivationOrchestratorService.swift`(신규) |
| 제안 정책 | 일일캡 적용, 점수 기반 랭킹, 콜드스타트 후보 강화 | `Dochi/Services/ProactiveSuggestionService.swift`, `Dochi/Models/ProactiveSuggestionModels.swift` |
| 사용자 활동 신호 | 메시지 전송 외 주요 상호작용도 activity로 기록 | `Dochi/ViewModels/DochiViewModel.swift`, `Dochi/Views/ContentView.swift` |
| 허락 UX | 제안 카드에 근거/비용/허락 액션 명시, 알림 액션 확장 | `Dochi/Views/SuggestionBubbleView.swift`, `Dochi/App/NotificationManager.swift` |
| 빈 상태 개선 | 정적 프롬프트 + 개인화 미션 카드 병행 | `Dochi/Views/ContentView.swift`, `Dochi/Models/FeatureSuggestion.swift` |
| 스타터 자동화 | 온보딩에서 템플릿 선택 즉시 스케줄 시드 | `Dochi/Services/SchedulerService.swift`, `Dochi/Models/ScheduleModels.swift` |
| 가족 홈 프로필 | 가족형 운영 프로필/루틴 템플릿/보호자 정책 | `Dochi/Views/OnboardingView.swift`, `Dochi/Views/Settings/FamilySettingsView.swift`, `Dochi/Models/AppSettings.swift` |
| 측정 | activation/proactive 관련 이벤트와 KPI 계측 | `Dochi/Services/MetricsCollector.swift`, `Dochi/Models/UsageModels.swift` |

---

## 8) 릴리즈 로드맵

### Phase A (1주): 측정과 안전장치
- activation 이벤트 정의/수집
- 프로액티브 일일캡 + 예산 연동 최소 구현
- 콜드스타트 fallback 후보 추가
- 미흡 구현 closure 1차(토글 UX/정책 이중화 정리)

### Phase B (1~2주): 온보딩 v2
- 온보딩 계약 단계 추가
- 생활 리소스 시딩(Reminders/Kanban/자동화)
- 가족 홈 어시스턴트 프로필 + 루틴 템플릿
- 스타터 자동화 시드
- 첫 성공 시뮬레이션

### Phase C (1주): 연속 온보딩
- ActivationOrchestrator 도입
- 빈 상태 개인화 미션 카드
- Setup Health Score + 설정 복구 동선

### Phase D (지속): 최적화
- 제안 점수 튜닝
- 수락률 기반 빈도 자동 조정
- A/B 실험

---

## 9) KPI 설계

### 핵심 KPI
- `Install → First Value(첫 제안 수락)` 전환율
- `Time to First Value` (목표: 5분 이내)
- `D1/D7 리텐션`
- `Proactive Acceptance Rate` (목표: 30%+)
- `Proactive Token Spend Ratio` (목표: 총 사용량 대비 15% 이하)

### 운영 KPI
- 제안 빈도/사용자/일
- 제안 유형별 수락/연기/끄기율
- 예산 임계(50/80/100%) 구간별 행동 변화
- 허락 요청 대비 실제 실행 비율
- 가족형 프로필에서 사용자별(보호자/아동) 수락률 편차와 피로도

---

## 10) 실험 계획

1. **온보딩 모드 실험**
   - A: 기존
   - B: 가족 홈 어시스턴트형 기본 선택
   - 지표: 첫 24h 수락률, D7 리텐션
2. **첫 성공 시뮬레이션 유무**
   - 지표: 첫 제안 수락까지 소요시간
3. **일일캡 2 vs 3**
   - 지표: 피로도(끄기율), 수락률, 토큰비율

---

## 11) 리스크와 대응

| 리스크 | 설명 | 대응 |
|------|------|------|
| 과도한 적극성으로 인한 피로 | 초반 경험 악화 가능 | 기본은 가족 홈 어시스턴트형(중간 프로필), 일일캡/쿨다운, 수락률 기반 감쇠 |
| 제안 품질 부족 | 초기 컨텍스트 빈약 | 콜드스타트 템플릿 + 역할 기반 시딩 |
| 비용 증가 | 프로액티브 호출 누적 | 3단계 비용 방화벽 + 예산 연동 강제 |
| 권한 불신 | 자동 실행에 대한 거부감 | 실행 전 이유/범위/취소 가능성 명시 |

---

## 12) 스프린트 1 실행 백로그 (권장)

1. `proactiveDailyCap` 설정 키 추가 + 실제 게이트 적용
2. Proactive candidate에 콜드스타트 소스(역할/시간대/스타터자동화) 추가
3. Heartbeat 설정 내 프로액티브 마스터 토글 disabled 버그 수정
4. `suggestionNotificationChannel` vs `notificationProactiveSuggestionEnabled` 정책 통합
5. 온보딩에 “운영 프로필 선택(가족형 포함) + Quick Seed(리마인더/칸반)” 1단계 추가
6. 첫 실행 후 빈 상태에 “다음 한 단계 카드” 노출
7. KPI 이벤트 5종 계측 시작

---

## 13) Spec Impact

- [product-spec.md](./product-spec.md): 활성화/프로액티브 목표를 성공지표에 명시 필요
- [flows.md](./flows.md): 온보딩 v2, 허락형 프로액티브 플로우 추가 필요
- [models.md](./models.md): 신규 AppSettings 키/상태 모델 추가 필요
- [ui-inventory.md](./ui-inventory.md): 온보딩 단계/연속 온보딩 카드/허락 카드 UI 추가 필요
- [security.md](./security.md): 프로액티브 실행 허락 정책을 권한 UX에 통합 필요
- [open-questions.md](./open-questions.md): 외부 트렌드 소스 선택/비용 상한 정책을 신규 결정 항목으로 추가 필요
