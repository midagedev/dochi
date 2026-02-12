# LLM Requirements (Provider-Agnostic)

프로바이더에 무관한 LLM 사용 규칙과 제약.

---

## Capabilities

- SSE 스트리밍 텍스트 응답. 부분 토큰 수신. 중간 취소 가능
- Function/tool calling: 모델이 도구 이름 + JSON 인자 반환. 복수 순차 호출 지원
- Image input (선택): vision 모델에 이미지 URL 포함 가능

---

## Provider Adapter

프로바이더별 차이를 어댑터 레이어에서 흡수. 공통 인터페이스만 상위에 노출.

| 프로바이더 | 인증 | 특이사항 |
|-----------|------|---------|
| OpenAI | `Bearer` header | 표준 chat completions 포맷 |
| Anthropic | `x-api-key` + `anthropic-version` | `system`은 top-level 필드. messages에 system role 없음 |
| Z.AI | `Bearer` header | OpenAI 호환. `"enable_thinking": false` 추가. 모델: `glm-4.7` |

어댑터가 처리할 것:
- 인증 헤더 구성
- request body 포맷 변환 (system 필드 위치, tool 스키마 형식)
- response 파싱 (SSE 포맷, tool_calls 추출)
- 에러 코드 정규화 (rate limit, auth failure, model not found → 공통 에러 타입)

---

## Context Composition

조합 순서 (정본, [flows.md](./flows.md#7-context-composition-flow) 참조):
1. Base system prompt
2. Agent persona
3. 현재 날짜/시간
4. Workspace memory
5. Agent memory
6. Personal memory
7. 최근 대화 (기본 최근 30개 메시지)

대상 크기 상한: `contextMaxSize` (기본 80k chars).

---

## Context Compression

크기 상한 초과 시 적용하는 압축 전략.

### 단계별 압축 (우선순위 순)

| 단계 | 대상 | 방법 | 보존 |
|------|------|------|------|
| 1 | 최근 대화 | 오래된 메시지부터 제거 | 최소 5개 유지 |
| 2 | Workspace + Agent memory | LLM 요약 호출 | 원본을 `.snapshot` 파일로 보존 |
| 3 | Personal memory | LLM 요약 호출 | 원본을 `.snapshot` 파일로 보존 |
| - | Base prompt, Agent persona | 압축하지 않음 | - |

### 요약 호출 규칙
- 경량 모델 사용 (비용 절감). 앱 기본 모델과 무관하게 고정
- 요약 프롬프트: "다음 메모리를 핵심 사실만 보존하여 50% 이하로 요약하세요. 라인 단위(`- ...`) 형식 유지."
- 요약 결과가 원본보다 길면 원본 유지 (안전장치)

### 대화 메시지 압축
- 단계 1에서 제거된 메시지는 요약문으로 대체: "이전 대화 요약: ..."
- 요약문 생성도 경량 모델 사용

### chars vs tokens
- `contextMaxSize`는 char 기준 (프로바이더 무관 단순 측정)
- 프로바이더별 토큰 한도는 별도 체크: char 상한을 넘지 않아도 토큰 초과 가능 시 단계 1부터 재적용
- 대략적 변환: 한국어 기준 1 char ≈ 0.5~1.5 tokens (프로바이더별 상이)

---

## Prompting & System Behavior

- 기본 언어: 한국어 (사용자 지시로 변경 가능)
- 안전: 고위험 동작은 명시적 확인 없이 실행 금지
- 시간 인지: 컨텍스트에 현재 로컬 시간 포함
- 에이전트 역할: 활성 에이전트의 페르소나/톤/권한 준수

---

## Token & Usage

- 교환별 input/output/total 토큰 추적 (로컬 진단용)
- 모델 라우팅 (Phase 5):
  - 기본 정책: 일반 대화 → 경량 모델, 분석/코딩 → 고급 모델
  - 수동 오버라이드 허용
  - 폴백 체인: 1차 실패 → 대체 모델 자동 전환

---

## Errors & Retries

| 상황 | 정책 |
|------|------|
| 일시적 실패 (5xx, timeout) | 최대 2회 재시도. 250ms / 750ms backoff |
| 인증 실패 (401/403) | 재시도 없음. "API 키를 확인하세요" 안내 |
| Rate limit (429) | Retry-After 헤더 존중. 없으면 5s 대기 후 1회 재시도 |
| 모델 미존재 | 재시도 없음. 모델 전환 안내 |
| 비멱등 도구 실행 결과 | 절대 재시도 금지 |

---

## Cancellation & Timeouts

| 항목 | 값 |
|------|-----|
| 첫 바이트 타임아웃 | 20s |
| 전체 교환 소프트 한도 | 60s |
| 사용자 취소 | 스트리밍 즉시 중단 + 대기 중 도구 취소 (가능한 경우) |

타임아웃 초과 시: 사용자에게 고지 후 요청 취소. 부분 응답은 보존.
