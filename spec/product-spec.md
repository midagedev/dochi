# Dochi — Product Spec (SpecKit)

## Meta
- Title: Dochi — macOS Context‑Aware AI Agent
- DRI: TBD (e.g., @hckim)
- Stakeholders: Family users, Team developers, Ops
- Status: Draft
- Created: 2026-02-12
- Updated: 2026-02-12
- Links: README.md, CONCEPT.md, ROADMAP.md, docs/built-in-tools.md

## 요약
- Dochi는 집/팀의 맥락을 이해하고 실행하는 macOS 네이티브 AI 에이전트입니다.
- 워크스페이스(가족/팀)와 개인 컨텍스트를 분리·조합해 대화와 도구 실행에 반영합니다.
- 로컬 우선 원칙: LLM 호출 이외 도구 실행은 맥(피어)에서 수행, 클라우드는 동기화 전용.

## 문제 배경
- 기존 비서(Siri 등)는 사용자의 장기 맥락과 역할(가족/팀/개인)에 따른 기억 분리가 부족합니다.
- 대화·일정·가정용 알림·개발 업무 등 서로 다른 목적을 한 장치에서 자연스럽게 전환하기 어렵습니다.
- 프라이버시/신뢰 관점에서 로컬 실행과 역할별 권한 제어가 필요합니다.

## 목표(Goals)
- 멀티 워크스페이스: 가족/팀 등 목적별 컨텍스트 분리 및 전환.
- 개인 컨텍스트: 사용자 고유 기억의 횡단적 유지(디바이스/워크스페이스를 가로질러 공유).
- 멀티 에이전트: 에이전트별 페르소나/웨이크워드/권한/기억 분리.
- 음성 UX: 웨이크워드(“도치야”) 기반 전환, 로컬 TTS, 연속 대화.
- 내장 도구: 설정/컨텍스트/프로필/워크스페이스/미리알림/알람/웹검색/이미지 생성.
- 통합: MCP 서버 도구 확장, 텔레그램 DM 연동, Supabase 기반 동기화.
- macOS 네이티브 경험: FaceTime, 캘린더, 미리알림, Shortcuts 연동.

## 비목표(Non‑goals)
- 클라우드에서 도구를 원격 실행하지 않음(클라우드는 동기화 전용).
- 범용 홈 허브(스마트홈 전범위) 지향 아님 — 범위는 개인/가족/팀 보조에 초점.
- 무제한 자동화/자율행동 아님 — 위험 동작은 사용자 확인이 필요.

## 대상 사용자/페르소나 (Audience)
- 가족: 아이 대화 친구(키키), 부모 비서(도치).
- 개발자/팀: 코드 리뷰/작업 이어하기/빌드 상태 질의(코디, Claude Code 연동).
- 개인: 일정·미리알림·지식 조회·개인 기억 질의.

## 핵심 시나리오 (User stories)
- “도치야, 민수 숙제 도와줘” → 가족 워크스페이스의 기억으로 응답/도구 실행.
- “코디야, PR 리뷰해줘” → 팀 워크스페이스, 코딩 에이전트 세션.
- “도치야, 엄마한테 전화해줘” → FaceTime 호출.
- 텔레그램 “밥 먹어!” → 집 Mac TTS 방송.

## 기능 요구사항 (Functional Requirements)
- LLM: OpenAI/Anthropic/Z.AI SSE 스트리밍, 모델 선택 및 전환.
- 음성: Apple STT, Supertonic ONNX TTS(ko 10종), 웨이크워드+연속 대화.
- 컨텍스트: 시스템/워크스페이스/에이전트/개인 기억의 계층적 조합과 자동 압축.
- 도구: 내장 도구 집합 제공 및 MCP 서버 연동으로 확장. (자세한 스키마: `docs/built-in-tools.md`)
- 통합: 텔레그램 DM(스트리밍, 진행 스니펫), Supabase 동기화.
- 설정: 다중 API 키, 음성/모델/UX 파라미터, 활성 에이전트, 사용자 프로필.

## 비기능 요구사항 (Non‑functional Requirements)
- macOS 14+, Xcode 15+ — SwiftUI 네이티브.
- 로컬 우선과 프라이버시: 도구 실행/음성 합성은 로컬에서, 최소한의 메타데이터만 동기화.
- 안정성: 네트워크 단절 시에도 핵심 기능(대화/로컬 도구) 동작.
- 확장성: 도구/에이전트/워크스페이스 추가가 선언적으로 가능.

## 아키텍처 개요 (System Overview)
- 피어 모델: 각 디바이스가 독립 피어. 꺼져도 다른 피어에 영향 없음.
- Supabase: 인증/워크스페이스/컨텍스트/대화/디바이스 동기화(실행은 로컬).
- 로컬 서비스: LLM/도구/음성/웨이크워드/텔레그램 클라이언트.

## 설정 및 컨텍스트 구조 (Configuration & Context)
- 기본 경로: `~/Library/Application Support/Dochi/`
- 주요 파일/디렉터리:
  - `system_prompt.md` — 앱 레벨 규칙
  - `profiles.json` — 사용자 프로필/별칭
  - `memory/{userId}.md` — 개인 기억
  - `workspaces/{wsId}/config.json` — WS 설정
  - `workspaces/{wsId}/memory.md` — WS 기억
  - `workspaces/{wsId}/agents/{name}/persona.md|memory.md|config.json`
- 레거시: `system.md`, `family.md`, `memory.md` 계속 읽기 지원.

## 통합/의존성 (Dependencies & Integrations)
- LLM: OpenAI, Anthropic, Z.AI(API 키 필요)
- 검색/이미지: Tavily, fal.ai(API 키 필요)
- 메시징: Telegram Bot API(토큰)
- 동기화: Supabase
- macOS: FaceTime/캘린더/미리알림/Shortcuts

## 성공 지표 (Success Metrics)
- 대화 레이턴시(p50/p95), TTS 시작까지 시간.
- 기억 반영 정확도(사용자 평가), 자동 압축 후 회상률.
- 도구 성공/실패율, 위험 동작 차단율.
- 세션 유지/재개 성공률(디바이스/텔레그램 간).

## 로드맵 요약 (Milestones)
- 완료: 멀티 LLM, STT/TTS, 웨이크워드, 컨텍스트 관리, 프로필, 내장 도구, MCP, 텔레그램(MVP), Supabase 동기화.
- Phase 3: 멀티 워크스페이스, 에이전트 모델/권한/관리 UI.
- Phase 4: 스마트 모델 라우팅/키 티어/폴백/로컬 LLM.
- Phase 5: 디바이스 제어 도구, 권한 시스템, 코딩 에이전트 연동.
- Phase 6: 멀티 인터페이스(텔레그램/슬랙/CLI), 피어 메시지 라우팅.
- Phase 7–8: 자동화/경험(태스크 큐, 워크플로우, 아바타, iOS 앱).

## 리스크와 대응 (Risks & Mitigations)
- 프라이버시/보안: 로컬 우선, 민감 도구는 사용자 확인, 에이전트별 권한.
- API 한도/비용: 모델 라우팅/폴백, 키 티어, 캐시/요약.
- 동기화 충돌: 라인 지향 메모리, 보수적 자동 병합, 명시적 편집 도구.
- 웨이크워드 오탐/미탐: 자모 유사도 매칭, 사용자 커스터마이즈, 임계값 조정.

## 오픈 이슈 (Open Questions)
- 멀티 디바이스 동시 말풍선/오디오 충돌 처리 정책.
- 로컬 LLM 도입 시 모델 선택/온디맨드 다운로드 UX.
- 위험 도구 실행의 사용자 확인 UX(텔레그램/원격 포함).

Owners & Target Decisions (placeholders)
- Device selection policy for remote tasks — Owner: TBD — Decision: YYYY‑MM‑DD
- Local LLM introduction scope — Owner: TBD — Decision: YYYY‑MM‑DD
- Risky tool confirmation UX — Owner: TBD — Decision: YYYY‑MM‑DD

## 롤아웃 (Rollout Plan)

## 문서화 계획 (Documentation Plan)
- 사용자 안내: README.md, in‑app 설정 설명, 도구 사용 가이드(`docs/built-in-tools.md`).
- 개발자 문서: 본 스펙, 기술 스펙, 컨텍스트 구조 설명.
- 변경 이력: Pull Request 템플릿에 스펙 링크를 포함하고, 마일스톤별 변경 점 기록.

## 대안 고려 (Alternatives Considered)
- Siri/단일 디바이스 비서: 장기 맥락과 역할 기반 분리가 부족.
- 범용 홈허브(예: Home Assistant): 스마트홈에 초점, 개인/팀 컨텍스트 및 에이전트 권한 모델과 거리가 있음.
- 전면 클라우드 실행형: 프라이버시/지연/권한 제어에서 불리, 로컬 우선 원칙 위배.
- 단계적: 내부 도그푸딩 → 소규모 베타(가족/팀) → 공개 릴리스.
- 가드레일: 도구/권한 기본 제한, 원격 인터페이스는 보수적 권한.
## 범위와 우선순위 (Scope & Priorities)
- Must: 텍스트/음성 기본 대화, 핵심 도구(미리알림/알람/검색/이미지), 개인/워크스페이스/에이전트 컨텍스트, 텔레그램 DM, 로컬 우선 실행.
- Should: 멀티 에이전트 관리, 기본 권한/확인 가드레일, 컨텍스트 자동 압축, 간단한 모델 선택 정책.
- Could: 고급 모델 라우팅/폴백, 로컬 LLM, 코딩 에이전트 심화, 다중 메신저.


## 참고/부록
- 기능/도구 스키마: `docs/built-in-tools.md`
- 비전/컨셉: `CONCEPT.md`
- 상세 로드맵: `ROADMAP.md`
