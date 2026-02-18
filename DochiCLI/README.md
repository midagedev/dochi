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
| `standalone` | 앱 없이 직접 LLM API 호출 | 아니오 | 아니오 | 예 (`dochi config set api_key ...`) |

참고: 현재 구현에서 `auto`와 `app`은 동일하게 앱 연결을 요구합니다.

## 3) 주요 명령

### 사용자 명령

```bash
dochi ask "오늘 할 일 정리해줘"
dochi chat
dochi conversation list --limit 20
dochi context show system
dochi context edit memory
dochi config show
dochi config get provider
dochi config set provider anthropic
dochi config set model claude-sonnet-4-5-20250929
dochi config set api_key <YOUR_KEY>
```

### 운영/개발 명령

```bash
dochi session list
dochi dev tool conversation.search '{"query":"회의","limit":5}'
dochi dev log recent --minutes 15
dochi dev log tail --seconds 30 --category App --level info
dochi dev chat stream "최근 대화 3개를 요약해줘"
dochi dev bridge open codex
dochi dev bridge status
dochi dev bridge send <session_id> "pwd"
dochi dev bridge read <session_id> 120
dochi doctor
```

## 4) JSON 출력

- 대부분의 명령은 `--json`을 지원합니다.
- `dochi chat` 대화 모드는 인터랙티브 세션이므로 `--json`을 지원하지 않습니다.

```bash
dochi ask "회의록 요약해줘" --json
```

## 5) 로컬 파일 경로

- CLI 설정 파일: `~/Library/Application Support/Dochi/cli_config.json`
- 로컬 소켓: `~/Library/Application Support/Dochi/run/dochi.sock`
- 로컬 API 토큰: `~/Library/Application Support/Dochi/run/control-plane.token`

앱 연결 모드에서는 CLI가 `control-plane.token`을 자동으로 읽어 `auth_token`을 요청에 포함합니다.

## 6) `dochi doctor`로 상태 점검

`doctor`는 아래 항목을 점검합니다.

- `context_dir`
- `config_file`
- `api_key`
- `app_running`
- `control_plane_socket`
- `control_plane_token_file`
- `control_plane_ping`
- `mode`

앱 연결 모드에서 문제를 만났다면 `dochi doctor` 출력부터 확인하세요.

## 7) 자주 발생하는 문제

### "Dochi 앱이 실행 중이 아닙니다" / "Control Plane 연결 실패"

1. Dochi 데스크톱 앱이 실행 중인지 확인
2. `dochi doctor`에서 `app_running`, `control_plane_socket`, `control_plane_ping` 확인
3. 앱 없이 쓰려면 `--mode standalone` 사용

### "로컬 API 인증에 실패했습니다"

1. `dochi doctor`에서 `control_plane_token_file` 확인
2. Dochi 앱 재실행 후 다시 시도 (토큰 재발급)
3. 앱 데이터 경로 권한/읽기 가능 여부 확인

### standalone에서 "API 키가 설정되지 않았습니다"

```bash
dochi config set api_key <YOUR_KEY>
dochi config set provider anthropic
dochi config set model claude-sonnet-4-5-20250929
```

## 8) 종료 코드

- `0`: 성공
- `1`: 런타임 오류
- `2`: 명령 사용법 오류
- `3`: 설정 오류
- `4`: 앱 연결 오류
- `5`: 인증 오류
