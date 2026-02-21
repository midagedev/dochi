# Dochi CLI Guide

`dochi`는 Dochi 앱을 터미널에서 제어하고 디버깅하는 CLI입니다.

## 1) 빌드와 실행

```bash
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme DochiCLI -configuration Debug build

CLI_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/dochi' -type f | head -n 1)"
"$CLI_BIN" --help
```

원하면 셸에서 별칭을 걸어 간단히 사용할 수 있습니다.

```bash
alias dochi="$CLI_BIN"
dochi doctor
```

## 2) 실행 모드 (`--mode`)

| 모드 | 설명 | 앱 실행 필요 | 토큰 파일 사용 | API 키 필요 |
|------|------|--------------|----------------|------------|
| `auto` (기본값) | 앱 연결 모드로 실행 | 예 | 예 | 아니오 |
| `app` | 앱 연결 모드 강제 | 예 | 예 | 아니오 |
| `standalone` | 디버그 전용 직접 LLM 호출 | 아니오 | 아니오 | 예 (`dochi config set api_key ...`) |

정책:
- 제품 기본 경로는 `auto`/`app` (Host 연결) 입니다.
- `standalone`은 자동 fallback되지 않습니다.
- `standalone`은 `--allow-standalone`(또는 `DOCHI_CLI_ALLOW_STANDALONE=1`)이 있어야만 실행됩니다.

## 3) 주요 명령

### 사용자 명령

```bash
dochi ask "오늘 할 일 정리해줘"
dochi chat
dochi conversation list --limit 20
dochi conversation show 35BBCC9A-EB8F-43E1-9069-D774E46E714D --limit 15
dochi conversation tail --limit 20
dochi log recent --minutes 30 --limit 200
dochi log recent --minutes 60 --category Tool --level error --contains "session"
dochi context show system
dochi context edit memory
dochi config show
dochi config get provider
dochi config set provider anthropic
dochi config set model claude-sonnet-4-5-20250929
```

디버그용 standalone 설정:

```bash
dochi config set api_key <YOUR_KEY>
dochi --mode standalone --allow-standalone ask "연결 테스트"
```

### 운영/개발 명령

```bash
dochi session list
dochi dev tool conversation.search '{"query":"회의","limit":5}'
dochi dev log recent --minutes 15
dochi dev log tail --seconds 30 --category App --level info
dochi dev chat stream "최근 대화 3개를 요약해줘"
dochi dev chat stream --secret --secret-allow-tool datetime -- "현재 시각만 알려줘"
dochi dev bridge open codex --cwd ~/repo/dochi
dochi dev bridge open codex --profile "Dochi Bridge Codex" --cwd ~/work/app --force-working-directory
dochi dev bridge roots --limit 10
dochi dev bridge roots --path ~/repo --path ~/work --limit 20
dochi dev bridge status
dochi dev bridge send <session_id> "pwd"
dochi dev bridge read <session_id> 120
dochi doctor
```

- `dev chat stream --secret`은 secret 모드 플래그를 앱 control-plane에 전달합니다.
- `--secret-allow-tool <name>`를 반복해서 전달하면 허용 도구 후보를 함께 전달합니다.

## 4) JSON 출력

- 대부분의 명령은 `--json`을 지원합니다.
- `dochi chat` 대화 모드는 인터랙티브 세션이므로 `--json`을 지원하지 않습니다.

```bash
dochi ask "회의록 요약해줘" --json
```

## 5) 대화/로그 점검 표준 루틴 (운영 기본)

앞으로 "도치가 이상하게 답했다 / 세션 조회가 꼬였다" 같은 이슈는 아래 순서로 먼저 수집합니다.

```bash
dochi conversation list --limit 10
dochi conversation tail --limit 30
dochi log recent --minutes 20 --limit 300
dochi log recent --minutes 60 --category Tool --level error
```

권장 규칙:
- 최신 대화 본문 확인은 `conversation tail` 또는 `conversation show`를 우선 사용
- 앱 상태/도구 오류 확인은 `log recent`를 우선 사용
- 필요하면 이후에만 `dochi dev log tail`로 실시간 추적

## 6) 로컬 파일 경로

- CLI 설정 파일: `~/Library/Application Support/Dochi/cli_config.json`
- 로컬 소켓: `~/Library/Application Support/Dochi/run/dochi.sock`
- 로컬 API 토큰: `~/Library/Application Support/Dochi/run/control-plane.token`
- 대화 파일: `~/Library/Application Support/Dochi/conversations/*.json`

앱 연결 모드에서는 CLI가 `control-plane.token`을 자동으로 읽어 `auth_token`을 요청에 포함합니다.

## 7) `dochi doctor`로 상태 점검

`doctor`는 아래 항목을 점검합니다.

- `context_dir`
- `config_file`
- `app_running`
- `control_plane_socket`
- `control_plane_token_file`
- `control_plane_ping`
- `mode`
- `standalone_api_key` (`--mode standalone`일 때만)

앱 연결 모드에서 문제를 만났다면 `dochi doctor` 출력부터 확인하세요.

## 8) 자주 발생하는 문제

### "Dochi 앱이 실행 중이 아닙니다" / "Control Plane 연결 실패"

1. Dochi 데스크톱 앱이 실행 중인지 확인
2. `dochi doctor`에서 `app_running`, `control_plane_socket`, `control_plane_ping` 확인
3. 디버깅으로 우회하려면 `--mode standalone --allow-standalone` 사용

### "로컬 API 인증에 실패했습니다"

1. `dochi doctor`에서 `control_plane_token_file` 확인
2. Dochi 앱 재실행 후 다시 시도 (토큰 재발급)
3. 앱 데이터 경로 권한/읽기 가능 여부 확인

### standalone에서 "API 키가 설정되지 않았습니다"

```bash
dochi config set api_key <YOUR_KEY>
dochi config set provider anthropic
dochi config set model claude-sonnet-4-5-20250929
dochi --mode standalone --allow-standalone ask "테스트"
```

### secret smoke에서 "옵션이 프롬프트로 들어간 것처럼" 보임

- 옵션과 프롬프트를 반드시 분리해서 전달해야 합니다.
- 권장 형식:

```bash
dochi --mode app --json dev chat stream \
  --secret \
  --secret-allow-tool datetime \
  -- "반드시 datetime 도구를 1회 호출하고 현재 시각만 한 줄로 답해."
```

- 래퍼 스크립트/CI에서 argv 배열이 아닌 단일 문자열로 전달하면 옵션이 프롬프트로 섞일 수 있습니다.

### "gpt4mini로 설정했는데 안 돈다"

1. 모델 ID는 `gpt4mini`가 아니라 `gpt-4o-mini`입니다.
2. provider/model을 함께 맞춥니다.

```bash
defaults write com.hckim.dochi llmProvider -string openai
defaults write com.hckim.dochi llmModel -string gpt-4o-mini
defaults write com.hckim.dochi offlineFallbackEnabled -bool false
```

3. 현재 값을 확인합니다.

```bash
defaults read com.hckim.dochi llmProvider
defaults read com.hckim.dochi llmModel
defaults read com.hckim.dochi offlineFallbackEnabled
```

4. secret smoke 결과가 `secret-mock llm fallback`이면 provider/API 키 이슈를 fallback으로 우회한 상태입니다.
   이 경우 LLM 경로 자체 검증을 위해 OpenAI API 키를 먼저 점검하세요.

## 9) 종료 코드

- `0`: 성공
- `1`: 런타임 오류
- `2`: 명령 사용법 오류
- `3`: 설정 오류
- `4`: 앱 연결 오류
- `5`: 인증 오류

## 10) 비-UI 기능 검증 표준 절차 (Host 모드)

비-UI 기능 검증 기본 원칙:
- 제품 검증은 `--mode app`(또는 `auto`)로 수행
- CLI와 앱은 같은 빌드 산출물(같은 DerivedData) 쌍으로 실행
- `standalone`은 보조 디버깅 경로이며 제품 E2E 검증 기준이 아님

### 권장 순서

```bash
APP_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/Dochi.app' -type d | head -n 1)"
CLI_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/dochi' -type f | head -n 1)"

open "$APP_BIN"
"$CLI_BIN" --mode app doctor
"$CLI_BIN" --mode app session list --json
"$CLI_BIN" --mode app dev log recent --minutes 5 --json
"$CLI_BIN" --mode app ask "host mode 왕복 검증. OK만 답해줘" --json
```

### 합격 기준

- `doctor`가 `정상` (`app_running`, `control_plane_socket`, `control_plane_ping` 모두 `OK`)
- `session list`가 정상 응답
- `dev log recent`가 정상 응답
- `ask` 요청이 앱에서 처리되어 응답이 반환됨

### 자주 헷갈리는 케이스

- 앱이 여러 위치에서 실행되는 경우:
  - 예) `/Applications/Dochi.app` + DerivedData `Dochi.app`
  - 현상: 간헐적 `Dochi 앱이 실행 중이 아닙니다`, `Control Plane 연결 실패`
  - 대응: 하나만 실행하고, CLI도 같은 빌드 산출물 경로로 고정
- `interaction_busy`:
  - 앱이 다른 요청 처리 중인 상태
  - 잠시 후 재시도하거나 UI에서 현재 작업 완료 후 재검증

## 11) 신규 도구 추가 검증 플레이북 (LLM 호출/E2E 스모크)

이 절차는 "LLM이 새 도구를 올바르게 호출하는지"를 빠르게 확인하기 위한 표준 루틴입니다.
실제 도구 동작 검증은 별도 테스트로 분리합니다.

### 11-1. 검증 범위 분리

- `dev chat stream --secret`:
  - 목적: LLM의 `tool_call` 발생 여부 + control-plane 스트림 연결 검증
  - 특징: 도구는 mock 실행, 대화/메모리 저장은 생략됨
  - 용도: 라이브 E2E 스모크
- `dev tool <name>` + XCTest:
  - 목적: 실제 도구 구현 동작 검증
  - 특징: 시스템에 실제 영향을 줄 수 있으므로 안전한 입력/임시 경로 필수

### 11-2. 사전 점검

```bash
dochi --mode app doctor
```

- `app_running`, `control_plane_socket`, `control_plane_ping`이 모두 `OK`여야 합니다.

### 11-3. 신규 도구 호출 스모크 (PC 영향 없음)

```bash
TOOL_NAME="datetime"
PROMPT="반드시 ${TOOL_NAME} 도구를 1회 호출한 뒤 결과를 한 줄로 요약해."

RESULT="$(dochi --mode app --json dev chat stream --secret --secret-allow-tool "$TOOL_NAME" -- "$PROMPT")"
echo "$RESULT"
```

권장 판정(`jq`):

```bash
echo "$RESULT" | jq -e --arg t "$TOOL_NAME" '
  .status == "ok"
  and any(.data.events[]?; .type == "tool_call" and .tool_name == $t)
  and any(.data.events[]?; .type == "tool_result")
  and any(.data.events[]?; .type == "done")
'
```

추가 확인 포인트:

- `tool_result.text`에 `secret-mock tool`이 포함되면 mock 경로를 탄 것입니다.
- `done.text`에 `secret-mock llm fallback`이 포함되면 LLM/provider 실패를 deterministic fallback으로 우회한 것입니다.
- 최종 메시지에 `chat.stream 완료`가 포함되어야 합니다.

### 11-4. secret 모드 가드레일 점검

```bash
dochi --mode app --json dev chat stream --secret "테스트"
```

- 기대 결과: 실패
- 실패 코드: `missing_secret_allowed_tools`

### 11-5. 실제 도구 동작 검증 (별도)

1. 단위 테스트 추가: 새 도구의 성공/실패/입력 검증 케이스
2. 필요 시 `dochi --mode app dev tool <tool_name> <args_json>`로 수동 확인
3. 파일/명령/시스템 변경 가능 도구는 반드시 임시 디렉토리/테스트 전용 데이터로만 검증
4. 회귀 확인:

```bash
xcodebuild test -project Dochi.xcodeproj -scheme Dochi -destination 'platform=macOS' -only-testing:DochiTests/NativeAgentLoopServiceTests -only-testing:DochiTests/SessionStreamingTests
```

### 11-6. PR 체크리스트

- [ ] `spec/tools.md`에 새 도구 스키마 반영
- [ ] secret smoke에서 `tool_call` 이벤트 확인
- [ ] 실제 도구 동작 단위 테스트 추가
- [ ] 시스템 영향 가능 도구는 안전한 테스트 경로/데이터 사용 증빙 포함
