# SpecKit — Dochi Specs

> ⚠️ **재초점 안내 (2026-05):** Dochi는 자체 두뇌(LLM 루프·도구·칸반·텔레그램·클라우드 동기화)를 들어내고
> **[Hermes Agent](https://github.com/NousResearch/hermes-agent)의 음성·캐릭터 프론트엔드**로 전면 재작성되었습니다.
> 현행 아키텍처/구조는 [`../CLAUDE.md`](../CLAUDE.md)와 [`../HermesBridge/README.md`](../HermesBridge/README.md)가 정본입니다.
> 이 `spec/` 폴더의 `tools.md`, `llm-requirements.md`, `security.md`, `interfaces.md` 등은 구(舊) 자체-에이전트 설계를
> 기술하므로 **역사적 참고용**입니다. 음성/상태 머신 관련 문서(`states.md`)만 부분적으로 유효합니다.

이 `spec/` 폴더는 (구) Dochi 자체-에이전트 재작성의 설계 문서.

---

## 작업 시작 순서 (중요)

1. [execution-context.md](./execution-context.md) — 이슈 실행용 단일 컨텍스트 (가장 먼저 읽기)
2. 해당 기능의 정본 문서 (`flows`, `models`, `interfaces`, `ui-inventory` 등)
3. 필요 시 비전/로드맵 문서 (`../CONCEPT.md`, `../ROADMAP.md`)

---

## 문서 목록

| 문서 | 역할 |
|------|------|
| [execution-context.md](./execution-context.md) | 이슈 드리븐 실행 정본. 구현 완료 축약 + 구현 예정 상세 + UX 일관성 계약 + 이슈 템플릿/백로그 |
| [claude-agent-sdk-rewrite/README.md](./claude-agent-sdk-rewrite/README.md) | 구 Native + MCP 리라이트 프로그램의 역사적 기록 |
| [product-spec.md](./product-spec.md) | 제품 배경, 목표, 요구사항, 성공 지표 |
| [tech-spec.md](./tech-spec.md) | 아키텍처, 컴포넌트, 의존성, 규칙 |
| [states.md](./states.md) | 앱 상태 머신, 전이 규칙, 금지 조합 |
| [flows.md](./flows.md) | 엔드투엔드 플로우 (정상 + 실패/엣지 케이스) |
| [data-overview.md](./data-overview.md) | 엔티티, 관계 |
| [models.md](./models.md) | 데이터 모델 필드, Phase 태그 |
| [interfaces.md](./interfaces.md) | 서비스 인터페이스, Phase 태그 |
| [llm-requirements.md](./llm-requirements.md) | LLM 규칙, 프로바이더 어댑터, 컨텍스트 압축 |
| [voice-and-audio.md](./voice-and-audio.md) | 웨이크워드, STT, TTS, 에이전트 라우팅 |
| [tools.md](./tools.md) | 내장 도구 스키마 (정본) |
| [project-context-proactive-ux.md](./project-context-proactive-ux.md) | 프로젝트 컨텍스트/프로액티브/유휴토큰 UX 명세 (MVP) |
| [always-on-agent-ops-scenarios.md](./always-on-agent-ops-scenarios.md) | 코딩 에이전트 상시 운영 시나리오 정본 (알림 루프/메모리 루프/레포 자율도) |
| [security.md](./security.md) | 보안, 권한 분류, 확인 UX |
| [supabase.md](./supabase.md) | 클라우드 테이블, 동기화 정책, RLS |
| [open-questions.md](./open-questions.md) | 미결 과제 |

---

## 정본 (Source of Truth) 규칙

| 항목 | 정본 위치 |
|------|----------|
| 수치 목표 (레이턴시, 크기, 재시도) | tech-spec.md (Performance) |
| 도구 스키마 | tools.md |
| 컨텍스트 조합 순서 | flows.md §7 |
| 상태 전이 규칙 | states.md |
| 권한 분류 및 에이전트별 선언 | security.md |
| 프로바이더별 어댑터 차이 | llm-requirements.md |
| Supabase 테이블 스키마 | supabase.md |
| Phase별 실행 계획/이슈 우선순위 | execution-context.md |
| 이슈 실행 우선순위/UX 일관성 계약 | execution-context.md |
| 장기 비전 (Phase 3+) | ROADMAP.md |
| 제품 비전/시나리오 | CONCEPT.md |

다른 문서에서 같은 정보를 반복하지 말고 정본을 링크.

---

## 사용법

- 구현 전에 `execution-context.md`를 먼저 확인하고, 해당 플로우 정본의 수용 기준 확인
- PR에 관련 스펙 섹션 링크. "Spec Impact" 섹션 포함
- 스펙 변경 시 정본 문서만 수정. 다른 문서의 링크가 깨지지 않는지 확인
- 실행 관련 신규 문서는 가급적 추가하지 않고 `execution-context.md`에 통합
