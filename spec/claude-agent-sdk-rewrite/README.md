# Claude Agent SDK Rewrite Spec

이 디렉토리는 Dochi를 Claude Agent SDK 중심으로 재구성하기 위한 리라이트 정본 문서 묶음입니다.

기준일: 2026-02-19
상태: Architecture Draft (Rewrite Kickoff)

## 목표

- 기존 커스텀 에이전트 루프를 제거하고 SDK 런타임을 표준 엔진으로 채택한다.
- Dochi 고유 가치(워크스페이스/개인 컨텍스트, 로컬 실행, 에이전트 역할 분리)는 유지하고 강화한다.
- 향후 구현/삭제/마이그레이션 작업의 단일 기준 문서로 사용한다.

## 읽기 순서

1. `rewrite-delivery-context.md`
2. `01-claude-agent-sdk-reference.md`
3. `02-architecture-principles.md`
4. `03-target-system-architecture.md`
5. `04-runtime-bridge-design.md`
6. `05-context-and-memory-architecture.md`
7. `06-agent-definition-and-lifecycle.md`
8. `07-tools-permissions-hooks.md`
9. `08-multi-device-sync-topology.md`
10. `09-implementation-roadmap.md`
11. `10-testing-observability-operations.md`

## 문서 맵

| 문서 | 목적 |
|------|------|
| `rewrite-delivery-context.md` | 참고 문서 + GH 이슈 + 품질 게이트를 한 번에 보는 실행 컨텍스트 |
| `01-claude-agent-sdk-reference.md` | SDK 핵심 개념, 인증/세션/권한/훅/서브에이전트/MCP 요약 |
| `02-architecture-principles.md` | CONCEPT 기반 설계 원칙과 비기능 요구 |
| `03-target-system-architecture.md` | 이상적인 시스템 아키텍처와 책임 분할 |
| `04-runtime-bridge-design.md` | Swift 앱과 Agent Runtime 사이 브리지 프로토콜 |
| `05-context-and-memory-architecture.md` | 4계층 컨텍스트/메모리 저장·주입·압축 전략 |
| `06-agent-definition-and-lifecycle.md` | 선언적 에이전트 모델, 웨이크워드 라우팅, 세션 수명주기 |
| `07-tools-permissions-hooks.md` | 도구 실행·권한·사용자 확인·훅 정책 |
| `08-multi-device-sync-topology.md` | 멀티 디바이스/워크스페이스 동기화·실행 위임 모델 |
| `09-implementation-roadmap.md` | 실제 rewrite 단계별 실행 계획 |
| `10-testing-observability-operations.md` | 테스트, 운영 가시성, SLO, 장애 대응 |

## 적용 범위

- 포함: macOS 앱, CLI/메신저 연동, 컨텍스트/동기화, 에이전트 런타임
- 제외: 단기 UI 픽셀 수정, legacy 엔진 유지보수 확장

## 핵심 결정

- 에이전트 런타임은 Claude Agent SDK를 기준으로 한다.
- 런타임 언어는 TypeScript를 우선 채택한다.
- 앱은 "오케스트레이터 + 도메인 시스템"으로 남고, 에이전트 추론 루프는 런타임에 위임한다.
- Supabase는 동기화/메시지 라우팅 계층으로 제한한다.

## 관련 상위 문서

- `CONCEPT.md`
- `ROADMAP.md`
- `spec/execution-context.md`
