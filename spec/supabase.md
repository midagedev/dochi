# Supabase Integration

클라우드 동기화 계층. 실행은 로컬, 클라우드는 동기화 전용.

---

## Auth & Session

- `AuthState`: signedOut / signingIn / signedIn(userId: UUID, email: String?)
- 인증 방법: Apple Sign-In, Email/Password
- `restoreSession()`: 앱 시작 시 세션 복원 시도
- 미인증 시 클라우드 기능 비활성, 로컬 기능 정상

---

## Tables

### workspaces
| 컬럼 | 타입 | 비고 |
|------|------|------|
| id | uuid PK | |
| name | text NOT NULL | |
| invite_code | text UNIQUE | 6자 영숫자 |
| owner_id | uuid FK → auth.users | |
| created_at | timestamptz | |

### workspace_members
| 컬럼 | 타입 | 비고 |
|------|------|------|
| id | uuid PK | |
| workspace_id | uuid FK → workspaces | |
| user_id | uuid FK → auth.users | |
| role | text | 'owner' \| 'member' |
| joined_at | timestamptz | |

UNIQUE(workspace_id, user_id)

### telegram_accounts
| 컬럼 | 타입 | 비고 |
|------|------|------|
| telegram_user_id | int8 PK | |
| workspace_id | uuid FK → workspaces | |
| user_id | uuid FK → auth.users | |
| username | text? | |
| updated_at | timestamptz | |

- 첫 DM 시 upsert. username 변경 시 갱신
- 워크스페이스 resolve: `updated_at` 최신 행 사용

### leader_locks
| 컬럼 | 타입 | 비고 |
|------|------|------|
| resource | text | 복합 PK |
| workspace_id | uuid | 복합 PK |
| holder_user_id | uuid FK → auth.users | |
| expires_at | timestamptz | |

- Acquire: 없으면 insert, 만료 또는 동일 holder면 update
- Refresh: holder가 `expires_at` 갱신
- Release: holder가 delete
- 기본 TTL: 60s
- Fail-open: lock 실패 시 경고 로깅 후 로컬 계속 실행

### devices (P4)
| 컬럼 | 타입 | 비고 |
|------|------|------|
| id | uuid PK | |
| user_id | uuid FK → auth.users | |
| name | text | 디바이스 표시명 |
| platform | text | 'macos' |
| last_heartbeat | timestamptz | |
| workspace_ids | uuid[] | 참여 워크스페이스 목록 |

- Heartbeat 주기: 30s
- 오프라인 판정: heartbeat 2분 이상 미갱신

---

## 동기화 정책

### 범위
| 대상 | 방향 | 빈도 |
|------|------|------|
| 워크스페이스 메타/멤버 | 양방향 | 변경 시 |
| 컨텍스트 (memory, persona) | 양방향 | 변경 시 push, 앱 시작 시 pull |
| 대화 로그 | 양방향 | 대화 종료 시 push |
| 디바이스 상태 | 단방향 (→ cloud) | heartbeat 주기 |
| 프로필 | 양방향 | 변경 시 |

### 충돌 해결
| 상황 | 전략 |
|------|------|
| 메모리 파일 동시 수정 | 라인 단위 병합 시도. 같은 라인 변경 시 로컬 우선 + 경고 |
| 대화 충돌 | timestamp 기준 최신 우선 |
| 워크스페이스 설정 | last-write-wins |
| 에이전트 설정 | last-write-wins |

### 오프라인 동작
- 클라우드 불가 시 로컬 기능 100% 정상
- 변경사항 로컬 큐에 적재
- 복구 시 큐 순서대로 push. 충돌 발생 시 위 전략 적용

---

## Realtime

현재 scope: REST/RPC 기반. Supabase Realtime은 향후 검토.
- 디바이스 온라인 상태 표시에 활용 가능
- 메시지 라우팅(피어 간)에 활용 가능

---

## RLS (Row Level Security)

- workspaces: 멤버만 읽기. owner만 수정/삭제
- workspace_members: 본인 멤버십 읽기. owner가 멤버 관리
- telegram_accounts: 본인 매핑만 읽기/수정
- leader_locks: 워크스페이스 멤버만 접근
- devices: 본인 디바이스만 읽기/수정
