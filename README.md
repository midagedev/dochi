# Dochi (도치)

**Hermes Agent를 위한 음성·캐릭터 인터페이스.** 한국어로 말을 걸면 듣고, 3D 아바타로 말하고 표정짓는 macOS 앱입니다. 생각하는 일(추론·기억·스킬·도구)은 [Nous Research의 Hermes Agent](https://github.com/NousResearch/hermes-agent)가 맡습니다.

```
사용자 ──말──▶  Dochi (한국어 STT)                  ──텍스트──▶  Hermes Agent
사용자 ◀─말+표정─ Dochi (TTS + VRM 아바타 + 립싱크)  ◀─델타/도구 이벤트─┘
                         └── 로컬 WebSocket 브리지 (HermesBridge/) ──┘
```

> Dochi는 한때 자체 LLM 루프·도구·동기화까지 떠안아 ~102K줄로 비대해졌습니다. 그 두뇌를 Hermes에 위임하고, 가장 잘하는 **음성과 캐릭터**에 집중하도록 ~8K줄로 전면 재작성했습니다.

## 핵심 기능

- **한국어 음성 인식** — Apple STT + 웨이크워드("도치야"), 항상 듣기 옵션
- **멀티 TTS** — 시스템 / Google Cloud / Typecast / 로컬 ONNX(Supertonic, 오프라인)
- **VRM 3D 아바타** — RealityKit 렌더링, 상태별 표정 + 발화 립싱크
- **Hermes 연동** — 추론·영속 메모리·스킬·40+ 도구·MCP를 백엔드에 위임
- **스트리밍** — 응답을 문장 단위로 받아 즉시 말하기, 도구 실행 상태 표시
- **프로액티브** — Hermes가 먼저 건네는 메시지도 말로 전달

## 빠른 시작

### 1) 백엔드: Hermes 브리지

```bash
cd HermesBridge
python -m venv .venv && source .venv/bin/activate
pip install -e .
python -m dochi_hermes_bridge --echo   # Hermes 없이 음성 루프부터 검증
# 운영: pip install -e ".[hermes]" 후  python -m dochi_hermes_bridge
```

브리지가 첫 실행 시 `~/.hermes/dochi_bridge_token`을 생성하고, 앱이 같은 파일을 읽어 자동 인증합니다.

### 2) 앱

```bash
brew install xcodegen          # 요구사항: macOS 14+, Xcode 16+
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme Dochi build
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

설정 → **Hermes** 탭에서 호스트/포트를 확인하고, **말하기/아바타** 탭에서 TTS·아바타를 켭니다. 마이크 버튼이나 "도치야"로 대화를 시작하세요.

## 구조

- 앱(Swift): [CLAUDE.md](./CLAUDE.md) 의 *Code Structure / Architecture* 참고
- 브리지(Python) 및 와이어 프로토콜: [HermesBridge/README.md](./HermesBridge/README.md)
