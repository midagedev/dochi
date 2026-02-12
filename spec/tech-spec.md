# Dochi — Technical Spec (SpecKit)

## Meta
- Title: Dochi — Technical Design
- DRI: TBD (e.g., @hckim)
- Reviewers: TBD
- Status: Draft
- Created: 2026-02-12
- Updated: 2026-02-12
- Links: product-spec.md, README.md, CONCEPT.md, ROADMAP.md, docs/built-in-tools.md

## 요약
- macOS 네이티브 SwiftUI 앱으로, 워크스페이스/에이전트/개인 컨텍스트를 조합하여 LLM 대화와 로컬 도구 실행을 제공.
- 피어 모델(디바이스 자율)과 Supabase 동기화 계층을 결합. 도구 실행은 로컬, 클라우드는 동기화 전용.

## 제안 아키텍처 (Proposed Architecture)
- UI: SwiftUI + ViewModel(`DochiViewModel`) 구조.
- 서비스 계층: LLMService, BuiltInToolService, SettingsService, Memory/ContextService, TelegramService, SupabaseSyncService, STT/TTS, WakeWord.
- 통신: LLM SSE 스트리밍, Telegram Bot API, Supabase(REST/RPC/Realtime) 기반 동기화.
- 확장: MCP 서버(외부 도구) 등록/해제 및 호출 프록시.

## 컴포넌트 (Components)
- LLMService: OpenAI/Anthropic/Z.AI 제공자 추상화, 모델 선택/폴백(로드맵), SSE 파싱.
- STT/TTS: Apple STT, Supertonic ONNX TTS(한국어 10종), 속도/보이스/스텝 설정.
- WakeWord: 자모 유사도 매칭 기반 웨이크워드 감지, 연속 대화 토글.
- BuiltInToolService: 설정/에이전트/컨텍스트/프로필/워크스페이스/텔레그램/미리알림/알람/검색/이미지/프린트 도구 제공.
- Memory/Context: 파일 기반 컨텍스트(시스템/WS/에이전트/개인) 구성과 자동 압축.
- TelegramService: DM 수신/스트리밍 응답/도구 진행 스니펫 중계.
- SupabaseSyncService: 인증/WS/대화/컨텍스트/디바이스 동기화(충돌 보수적 처리).

## 데이터 모델 & 파일 구조 (Data Model)
- 기본 경로: `~/Library/Application Support/Dochi/`
- 시스템: `system_prompt.md`
- 프로필: `profiles.json`(이름/별칭/설명/기본 사용자 지정)
- 개인 기억: `memory/{userId}.md`(라인 지향 `- ...`)
- 워크스페이스: `workspaces/{wsId}/config.json|memory.md`
- 에이전트: `workspaces/{wsId}/agents/{name}/persona.md|memory.md|config.json`
- 레거시 호환: `system.md|family.md|memory.md`

## 동기화 모델 (Supabase)
- 범위: 사용자/프로필, 워크스페이스 메타/멤버, 대화 로그, 컨텍스트 스냅샷/패치, 디바이스 메타/상태.
- 정책: 클라우드는 동기화 전용, 실행/도구는 로컬.
- 충돌: 라인 지향 메모리 우선, 대량 변경은 프리뷰/확인 가드레일 도구 제공.

## API/도구 스키마 (APIs)
- MCP 스타일 입력 스키마, 도구 레지스트리로 노출 제어/TTL 지원.
- 카테고리(예): settings, agent, agent_edit, context, profile, profile_admin, workspace, reminders, alarm, web_search, generate_image, print_image, telegram.
- 상세 스키마와 사용 예시는 `docs/built-in-tools.md` 참조.

## 보안/프라이버시 (Security & Privacy)
- 에이전트별 권한 범위(도구/명령) 설정(로드맵 세분화).
- 위험 동작(파일/셸/원격 제어)은 사용자 확인 필수.
- API 키/토큰은 설정 서비스에서 관리(마스킹 출력, 키체인 연동은 추후).

## 실패 모드/복구 (Failure Modes & Recovery)
- LLM 스트림 끊김: 자동 재시도/폴백 모델(Phase 4) 시도.
- 도구 호출 실패: 원인/입력 스니펫을 대화로 반환, 재시도 지침 포함.
- 동기화 충돌: 보수적 머지, 사용자에게 프리뷰 제공(에이전트 에디터 도구).
 - 타임아웃: LLM 요청 첫 바이트 20초, 전체 교환 60초(소프트) 초과 시 고지 후 취소.

## 성능/용량 (Performance & Capacity)
- SSE 스트리밍 파이프라인, 버퍼링/토큰 절약(문맥 압축) 적용.
- TTS 시작 지연 최소화(로컬 엔진, 사전 워밍업 옵션).
- 모델 라우팅/폴백/로컬 LLM 도입으로 비용/지연 최적화(Phase 4).
 - 초기 목표(검토/조정 가능):
   - 텍스트 첫 부분 응답 p50 ≤ 1.0s, p95 ≤ 2.5s
   - 전체 텍스트 응답 p50 ≤ 3.5s, p95 ≤ 7s
   - TTS 최초 오디오 시작 ≤ 800ms(사전 로드 시)
   - 컨텍스트 크기 상한: 80k chars, 최근 대화 30개

## 관측/텔레메트리 (Observability)
- 로컬 진단 로그(사용자 opt‑in), 실패율/지연/웨이크워드 정확도 수집.
- 외부 전송은 비활성 기본, 프라이버시 우선 원칙.
 - 핵심 지표(로컬): 텍스트/음성 레이턴시, 툴 성공률, 재시도율, 웨이크워드 FAR/FRR, 실패 상위 원인.

## 테스트 전략 (Testing)
- 모듈/서비스 단위 테스트(프로토콜 기반 DI로 주입 테스트).
- 통합 시나리오: 웨이크워드→STT→LLM→도구→TTS 체인 검증.
- 회귀 방지: 도구 스키마 스냅샷 테스트, 설정/컨텍스트 마이그레이션 테스트.

## 마이그레이션/호환성 (Migration & Compatibility)
- 레거시 `system.md|family.md|memory.md` → 워크스페이스/개인 구조로 점진 이전.
- 자동 포함(존재 시), 신규 작성은 `system_prompt.md` 및 WS/에이전트 디렉토리 사용 권장.

## 대안/선행사례 (Alternatives & Prior Art)
- Claude Code / OpenClaw에서 로컬 제어 아이디어 차용, macOS 네이티브/워크스페이스 맥락 관리로 차별화.

## 오픈 이슈 (Open Questions)
- 에이전트별 세분 권한 설계(권한 카테고리/프롬프트/UX).
- 로컬 LLM 통합(Ollama/llama.cpp)과 모델 선택 UX.
- 다중 피어 간 작업 라우팅 정책(음성/도구 실행 충돌 회피).

## 부록 (Appendix)
- 도구 목록/스키마: `docs/built-in-tools.md`
- 비전/컨셉: `CONCEPT.md`, 로드맵: `ROADMAP.md`, 시작: `README.md`
