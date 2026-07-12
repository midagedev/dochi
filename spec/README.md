# Dochi specifications

## 현행 정본

Dochi는 AgentRuntimeKit을 앱 안에서 실행하는 Swift 네이티브 에이전트를 기본으로 사용한다. macOS는
Hermes WebSocket bridge를 선택 경로로 유지하고, iOS는 네이티브 경로만 제공한다.

| 문서 | 정본 범위 |
| --- | --- |
| [`native-agent-runtime.md`](./native-agent-runtime.md) | 네이티브 host 경계, provider/credential, 기억, checkpoint/continuation, 도구 승인, iOS 개인정보·음성 |
| [`../README.md`](../README.md) | 제품 개요, 설정, 빌드·실행, 사용자 대상 보안 안내 |
| [`../HermesBridge/README.md`](../HermesBridge/README.md) | macOS 선택형 Hermes bridge 설치, 실행, wire protocol |
| [`states.md`](./states.md) | macOS 음성 상호작용 상태 머신 중 현재 코드와 일치하는 부분 |
| [`../Dochi/Resources/Models/README.md`](../Dochi/Resources/Models/README.md) | 번들 VRM 출처, 라이선스, 검증 hash |

새 네이티브 에이전트 동작이나 보안 경계를 바꾸는 PR은 **Spec Impact**에서
`native-agent-runtime.md`의 영향 범위를 밝히고 필요하면 같은 변경에서 갱신한다. Xcode target과
package 의존성의 실행 정본은 `../project.yml`이다.

## 역사적 문서

2026-05의 Hermes-only 재초점 이전에 작성된 아래 문서들은 과거의 대규모 자체 에이전트, 클라우드
동기화, MCP/도구 카탈로그와 제품 로드맵을 설명한다. 현재 구현의 인터페이스, 보안 정책 또는 수용
기준으로 사용하지 않는다.

- `execution-context.md`
- `product-spec.md`, `tech-spec.md`
- `flows.md`, `models.md`, `interfaces.md`, `data-overview.md`
- `llm-requirements.md`, `tools.md`, `security.md`, `supabase.md`
- `voice-and-audio.md`
- `project-context-proactive-ux.md`, `always-on-agent-ops-scenarios.md`
- `claude-agent-sdk-rewrite/`
- `ux/`와 기타 milestone/roadmap 문서

역사적 문서와 현행 코드가 충돌하면 `native-agent-runtime.md`, `project.yml`, 실제 코드와 테스트 순으로
판단한다. 과거 문서를 현행으로 되살리거나 그 기능이 구현되어 있다고 요약하지 않는다.

## 문서 변경 규칙

- 동작과 인터페이스는 구현 및 테스트와 같은 변경에서 문서화한다.
- 아직 연결하지 않은 AgentRuntimeKit module이나 tool을 Dochi 기능으로 적지 않는다.
- 기억 비활성화, 대화 삭제, checkpoint 삭제와 hard deletion을 서로 같은 의미로 표현하지 않는다.
- provider/model 기본값은 편의 초기값이며 서비스 가용성 보장으로 표현하지 않는다.
- Hermes 문서는 선택형 legacy/remote backend 범위에만 유지한다.
