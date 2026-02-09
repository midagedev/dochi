# Dochi (도치)

디바이스에 상주하며 로컬 환경을 직접 제어하는 AI 에이전트 플랫폼.

bash 실행, 앱 제어, 코딩 에이전트 연동까지. 에이전트마다 고유한 페르소나와 권한을 갖고, 워크스페이스 단위로 컨텍스트를 공유합니다.

> 비전: [CONCEPT.md](./CONCEPT.md) · 개발 계획: [ROADMAP.md](./ROADMAP.md)

## 현재 구현됨

- **멀티 LLM** — OpenAI, Anthropic, Z.AI SSE 스트리밍
- **텍스트 + 음성** — 텍스트 입력 기본, 웨이크워드("도치야")로 음성 전환
- **로컬 TTS** — Supertonic ONNX 엔진, 10종 한국어 음성
- **장기 기억** — 대화에서 중요 정보 자동 추출, 메모리 압축
- **내장 도구** — 웹검색(Tavily), 미리알림, 알람, 이미지 생성(fal.ai)
- **MCP 연동** — Model Context Protocol 서버로 도구 확장
- **클라우드 동기화** — Supabase 기반 컨텍스트·대화 동기화

## 다음 목표

- **로컬 디바이스 제어** — bash, 앱 제어, 파일 관리, 코딩 에이전트 연동
- **멀티 에이전트** — 에이전트별 페르소나, 웨이크워드, 권한
- **멀티 워크스페이스** — 가족/팀 등 목적별 워크스페이스, 디바이스 공유

```
"프로젝트 빌드해줘"          → $ npm run build
"rate limit 추가해줘"        → Claude Code 세션 → 코드 수정 → 결과 요약
"엄마한테 FaceTime 걸어줘"   → FaceTime 실행 → 통화 시작
"내일 일정 알려줘"           → 캘린더 조회 → 음성 안내
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
개인 컨텍스트 (사용자 소유, 워크스페이스 횡단)
├── 가족 워크스페이스
│   ├── 워크스페이스 기억
│   ├── 도치 (system.md + 에이전트 기억)
│   └── 키키 (system.md + 에이전트 기억)
└── 팀 워크스페이스
    ├── 워크스페이스 기억
    └── 코디 (system.md + 에이전트 기억)
```

개인 컨텍스트는 dotfiles처럼 동작합니다. 클라우드에 동기화되어, 새 워크스페이스나 새 디바이스에서도 AI가 나를 즉시 이해합니다.

## 커스터마이징

현재는 `~/Library/Application Support/Dochi/` 아래 마크다운 파일로 동작을 정의합니다.

| 파일 | 역할 |
|------|------|
| `system.md` | 페르소나, 행동 규칙 |
| `memory.md` | 장기 기억 (자동 축적) |

멀티 에이전트 구현 후에는 에이전트별 `system.md`와 `memory.md`로 확장됩니다.

## 라이선스

MIT License. [LICENSE](./LICENSE) 참조.
