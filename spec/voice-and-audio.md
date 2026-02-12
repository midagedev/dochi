# Voice & Audio

음성 입출력과 웨이크워드 매칭, 에이전트 라우팅 정의.

---

## Wake Word Matching

### 알고리즘
- 한글 자모 분해 + Levenshtein distance (슬라이딩 윈도우)
- 윈도우 크기: 웨이크워드 음절 수 ± 1. 공백 제거 후 매칭
- 임계값: 미지정 시 `auto = max(2, jamo_count / 4)`
- API: `JamoMatcher.isMatch(transcript: String, wakeWord: String, threshold: Int?) -> Bool`

### 설정
- `wakeWordEnabled: Bool`
- `wakeWord: String` (앱 기본 웨이크워드)
- 에이전트별 웨이크워드: `AgentConfig.wakeWord`

### 품질 목표
- FAR (false accept rate): < 5% (일상 대화 환경)
- FRR (false reject rate): < 10% (명확 발화 기준)
- 임계값 튜닝: 사용자가 `settings.set` 도구 또는 설정 UI로 조정 가능

---

## Wake Word → Agent Routing

웨이크워드 감지 후 에이전트 선택 규칙.

### 매칭 순서
1. 현재 워크스페이스의 에이전트 목록에서 `wakeWord` 매칭 시도
2. 전체 워크스페이스를 순회하며 매칭 (워크스페이스 간 탐색)
3. 매칭된 에이전트가 없으면 앱 기본 에이전트 활성화

### 충돌 해결
- 같은 워크스페이스 내 웨이크워드 중복: 생성 시 거부 (유니크 제약)
- 다른 워크스페이스 간 웨이크워드 중복: 현재 워크스페이스 우선
- 매칭 시 워크스페이스 자동 전환: 다른 워크스페이스 에이전트 매칭 시 해당 워크스페이스로 전환

### 텍스트 모드 에이전트 전환
- 웨이크워드 없이 에이전트 전환:
  - 설정 UI에서 활성 에이전트 변경
  - `agent.set_active` 도구 사용
  - Command palette (향후)

### 전환 시 대화 처리
- 에이전트 전환 시 새 대화 시작 (이전 대화는 종료+저장)
- 연속 대화 세션 중 다른 웨이크워드 감지 시: 현재 세션 종료 → 새 에이전트로 새 세션

---

## STT (Speech-to-Text)

- 엔진: Apple Speech (온디바이스 / Apple API, OS 설정 따름)
- 침묵 타임아웃: `settings.sttSilenceTimeout` (초)
- Interaction mode: `voiceAndText` | `textOnly`
  - `textOnly` 모드에서 웨이크워드 감지 비활성

---

## TTS (Supertonic ONNX)

### 음성
- `SupertonicVoice`: F1~F5, M1~M5 (한국어 10종)
- 지원 언어 (모델): en, ko, es, pt, fr

### 설정
- `settings.ttsSpeed: Float`
- `settings.ttsDiffusionSteps: Int`

### 파이프라인
1. 텍스트 전처리 (이모지 제거, 구두점/따옴표 정규화)
2. Unicode → text IDs / mask
3. Duration inference → latent sampling (chunking)
4. Diffusion steps → waveform
5. Audio engine 재생 (큐 기반: `enqueueSentence` → `processQueue`)

### 문장 단위 스트리밍
- LLM SSE 스트리밍 중 문장 경계(줄바꿈, 마침표 등)에서 TTS 큐에 적재
- 이전 문장 재생 중 다음 문장 합성 (파이프라이닝)
- TTS 큐 비어있으면 → speaking 완료 → 다음 상태 전이

### 엔진 관리
- 최초 사용 시 모델 다운로드 (앱 번들 또는 CDN)
- 사전 로드: 앱 시작 시 또는 음성 모드 활성화 시 warm-up
- 메모리: 미사용 시 모델 언로드 가능

---

## UX Signals

- `SoundService.playWakeWordDetected()` — 웨이크워드 감지 시 확인음
- `SoundService.playInputComplete()` — STT 발화 종료 시 확인음
- 시각 피드백: 상태바에 현재 상태 표시 (listening, processing, speaking)
