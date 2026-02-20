# Native + MCP Rewrite Program

상태 갱신: 2026-02-20

> 이 디렉토리는 원래 Claude Agent SDK 전면 전환 계획의 정본이었지만,
> 아키텍처 결정 [#318](https://github.com/midagedev/dochi/issues/318) 이후
> **Native + MCP 기준 실행 트랙**으로 재정렬되었다.

## 현재 결정

- 대화/음성 기본 경로: 네이티브 Swift + provider adapter
- 도구 확장: MCP 계층 유지/강화
- 장시간 코딩 작업: Claude Code / Codex CLI 오케스트레이션
- SDK sidecar 전면 의존 계획: deprecated (history only)

## 읽기 순서 (Current SoT)

1. [#318](https://github.com/midagedev/dochi/issues/318) 프로그램 결정/체크리스트
2. `spec/claude-agent-sdk-rewrite/rewrite-delivery-context.md`
3. `spec/claude-agent-sdk-rewrite/10-mcp-coding-profiles-guide.md`
4. `spec/claude-agent-sdk-rewrite/11-tool-routing-policy.md`
5. `spec/claude-agent-sdk-rewrite/12-cli-orchestration-contract.md`
6. `spec/llm-requirements.md`, `spec/tools.md`, `spec/security.md`, `spec/tech-spec.md`

## 이슈 맵 (Native Track)

| Phase | Issue | 상태 | 스펙/코드 기준 |
|------|-------|------|----------------|
| Phase 1 | [#320](https://github.com/midagedev/dochi/issues/320) 멀티 Provider 인터페이스 + Anthropic | CLOSED | `spec/llm-requirements.md` |
| Phase 1 | [#321](https://github.com/midagedev/dochi/issues/321) NativeAgentLoopService | CLOSED | `Dochi/Services/NativeLLM/*` |
| Phase 1 | [#322](https://github.com/midagedev/dochi/issues/322) DochiViewModel 컷오버 | CLOSED | `Dochi/ViewModels/DochiViewModel.swift` |
| Phase 1 | [#323](https://github.com/midagedev/dochi/issues/323) 세션 지속성/재개 | CLOSED | `Dochi/Services/NativeLLM/*` |
| Phase 2 | [#324](https://github.com/midagedev/dochi/issues/324) ContextCompactionService | CLOSED | `Dochi/Services/NativeLLM/ContextCompactionService.swift` |
| Phase 2 | [#325](https://github.com/midagedev/dochi/issues/325) HookPipeline 통합 | CLOSED | `Dochi/Services/Runtime/Hooks/*` |
| Phase 3 | [#326](https://github.com/midagedev/dochi/issues/326) MCP 프로파일/lifecycle | CLOSED | `10-mcp-coding-profiles-guide.md` |
| Phase 3 | [#327](https://github.com/midagedev/dochi/issues/327) BuiltIn/MCP 라우팅 정책 | CLOSED | `11-tool-routing-policy.md` |
| Phase 3 | [#328](https://github.com/midagedev/dochi/issues/328) CLI 오케스트레이션 계약 | CLOSED | `12-cli-orchestration-contract.md` |
| Phase 4 | [#329](https://github.com/midagedev/dochi/issues/329) SDK sidecar 제거 | CLOSED | `Dochi/ViewModels/DochiViewModel.swift` |
| Phase 4 | [#330](https://github.com/midagedev/dochi/issues/330) 회귀/성능/SLO 게이트 | OPEN | `10-testing-observability-operations.md` |
| Phase 4 | [#331](https://github.com/midagedev/dochi/issues/331) 스펙/이슈 동기화 | OPEN | 본 문서 + `rewrite-delivery-context.md` |
| Phase 1 (Provider) | [#332](https://github.com/midagedev/dochi/issues/332) OpenAI 어댑터 | OPEN | `spec/llm-requirements.md` |
| Phase 1 (Provider) | [#333](https://github.com/midagedev/dochi/issues/333) Z.AI 어댑터 | OPEN | `spec/llm-requirements.md` |
| Phase 1 (Provider) | [#334](https://github.com/midagedev/dochi/issues/334) Ollama/LM Studio 어댑터 | OPEN | `spec/llm-requirements.md` |
| Phase 2 (Provider) | [#335](https://github.com/midagedev/dochi/issues/335) Capability Matrix | OPEN | `spec/llm-requirements.md` |
| Phase 2 (Provider) | [#336](https://github.com/midagedev/dochi/issues/336) ModelRouter v2 | OPEN | `spec/tech-spec.md`, `spec/tools.md` |
| Phase 4 (Provider) | [#337](https://github.com/midagedev/dochi/issues/337) Provider Contract Test Matrix | OPEN | `DochiTests/*Provider*` |

## Deprecated/Archive 문서

아래 문서는 **SDK 전면 전환 당시 설계 이력**으로 보관한다.

- `01-claude-agent-sdk-reference.md`
- `02-architecture-principles.md`
- `03-target-system-architecture.md`
- `04-runtime-bridge-design.md`
- `05-context-and-memory-architecture.md`
- `06-agent-definition-and-lifecycle.md`
- `07-tools-permissions-hooks.md`
- `08-multi-device-sync-topology.md`
- `09-implementation-roadmap.md`

사용 규칙:

- 신규 기능 설계의 1차 근거로 사용하지 않는다.
- 필요한 경우 "history reference"로만 인용한다.
- 현재 동작/우선순위 판단은 #318 + 본 문서 기준으로 한다.

## 유지보수 규칙

- 이슈 상태 변경 시 이 문서 표를 함께 갱신한다.
- Program 레벨 결정 변경 시 `rewrite-delivery-context.md`를 먼저 갱신한다.
- obsolete 계획은 문서 내에 deprecated로 명시한다.
