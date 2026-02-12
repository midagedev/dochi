# Dochi — Product Spec

## Meta
- DRI: @hckim
- 상태: Draft
- 생성: 2026-02-12
- 갱신: 2026-02-12

---

## 요약

Dochi는 집/팀의 맥락을 이해하고 실행하는 macOS 네이티브 AI 에이전트. 워크스페이스 단위로 기억을 관리하고, 에이전트마다 고유한 페르소나와 권한을 가짐. 로컬 우선 실행, 클라우드는 동기화 전용.

비전과 시나리오: [CONCEPT.md](../CONCEPT.md)

---

## 문제 배경

- 기존 비서(Siri 등)는 장기 맥락과 역할별 기억 분리가 부족
- 대화/일정/가정/개발 등 다른 목적을 한 장치에서 자연스럽게 전환하기 어려움
- 프라이버시 관점에서 로컬 실행과 역할별 권한 제어 필요

---

## 목표 (Goals)

- 멀티 워크스페이스: 가족/팀 등 목적별 컨텍스트 분리 및 전환
- 개인 컨텍스트: 사용자 고유 기억의 횡단적 유지 (디바이스/워크스페이스를 가로질러 공유)
- 멀티 에이전트: 에이전트별 페르소나/웨이크워드/권한/기억 분리
- 음성 UX: 웨이크워드 기반 전환, 로컬 TTS, 연속 대화
- 내장 도구: [tools.md](./tools.md) 참조
- 통합: MCP 확장, 텔레그램 DM, Supabase 동기화
- macOS 네이티브: FaceTime, 캘린더, 미리알림, Shortcuts 연동

---

## 비목표 (Non-Goals)

- 클라우드에서 도구 원격 실행 (동기화 전용)
- 범용 홈 허브 (개인/가족/팀 보조에 초점)
- 무제한 자동화/자율행동 (위험 동작은 확인 필요)

---

## 대상 사용자

| 페르소나 | 시나리오 |
|---------|---------|
| 가족 (부모) | 일정, 미리알림, FaceTime, 아이에게 TTS 전달 |
| 가족 (아이) | 대화 친구 (키키), 이야기, 교육, 안전 환경 |
| 개발자/팀 | 코드 리뷰, 작업 이어하기, 빌드 상태 (코디) |
| 개인 | 일정, 지식 조회, 개인 기억 질의 |

---

## 기능 요구사항

- **LLM**: OpenAI/Anthropic/Z.AI SSE 스트리밍, 모델 선택/전환. 상세: [llm-requirements.md](./llm-requirements.md)
- **음성**: Apple STT, Supertonic ONNX TTS, 웨이크워드+연속 대화. 상세: [voice-and-audio.md](./voice-and-audio.md)
- **컨텍스트**: 시스템/워크스페이스/에이전트/개인 계층 조합, 자동 압축. 상세: [flows.md](./flows.md#7-context-composition-flow)
- **도구**: 내장 도구 + MCP 확장. 상세: [tools.md](./tools.md)
- **통합**: 텔레그램 DM, Supabase 동기화. 상세: [supabase.md](./supabase.md)
- **설정**: 다중 API 키, 음성/모델/UX 파라미터. 상세: [models.md](./models.md#settings)
- **상태 관리**: 명시적 상태 머신. 상세: [states.md](./states.md)

---

## 비기능 요구사항

- macOS 14+, Swift 6.0, SwiftUI 네이티브
- 로컬 우선: 도구/음성은 로컬, 최소한의 메타데이터만 동기화
- 안정성: 네트워크 단절 시에도 핵심 기능(대화/로컬 도구) 동작
- 확장성: 도구/에이전트/워크스페이스 추가가 선언적으로 가능

---

## 성공 지표

- 대화 레이턴시 (p50/p95): [rewrite-plan.md](./rewrite-plan.md#quality-targets-정본) 참조
- 웨이크워드 FAR/FRR: [rewrite-plan.md](./rewrite-plan.md#quality-targets-정본) 참조
- 기억 반영 정확도 (사용자 평가)
- 도구 성공/실패율
- 세션 유지/재개 성공률

---

## 리스크

상세: [rewrite-plan.md](./rewrite-plan.md#리스크--대응)

---

## 로드맵

리라이트 Phase: [rewrite-plan.md](./rewrite-plan.md#phases)
장기 비전 (Phase 3+): [ROADMAP.md](../ROADMAP.md)
