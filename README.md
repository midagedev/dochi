# Dochi (도치)

로컬 디바이스를 직접 제어하는 AI 에이전트 플랫폼.

macOS에서 bash 실행, 앱 제어, 파일 관리까지 — AI에게 손과 발을 줍니다. 여러 에이전트가 각자의 페르소나로 동작하고, `system.md` 하나로 새 에이전트를 만듭니다.

> 자세한 비전은 [CONCEPT.md](./CONCEPT.md), 개발 계획은 [ROADMAP.md](./ROADMAP.md) 참조.

## 특징

- **로컬 디바이스 제어** — bash 실행, 앱 열기, 파일 관리, AppleScript, Shortcuts
- **코딩 에이전트 연동** — Claude Code, OpenCode를 실행·중계·세션 관리
- **멀티 에이전트** — 에이전트마다 고유한 페르소나, 웨이크워드, 권한
- **멀티 LLM** — OpenAI, Anthropic, Z.AI 중 선택
- **텍스트 + 음성** — 텍스트 입력 기본, 웨이크워드로 음성 모드 전환
- **로컬 TTS** — Supertonic ONNX 엔진, 10종 한국어 음성
- **장기 기억** — 대화에서 중요 정보를 자동 추출하여 다음 세션에 반영
- **도구 확장** — 내장 도구 + MCP 서버 연동

## 에이전트 예시

| 에이전트 | 페르소나 | 웨이크워드 | 주요 능력 |
|---------|---------|-----------|----------|
| 도치 | 범용 비서 | "도치야" | 일정, 미리알림, 앱 제어, FaceTime |
| 코디 | 시니어 개발자 | "코디야" | Claude Code/OpenCode 연동, bash, git, 빌드 |
| 키키 | 아이 대화 친구 | "키키야" | 이야기, 교육, 제한된 권한 |
| (커스텀) | system.md로 정의 | 자유 설정 | 에이전트별 권한 설정 |

## 로컬 디바이스 능력

```
"프로젝트 빌드해줘"            → $ npm run build
"로그인 API에 rate limit 추가해줘" → Claude Code 세션 → 코드 수정 → 결과 요약
"아까 작업 이어서 해줘"         → 기존 코딩 세션 재개
"엄마한테 FaceTime 걸어줘"      → FaceTime 앱 실행 → 통화 시작
"내일 일정 알려줘"              → 캘린더 조회 → 음성으로 안내
```

| 능력 | 방법 |
|------|------|
| Shell 실행 | bash/zsh 명령어 직접 실행 |
| 코딩 에이전트 | Claude Code, OpenCode 실행·중계·세션 관리 |
| 앱 열기/제어 | open, AppleScript (FaceTime, Keynote 등) |
| 파일 관리 | 파일 읽기/쓰기/검색/정리 |
| Apple Shortcuts | 사용자 정의 자동화 실행 |
| 미리알림/캘린더 | EventKit으로 일정·할 일 관리 |
| 클립보드 | 복사/붙여넣기 |
| 스크린샷 | 화면 캡처 |

## 빠른 시작

```bash
# 요구사항: macOS 14+, Xcode 15+, XcodeGen
brew install xcodegen

# 빌드
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme Dochi build

# 실행
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

1. 설정에서 API 키 입력 (OpenAI / Anthropic / Z.AI 중 하나 이상)
2. 텍스트로 바로 대화 시작
3. 음성 사용 시: 웨이크워드 활성화 → "도치야" 호출 → 연속 대화

## 에이전트 만들기

에이전트는 `~/Library/Application Support/Dochi/agents/` 아래 디렉토리로 관리됩니다.

| 파일 | 역할 |
|------|------|
| `{agent}/system.md` | 페르소나, 행동 규칙, 톤 |
| `{agent}/memory.md` | 에이전트 고유 장기 기억 |
| `config.json` | 이름, 웨이크워드, 권한 설정 |

예시: 아이 대화 상대를 만들려면 `system.md`에 "초등학생 눈높이로 대화해줘"를 적고, bash 권한을 끄면 됩니다.

## 음성 모드

- **웨이크워드**: 에이전트별 호출어 — "도치야", "코디야", "키키야"
- **연속 대화**: 웨이크워드로 세션 시작 후 웨이크워드 없이 대화 지속
- **세션 종료**: "대화 종료", "그만할게" 등 직접 종료 또는 10초 무응답 시 자동 확인

## 내장 도구

| 도구 | API 키 | 기능 |
|------|--------|------|
| Shell 실행 | - | bash/zsh 명령어 실행 |
| 코딩 에이전트 | - | Claude Code/OpenCode 세션 실행, 태스크 위임, 결과 중계 |
| 앱 제어 | - | macOS 앱 열기/조작 (AppleScript) |
| 웹검색 | Tavily | 실시간 웹 검색 |
| 미리알림 | - | Apple 미리알림 생성/조회/완료 |
| 알람 | - | TTS로 알림 메시지를 읽어주는 타이머 |
| 이미지 생성 | fal.ai | FLUX 기반 AI 이미지 생성 |

MCP(Model Context Protocol) 서버를 추가로 연결하여 도구를 확장할 수 있습니다.

## 라이선스

MIT License. [LICENSE](./LICENSE) 참조.
