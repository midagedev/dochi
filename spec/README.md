# SpecKit — Dochi Specs

이 `spec/` 폴더는 Dochi 재작성의 설계 문서.

---

## 문서 목록

| 문서 | 역할 |
|------|------|
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
| [security.md](./security.md) | 보안, 권한 분류, 확인 UX |
| [supabase.md](./supabase.md) | 클라우드 테이블, 동기화 정책, RLS |
| [rewrite-plan.md](./rewrite-plan.md) | 리라이트 Phase, 마일스톤, 품질 목표 (수치 정본) |
| [open-questions.md](./open-questions.md) | 미결 과제 |

---

## 정본 (Source of Truth) 규칙

| 항목 | 정본 위치 |
|------|----------|
| 수치 목표 (레이턴시, 크기, 재시도) | rewrite-plan.md |
| 도구 스키마 | tools.md |
| 컨텍스트 조합 순서 | flows.md §7 |
| 상태 전이 규칙 | states.md |
| 권한 분류 및 에이전트별 선언 | security.md |
| 프로바이더별 어댑터 차이 | llm-requirements.md |
| Supabase 테이블 스키마 | supabase.md |
| Phase별 계획 | rewrite-plan.md |
| 장기 비전 (Phase 3+) | ROADMAP.md |
| 제품 비전/시나리오 | CONCEPT.md |

다른 문서에서 같은 정보를 반복하지 말고 정본을 링크.

---

## 사용법

- 구현 전에 스펙을 읽고, 해당 플로우의 수용 기준 확인
- PR에 관련 스펙 섹션 링크. "Spec Impact" 섹션 포함
- 스펙 변경 시 정본 문서만 수정. 다른 문서의 링크가 깨지지 않는지 확인
- 대규모 기능은 `spec/` 하위에 별도 문서 추가 후 이 README에 등록
