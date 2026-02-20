# 08. Multi-Device Sync Topology

## 1) 목표

"디바이스는 투명하다"를 구현하기 위해, 어느 채널에서 요청하든 동일 컨텍스트와 에이전트 정책으로 실행되게 한다.

## 2) 토폴로지

- 각 디바이스는 독립 실행 피어다.
- Supabase는 상태 동기화/라우팅 버스다.
- 실행 자체는 가능한 한 디바이스 로컬에서 수행한다.

## 3) 핵심 엔티티

- `Workspace`
- `Device`
- `Agent`
- `ExecutionLease`
- `SessionRoutingRecord`

## 4) 실행 할당 모델 (Lease)

### Execution Lease

필드:

- `leaseId`
- `workspaceId`
- `agentId`
- `conversationId`
- `assignedDeviceId`
- `expiresAt`
- `status`

동작:

1. 요청 도착 시 라우터가 최적 디바이스 계산
2. 해당 디바이스에 lease 부여
3. 디바이스가 heartbeat로 lease 유지
4. 실패/만료 시 다른 디바이스로 재할당

## 5) 디바이스 선택 전략

우선순위:

1. required capability 일치 (예: FaceTime 가능한 집 Mac)
2. agent affinity (최근 실행 디바이스)
3. 현재 온라인 상태/부하
4. 사용자 명시 선호 디바이스

## 6) 채널별 흐름

### 음성 (로컬)

- 입력 디바이스가 직접 lease 획득 후 실행

### 메신저 (원격)

- 봇이 메시지 수신
- 라우터가 실행 디바이스를 선택
- 선택 디바이스가 실행 후 결과를 채널로 반환

### 멀티 디바이스 이어하기

- 기존 conversationId로 session resume
- 다른 디바이스가 실행해도 동일 context snapshot 규칙 유지

## 7) 동기화 데이터 경계

Supabase 동기화 대상:

- conversation metadata
- routing records
- memory projection hashes
- device liveness

로컬 전용 데이터:

- raw personal memory
- 비밀값 원문
- 고위험 도구 실행 상세 인자

## 8) 오프라인/분할 상황

- 클라우드 단절 시 로컬 큐에 이벤트 적재
- 복구 후 idempotent replay
- lease 동기화 실패 시 로컬 안전 모드(읽기 중심)로 축소

## 9) 충돌 해결

- 메모리: layer별 병합 규칙 + 충돌 로그
- 세션 라우팅: latest valid lease 우선
- 메시지 순서: channel timestamp + monotonic counter 조합

## 10) 운영 지표

- lease 획득 성공률
- 재할당률
- cross-device resume 성공률
- sync lag p95

