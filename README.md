# Dochi (도치)

집 Mac에 상주하며 가족과 팀의 맥락을 이해하는 macOS 네이티브 AI 에이전트.

워크스페이스 단위로 기억을 관리하고, 에이전트마다 고유한 페르소나와 권한을 갖습니다. SwiftUI 네이티브 앱으로 FaceTime, 캘린더, 미리알림, Apple Shortcuts와 깊이 통합됩니다.

> 비전: [CONCEPT.md](./CONCEPT.md) · 스펙: [spec/](./spec/README.md) · 개발 계획: [spec/rewrite-plan.md](./spec/rewrite-plan.md) · 장기 로드맵: [ROADMAP.md](./ROADMAP.md)

## 핵심 기능

- **멀티 LLM** — OpenAI, Anthropic, Z.AI SSE 스트리밍
- **텍스트 + 음성** — 텍스트 입력 기본, 웨이크워드("도치야")로 음성 전환
- **로컬 TTS** — Supertonic ONNX 엔진, 10종 한국어 음성
- **장기 기억** — 워크스페이스/에이전트/개인 컨텍스트 계층, 자동 압축
- **내장 도구** — 설정/에이전트/프로필/워크스페이스/미리알림/알람/웹검색/이미지 생성 ([도구 스키마](spec/tools.md))
- **MCP 연동** — Model Context Protocol 서버로 도구 확장
- **클라우드 동기화** — Supabase 기반 컨텍스트·대화 동기화
- **텔레그램 연동** — 앱 실행 중 DM 수신, 스트리밍 응답

```
"도치야, 민수 숙제 도와줘"      → 가족 워크스페이스 · 가족 기억으로 대화
"코디야, PR 리뷰해줘"           → 팀 워크스페이스 · Claude Code 세션
"도치야, 엄마한테 전화해줘"      → FaceTime 통화 시작
"도치야, 내 알러지 뭐였지?"      → 개인 컨텍스트 · 어디서든 동일
```

## 빠른 시작

```bash
brew install xcodegen       # 요구사항: macOS 14+, Xcode 15+
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme Dochi build
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

1. 설정에서 API 키 입력 (OpenAI / Anthropic / Z.AI 중 하나 이상)
2. 텍스트로 바로 대화 시작
3. 음성: 웨이크워드 활성화 → "도치야" → 연속 대화

## 컨텍스트 구조

```
~/Library/Application Support/Dochi/
├── system_prompt.md             # 앱 레벨 기본 규칙 (선택)
├── profiles.json                # 사용자 프로필
├── memory/{userId}.md           # 개인 기억
└── workspaces/{workspaceId}/
    ├── config.json
    ├── memory.md                # 워크스페이스 공유 기억
    └── agents/{name}/
        ├── persona.md           # 에이전트 페르소나
        ├── memory.md            # 에이전트 기억
        └── config.json          # 에이전트 설정
```

## 문서

| 문서 | 내용 |
|------|------|
| [CONCEPT.md](./CONCEPT.md) | 제품 비전, 시나리오, 설계 원칙 |
| [spec/](./spec/README.md) | 설계 스펙 전체 (모델, 플로우, 상태, 권한 등) |
| [spec/rewrite-plan.md](./spec/rewrite-plan.md) | 리라이트 Phase, 마일스톤, 품질 목표 |
| [ROADMAP.md](./ROADMAP.md) | 장기 비전 (Phase 6+) |

## 라이선스

MIT License. [LICENSE](./LICENSE) 참조.
