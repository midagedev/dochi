# Dochi (도치)

macOS 음성 비서 앱.

- 멀티 LLM 지원 (OpenAI, Anthropic, Z.AI)
- Supertonic 로컬 TTS (ONNX, F1~F5/M1~M5 10종 음성)
- Apple Speech 프레임워크 STT
- 웨이크워드 + 연속 대화
- 내장 도구: 웹검색, 미리알림, 음성 알람, 이미지 생성

## 요구사항

- macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 빌드

```bash
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme Dochi build
```

## 기능

### 음성 대화
- OpenAI / Anthropic / Z.AI SSE 스트리밍
- Supertonic ONNX 로컬 TTS (한국어, 영어 등 다국어 지원, F1~F5/M1~M5 10종 음성)
- Apple Speech 프레임워크 STT
- 문장 단위 스트리밍 TTS (LLM 응답 중 즉시 음성 재생)

### 웨이크워드 & 연속 대화
- 웨이크워드 감지 (기본: "도치야")
- LLM 기반 발음 유사 변형 자동 생성으로 인식률 향상
- 실시간 웨이크워드 모니터 (등록된 변형 목록 + 인식 텍스트 표시)
- **연속 대화 모드**: 웨이크워드로 세션 시작 후 웨이크워드 없이 대화 지속
- 10초 무응답 시 "대화를 종료할까요?" 질문
- 직접 종료 요청 지원 ("대화 종료", "그만할게", "잘가" 등)

### 내장 도구
- **웹검색**: Tavily API를 통한 실시간 웹 검색
- **Apple 미리알림**: 미리알림 생성, 조회, 완료 처리
- **음성 알람**: TTS로 알림 메시지를 읽어주는 타이머/알람 설정
- **이미지 생성**: fal.ai FLUX를 통한 AI 이미지 생성 (대화창에 인라인 표시)

### 프롬프트 파일 관리
```
~/Library/Application Support/Dochi/
├── system.md    # 페르소나 + 행동 지침 (수동 편집)
├── memory.md    # 사용자 기억 (자동 누적)
└── images/      # 생성된 이미지 저장
```
- **system.md**: AI의 정체성과 행동 지침 정의
- **memory.md**: 세션 종료 시 LLM이 대화 분석하여 중요 정보 자동 추출
- 다음 세션 시작 시 두 파일 모두 시스템 프롬프트에 포함
- 사이드바에서 확인/편집 가능
- 자동 압축: memory.md 크기 초과 시 LLM으로 요약 (기본 15KB)

### TTS 설정
- 속도 조절 (0.8x ~ 1.5x)
- 표현력/품질 조절 (디퓨전 스텝 4~20)

## 사용법

1. 설정에서 API 키 입력 (OpenAI / Anthropic / Z.AI 중 하나 이상)
2. 선택: Tavily API 키 (웹검색), Fal.ai API 키 (이미지 생성)
3. "연결" 클릭 (TTS 모델 로드)
4. 웨이크워드 활성화 시: "도치야" 호출 → 대화 시작
5. 대화 종료: "대화 종료", "그만할게" 등 또는 10초 무응답 후 확인

## 파일 구조

```
Dochi/
├── Models/
│   ├── Enums.swift            # LLMProvider, SupertonicVoice
│   ├── Conversation.swift     # 대화 히스토리 모델
│   ├── Message.swift          # 대화 메시지 모델 (이미지 URL 지원)
│   └── Settings.swift         # 앱 설정 (UserDefaults + Keychain)
├── Services/
│   ├── Protocols/             # 서비스 프로토콜 (DI용)
│   ├── BuiltInTools/          # 내장 도구 모듈
│   │   ├── BuiltInToolProtocol.swift  # 도구 프로토콜
│   │   ├── WebSearchTool.swift        # Tavily 웹검색
│   │   ├── RemindersTool.swift        # Apple 미리알림
│   │   ├── AlarmTool.swift            # 음성 알람
│   │   └── ImageGenerationTool.swift  # fal.ai 이미지 생성
│   ├── BuiltInToolService.swift # 내장 도구 라우터
│   ├── ContextService.swift   # system.md, memory.md 파일 관리
│   ├── ConversationService.swift # 대화 히스토리 저장
│   ├── KeychainService.swift  # API 키 저장
│   ├── LLMService.swift       # LLM SSE 스트리밍
│   ├── MCPService.swift       # MCP 서버 연동
│   ├── SoundService.swift     # UI 효과음
│   ├── SpeechService.swift    # Apple STT + 웨이크워드
│   ├── SupertonicService.swift # ONNX TTS
│   ├── ChangelogService.swift # 버전/변경 로그
│   └── Supertonic/
│       └── SupertonicHelpers.swift # ONNX 추론 헬퍼
├── ViewModels/
│   └── DochiViewModel.swift   # 메인 뷰모델 (오케스트레이터)
└── Views/
    ├── ContentView.swift      # 메인 레이아웃 + 사이드바
    ├── ConversationView.swift # 대화 표시 + 이미지 렌더링
    ├── SettingsView.swift     # 설정 시트
    └── ChangelogView.swift    # 변경 로그 표시
```
