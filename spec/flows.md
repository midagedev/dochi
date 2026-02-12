# Core Flows

엔드투엔드 플로우 정의. 각 플로우에 정상 경로, 수용 기준, 실패/엣지 케이스를 포함.

상태 전이 규칙은 [states.md](./states.md) 참조.

---

## 1. Text Interaction Flow

### 정상 경로
1. 사용자가 텍스트 입력 → interaction: idle → processing
2. 컨텍스트 조합: base rules → agent persona → 현재 시각 → workspace memory → agent memory → personal memory → 최근 대화 요약
3. LLM에 SSE 스트리밍 요청. 부분 응답을 UI에 실시간 렌더링
4. tool call 반환 시 → [Tool Invocation Flow](#4-tool-invocation-flow) 진입
5. 최종 응답 완료 → 대화 저장, 필요 시 메모리 갱신
6. processing → idle (텍스트 모드) 또는 processing → speaking (음성 모드)

### 수용 기준
- Given 유효한 모델/키, When 텍스트 전송, Then 첫 부분 응답이 목표 레이턴시 이내 표시 (목표값: [rewrite-plan.md](./rewrite-plan.md))
- Given tool call 필요, When 도구 허용됨, Then 도구 결과 포함 응답 또는 에러+안내 반환
- Given 사용자 취소, When 스트리밍 중, Then 즉시 중단. 이미 수신된 부분 응답은 대화에 보존

### 실패 & 엣지 케이스
| 상황 | 처리 |
|------|------|
| 네트워크 끊김 (스트리밍 중) | 이미 수신된 부분 응답 보존 + UI에 에러 표시. retry 예산 내 자동 재시도 (최대 2회, 250/750ms backoff). 재시도 실패 시 "네트워크 오류" 안내 |
| LLM 응답 없음 (20s 타임아웃) | 요청 취소 + "응답 시간 초과" 안내. 모델 전환 제안 |
| LLM 응답이 빈 문자열 | "응답을 생성하지 못했습니다" 안내. 재시도 권유 |
| 컨텍스트가 모델 한도 초과 | 압축 전략 적용 후 재시도. 실패 시 오래된 대화부터 제거하고 경고 |
| API 키 미설정/만료 | processing 진입 전 체크. "API 키를 확인하세요" 안내 |

---

## 2. Voice Interaction Flow

### 정상 경로
1. 웨이크워드 감지 또는 UI 토글 → interaction: idle → listening, session: inactive → active
2. STT로 발화 캡처. 침묵 타임아웃(configurable) 시 발화 종료
3. listening → processing. 이후 Text Flow와 동일한 LLM/도구 경로
4. 응답 텍스트를 TTS로 변환. 문장 단위 스트리밍: LLM 스트리밍 중 문장 경계에서 TTS 큐에 적재
5. speaking 완료 → session active이면 → listening (연속 대화)

### 수용 기준
- Given 웨이크워드 활성, When 사용자 발화, Then 감지율이 목표 FRR/FAR 밴드 충족
- Given STT 활성, When 침묵 타임아웃, Then TTS 첫 오디오가 목표 레이턴시 이내 시작
- Given barge-in, When 사용자 발화 감지, Then TTS 즉시 중단 + 새 입력 수락

### 실패 & 엣지 케이스
| 상황 | 처리 |
|------|------|
| 웨이크워드 오탐 (false accept) | 사용자가 아무 말 안 함 → 침묵 타임아웃 → idle 복귀. 불필요한 LLM 호출 없음 |
| STT 인식 실패 (빈 결과) | "잘 못 들었어요, 다시 말해주세요" TTS 재생 → listening 복귀 |
| TTS 엔진 로드 실패 | 텍스트 폴백: 응답을 UI에만 표시. "음성 출력을 사용할 수 없습니다" 안내 |
| TTS 재생 중 barge-in | TTS 큐 전체 비움 + 즉시 중단. 이미 표시된 텍스트는 보존. → listening |
| 연속 대화 침묵 타임아웃 | "대화를 종료할까요?" TTS → session: ending. 10s 추가 대기 |
| ending 상태에서 인식 불가 응답 | 부정으로 간주하지 않음. 추가 침묵 타임아웃 시 session 종료 |
| 마이크 권한 미부여 | listening 진입 전 체크. 권한 요청 다이얼로그 표시 |

---

## 3. Telegram Interaction Flow

### 정상 경로
1. DM 수신 → 워크스페이스/에이전트 resolve (telegram_accounts 매핑)
2. 보수적 권한 적용: Safe 도구만 기본 허용
3. LLM 호출 + 도구 실행. progress snippet을 텔레그램에 스트리밍 (메시지 편집)
4. 최종 응답 전송. 이미지가 있으면 함께 전송

### 수용 기준
- Given 매핑된 워크스페이스, When DM 수신, Then 응답 + progress snippet 스트리밍. Sensitive 도구 미노출
- Given 위험 도구 요청, When 원격 인터페이스, Then 실행 거부 + 사유 안내. 인앱 확인 필요

### 실패 & 엣지 케이스
| 상황 | 처리 |
|------|------|
| 워크스페이스 매핑 없음 | "워크스페이스를 먼저 연결해주세요" 응답. 매핑 방법 안내 |
| 앱 미실행 / 오프라인 | 응답 없음 (텔레그램 서버에 메시지 큐잉). 앱 재시작 시 최근 N개 처리 (또는 TTL 초과 시 무시) |
| LLM 호출 실패 | "처리 중 오류가 발생했습니다" 에러 메시지 전송 |
| 스트리밍 중 앱 종료 | 미완료. 재개 없음. 사용자에게 응답 없이 끊김 (알려진 한계) |
| 빠른 연속 메시지 | 큐 기반 순차 처리. 이전 요청 완료 후 다음 처리 |
| Sensitive 도구 시도 | 거부 + "이 작업은 앱에서 직접 실행해주세요" 안내 |

---

## 4. Tool Invocation Flow

### 정상 경로
1. LLM이 tool_calls 반환 → processing sub-state: streaming → toolCalling
2. 각 tool call에 대해: 가용성 확인 → 권한 확인 → 입력 검증 → 실행
3. 결과 수집 → LLM 재호출 (tool results 포함)
4. LLM이 텍스트 응답 반환할 때까지 반복 (최대 10회)

### 수용 기준
- Given 유효 입력 + 허용 카테고리, When 도구 실행, Then 결과를 사람이 읽을 수 있는 형태로 반환
- Given 무효 입력, When 검증 실패, Then 부작용 없이 에러+안내 반환

### 실패 & 엣지 케이스
| 상황 | 처리 |
|------|------|
| 도구 실행 실패 (API 에러 등) | isError: true로 결과 반환 → LLM이 에러를 사용자에게 설명. 다른 도구는 계속 실행 |
| 도구 타임아웃 (개별 10s) | 타임아웃 에러로 결과 반환 → LLM 재호출 |
| loop 10회 초과 | 강제 종료. "도구 호출이 너무 많습니다" 에러 포함하여 LLM 최종 호출 |
| 권한 부족 (Sensitive/Restricted) | 실행 거부. "이 작업은 확인이 필요합니다" 메시지 포함하여 LLM 재호출 |
| 확인 필요 도구 (Sensitive, 로컬) | 사용자 확인 UI 표시 → 승인 시 실행, 거부 시 거부 결과로 LLM 재호출 |
| 복수 tool call 중 일부 실패 | 성공한 것은 결과 반환, 실패한 것은 에러 반환. 전체 롤백 없음 |
| MCP 서버 연결 끊김 | 해당 도구 에러 반환. 내장 도구는 정상 실행 |

---

## 5. Memory Update Flow

### 정상 경로
1. 대화에서 중요 사실 감지 (자동) 또는 사용자 명시 요청
2. 적절한 scope 결정: workspace / personal / agent
3. 라인 단위(`- ...`) 추가. 크기 한도 내 유지

### 수용 기준
- Given 중요 사실, When 저장 허용, Then 올바른 scope에 크기 한도 내 추가
- Given 메모리 한도 초과, When 압축 실행, Then 의미 보존 + 이전 항목 검사 가능

### 실패 & 엣지 케이스
| 상황 | 처리 |
|------|------|
| 파일 쓰기 실패 | 에러 로깅. 사용자에게 "기억 저장에 실패했습니다" 안내. 대화는 계속 |
| 중복 사실 | 기존 항목과 유사도 체크 (간단한 문자열 매칭). 중복 시 스킵 또는 병합 |
| 한도 초과 | 압축 전략 적용 → [llm-requirements.md](./llm-requirements.md) 참조 |

---

## 6. Sync & Device Selection Flow

### 정상 경로
1. 앱 시작 시 세션 복원 → 클라우드와 컨텍스트/대화 동기화
2. 원격 요청(텔레그램) 수신 시 leader lock 획득 → 단일 디바이스에서 실행
3. 변경사항 발생 시 클라우드에 push → 다른 디바이스에 전파

### 수용 기준
- Given 다수 디바이스 온라인, When 원격 태스크, Then leader lock으로 단일 디바이스 실행
- Given 클라우드 불가, When 요청 발생, Then 로컬 동작 계속. 복구 시 동기화 재개

### 실패 & 엣지 케이스
| 상황 | 처리 |
|------|------|
| 클라우드 불가 | fail-open: 로컬 기능 정상. 동기화는 복구 시 재개 |
| leader lock 충돌 | expire 된 lock은 탈취. 동시 실행 방지는 best-effort |
| 동기화 충돌 (메모리 파일) | 라인 단위 병합 시도. 실패 시 양쪽 보존 + 사용자에게 수동 해결 요청 |
| 오프라인 기간 변경 누적 | 재연결 시 timestamp 기반 최신 우선. 충돌 시 로컬 우선 + 경고 |

---

## 7. Context Composition Flow

LLM 호출 전 컨텍스트를 조합하는 내부 플로우.

### 조합 순서 (정본)
1. Base system prompt (`system_prompt.md`)
2. Agent persona (`agents/{name}/persona.md`)
3. 현재 날짜/시간
4. Workspace memory (`workspaces/{wsId}/memory.md`)
5. Agent memory (`workspaces/{wsId}/agents/{name}/memory.md`)
6. Personal memory (`memory/{userId}.md`)
7. 최근 대화 요약 (configurable, 기본 최근 30개 메시지)

### 크기 초과 시 압축 순서
총 크기가 `contextMaxSize` (기본 80k chars) 초과 시:
1. 최근 대화에서 오래된 메시지부터 제거 (최소 5개 유지)
2. 여전히 초과 시 workspace memory + agent memory를 LLM 요약 호출로 압축
3. 여전히 초과 시 personal memory를 LLM 요약 호출로 압축
4. base prompt와 agent persona는 압축하지 않음

상세 압축 전략은 [llm-requirements.md](./llm-requirements.md#context-compression) 참조.
