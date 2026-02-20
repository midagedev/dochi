# Rewrite Delivery Context (Native + MCP)

기준일: 2026-02-20  
상태: Active Program Context (post-#318)

## 1) 목적

이 문서는 Native + MCP 리라이트의 실행 기준을 한 곳에 고정한다.

- 현재 아키텍처 결정
- 활성 이슈 트랙과 우선순위
- 품질 게이트/완료 조건
- legacy 이슈(#281~#293) 이관 상태

## 2) Source of Truth

1. [#318](https://github.com/midagedev/dochi/issues/318)
2. `spec/claude-agent-sdk-rewrite/README.md`
3. `spec/llm-requirements.md`
4. `spec/claude-agent-sdk-rewrite/10-mcp-coding-profiles-guide.md`
5. `spec/claude-agent-sdk-rewrite/11-tool-routing-policy.md`
6. `spec/claude-agent-sdk-rewrite/12-cli-orchestration-contract.md`
7. `spec/tech-spec.md`, `spec/tools.md`, `spec/security.md`

## 3) Active Program Checklist

### Core Native Track

- [x] [#320](https://github.com/midagedev/dochi/issues/320) 멀티 Provider 네이티브 인터페이스 + Anthropic 1차
- [x] [#321](https://github.com/midagedev/dochi/issues/321) NativeAgentLoopService
- [x] [#322](https://github.com/midagedev/dochi/issues/322) DochiViewModel 네이티브 컷오버
- [x] [#323](https://github.com/midagedev/dochi/issues/323) 세션 지속성/재개
- [x] [#324](https://github.com/midagedev/dochi/issues/324) ContextCompactionService
- [x] [#325](https://github.com/midagedev/dochi/issues/325) HookPipeline 네이티브 통합
- [x] [#326](https://github.com/midagedev/dochi/issues/326) MCP 코딩 프로파일/lifecycle
- [x] [#327](https://github.com/midagedev/dochi/issues/327) BuiltIn/MCP 라우팅 정책 일원화
- [x] [#328](https://github.com/midagedev/dochi/issues/328) CLI 오케스트레이션 계약
- [x] [#329](https://github.com/midagedev/dochi/issues/329) SDK sidecar 경로 제거
- [x] [#330](https://github.com/midagedev/dochi/issues/330) 회귀/성능 벤치/SLO 게이트
- [x] [#331](https://github.com/midagedev/dochi/issues/331) 스펙/이슈 트랙 동기화

### Multi-Provider Extension Track

- [ ] [#332](https://github.com/midagedev/dochi/issues/332) OpenAI 어댑터
- [ ] [#333](https://github.com/midagedev/dochi/issues/333) Z.AI 어댑터
- [ ] [#334](https://github.com/midagedev/dochi/issues/334) Ollama/LM Studio 어댑터
- [ ] [#335](https://github.com/midagedev/dochi/issues/335) Provider Capability Matrix
- [ ] [#336](https://github.com/midagedev/dochi/issues/336) ModelRouter v2
- [ ] [#337](https://github.com/midagedev/dochi/issues/337) Contract Test Matrix

### Follow-up / Stabilization Backlog

- [ ] [#339](https://github.com/midagedev/dochi/issues/339) Anthropic SSE incremental parser 적용
- [ ] [#344](https://github.com/midagedev/dochi/issues/344) ContextCompaction tokenizer 정밀도 개선
- [ ] [#347](https://github.com/midagedev/dochi/issues/347) coding-git MCP repo 경로 자동 동기화
- [ ] [#350](https://github.com/midagedev/dochi/issues/350) orchestrator summarize 로직 서비스 분리
- [ ] [#352](https://github.com/midagedev/dochi/issues/352) DochiViewModel SDK dead code 제거
- [ ] [#355](https://github.com/midagedev/dochi/issues/355) RuntimeMetrics 실계측(first partial/tool latency) 연동

## 4) Legacy SDK Program (#281~#293) Status Mapping

| Legacy Issue | 상태 | Native Track 대응 |
|-------------|------|-------------------|
| #281 ~ #289 | historical completed | #320 ~ #325로 대체 완료 |
| #290 ~ #291 | historical scope split | Native session/resume는 #323에서 반영 |
| #292 | partially superseded | 품질 게이트는 #330에서 재정의 |
| #293 | superseded/closed path | sidecar 제거는 #329에서 수행 |

정책:

- #281~#293은 "SDK 전면 채택" 맥락의 이력으로 간주한다.
- 현재 실행 판단은 #318 + #320~#337 기준으로만 한다.

## 5) Quality Gates (현재 기준)

Program 완료 판정은 아래를 모두 만족해야 한다.

1. 네이티브 실행 경로가 기본 경로이며 sidecar runtime run 경로가 0%
2. 회귀 리포트 자동 생성 가능 (#330)
3. first partial p95 / tool latency p95 확인 가능 (#330)
4. Provider contract matrix CI 게이트 통과 (#337)
5. 문서-이슈 매핑이 1:1 유지 (#331)

## 6) PR 운영 규칙

각 PR은 아래를 포함한다.

- `Spec Impact` (변경/무변경 명시)
- 관련 이슈 링크
- 테스트 실행 커맨드 및 결과
- 남은 리스크와 후속 이슈

## 7) Deprecated 안내

아래 문서는 active 설계 문서가 아니다.

- `01` ~ `09` 문서 전체 (SDK 중심 계획)

해당 문서는 history reference로만 사용한다.
