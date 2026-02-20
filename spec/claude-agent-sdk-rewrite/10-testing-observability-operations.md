# 10. Testing, Observability, Operations

## 1) 목표

리라이트 이후에도 "안전하고 재현 가능한 운영"을 유지하기 위한 테스트/관측 기준을 정의한다.

## 2) 테스트 전략

### 단위 테스트

- Snapshot builder
- Permission policy engine
- Tool risk classifier
- Session mapping store
- Hook handlers

### 통합 테스트

- Swift app <-> runtime bridge IPC
- tool dispatch roundtrip
- approval request/resolve 흐름
- session resume

### E2E 테스트

- 음성 입력 -> 툴 실행 -> 응답
- 메신저 입력 -> 원격 디바이스 실행 -> 응답
- cross-device 이어하기

## 3) 회귀 평가셋

컨텍스트 품질 회귀를 감지하기 위해 시나리오 기반 평가셋을 유지한다.

카테고리:

- 가족 도메인 (일정/아이 대화)
- 개발 도메인 (코드 리뷰/세션 재개)
- 개인 컨텍스트 회상

평가 항목:

- 사실 일치율
- 권한 정책 준수율
- 불필요 도구 호출률
- 응답 지연

## 4) 관측 구조

### 로그

모든 이벤트를 구조화 JSON으로 기록:

- session lifecycle
- tool decision
- hook decision
- approval flow
- routing/lease

### 메트릭

필수 메트릭:

- `dochi_runtime_session_active`
- `dochi_runtime_session_latency_ms`
- `dochi_tool_call_total{tool,decision}`
- `dochi_approval_wait_ms`
- `dochi_context_snapshot_tokens`
- `dochi_session_resume_success_rate`

### 트레이싱

각 사용자 요청에 `traceId`를 부여해

- 입력 수신
- 컨텍스트 구성
- 런타임 실행
- 도구 호출
- 최종 응답

을 단일 체인으로 조회할 수 있어야 한다.

## 5) SLO (초안)

- 가용성: 99.5%
- 첫 partial 응답 p95: 2.0초
- 승인 대기 제외 전체 응답 p95: 8.0초
- 세션 resume 성공률: 99%

## 6) 운영 Runbook

### 런타임 무응답

1. health check 실패 감지
2. runtime 재기동
3. 세션 recover 시도
4. recover 실패 세션은 사용자에게 재시작 안내

### 도구 폭주/루프 의심

1. 세션 즉시 interrupt
2. 최근 tool chain 로그 추출
3. 정책 룰셋/프롬프트/훅 판정 비교

### 권한 오판

1. approval 로그 + canUseTool 판정 비교
2. 정책 버전 롤백 가능하도록 유지

## 7) 배포 게이트

아래를 모두 만족해야 rollout:

- 통합/E2E 테스트 통과
- 회귀 평가셋 임계치 통과
- 에러 버짓 기준 충족
- 보안 점검 체크리스트 통과

## 8) 운영 데이터 보존

- 감사 로그: 30일
- 세션 진단 로그: 7일 (로컬)
- 민감 원문: 최소 보존 원칙 적용

