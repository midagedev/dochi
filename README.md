# Dochi (도치)

집 Mac에 상주하며 가족과 팀의 맥락을 이해하는 macOS 네이티브 AI 에이전트.

워크스페이스 단위로 기억을 관리하고, 에이전트마다 고유한 페르소나와 권한을 갖습니다. SwiftUI 네이티브 앱으로 FaceTime, 캘린더, 미리알림, Apple Shortcuts와 깊이 통합됩니다.

> 비전: [CONCEPT.md](./CONCEPT.md) · 개발 계획: [ROADMAP.md](./ROADMAP.md)

## 현재 구현됨

- **macOS 네이티브** — SwiftUI 앱, macOS API 깊은 통합
- **멀티 LLM** — OpenAI, Anthropic, Z.AI SSE 스트리밍
- **텍스트 + 음성** — 텍스트 입력 기본, 웨이크워드("도치야")로 음성 전환
- **로컬 TTS** — Supertonic ONNX 엔진, 10종 한국어 음성
- **장기 기억** — 대화에서 중요 정보 자동 추출, 메모리 압축
- **내장 도구** — 설정/에이전트/컨텍스트/프로필/워크스페이스/텔레그램 관리, 웹검색(Tavily), 미리알림, 알람, 이미지 생성(fal.ai) [[가이드](docs/built-in-tools.md)]
- **MCP 연동** — Model Context Protocol 서버로 도구 확장
- **클라우드 동기화** — Supabase 기반 컨텍스트·대화 동기화
- **텔레그램 연동** — 앱 실행 중 DM 수신, 스트리밍 응답 및 도구 진행 스니펫 전송

## 다음 목표

- **멀티 워크스페이스** — 가족/팀 등 목적별 워크스페이스, 컨텍스트 분리
- **멀티 에이전트** — 에이전트별 페르소나, 웨이크워드, 권한
- **디바이스 제어** — FaceTime, 앱 제어, 코딩 에이전트 연동

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
4. (선택) 텔레그램: 설정 → 통합에서 봇 토큰 입력 후 토글 활성화

## 컨텍스트 구조

```
~/Library/Application Support/Dochi/
├── system_prompt.md             # 앱 레벨 기본 규칙 (선택)
├── profiles.json                # 사용자 프로필(가족)
├── memory/                      # 개인 기억(사용자별)
│   └── {userId}.md
└── workspaces/{workspaceId}/
    ├── config.json
    ├── memory.md                # 워크스페이스 공유 기억
    └── agents/{name}/
        ├── persona.md           # 에이전트 페르소나
        ├── memory.md            # 에이전트 기억
        └── config.json          # 에이전트 설정 (웨이크워드 등)

# 레거시(존재 시 계속 읽기): system.md, family.md, memory.md
```

개인 컨텍스트는 dotfiles처럼 동작합니다. 클라우드에 동기화되어, 새 워크스페이스나 새 디바이스에서도 AI가 나를 즉시 이해합니다. 레거시 파일이 있는 경우도 자동으로 포함되며, 워크스페이스 기반 구조로 점진 마이그레이션할 수 있습니다.

## 커스터마이징

현재는 `~/Library/Application Support/Dochi/` 아래 파일로 동작을 정의합니다.

- `system_prompt.md` — 앱 레벨 기본 규칙
- `workspaces/{id}/memory.md` — 워크스페이스 공유 기억
- `workspaces/{id}/agents/{name}/persona.md` — 에이전트 페르소나
- `workspaces/{id}/agents/{name}/memory.md` — 에이전트 기억
- `profiles.json` — 사용자 프로필(다중 사용자)
- `memory/{userId}.md` — 개인 기억
- (레거시) `system.md`, `family.md`, `memory.md`

## 라이선스

MIT License. [LICENSE](./LICENSE) 참조.
