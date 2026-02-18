# Dochi TODO (Operational)

갱신: 2026-02-18

이 문서는 대시보드용 요약이다.  
실행 상세(이슈 템플릿, 파일 단위 범위, 수용 기준)는 `spec/execution-context.md`를 단일 정본으로 사용한다.

---

## 구현 완료 (축약)

1. 텍스트/음성 대화 기본 루프와 상태 머신
2. 주요 도구 + 권한 확인 플로우
3. 프로액티브 제안/하트비트 기본 구조
4. 설정/사이드바/칸반/터미널/MCP 등 핵심 UI 골격
5. 기본 테스트 스위트 및 빌드 파이프라인

---

## 현재 우선순위 (상세는 execution-context 참조)

## P0
1. 온보딩 운영 프로필(가족형 기본) 도입
2. 프로액티브 일일 캡 실적용
3. 프로액티브 알림 정책 단일화
4. Settings 마스터 토글 disabled UX 결함 수정

## P1
1. Quick Seed 온보딩(리마인더/칸반/자동화)
2. Setup Health Score + 설정 복구 동선
3. Heartbeat -> TaskOpportunity 엔진
4. 동기화/TTS 마무리 착수

---

## 작업 방식

1. GitHub 이슈 생성: `spec/execution-context.md` 템플릿 사용
2. 이슈 단위 구현/테스트/문서 갱신
3. 머지 후 `spec/execution-context.md` 상태 업데이트

