# MCP 코딩 프로파일 운영 가이드 (Phase 3)

## 목적
- `#326`의 기본 코딩 MCP 프로파일(filesystem/git/shell)과 lifecycle 복구 동작을 운영 가능한 형태로 정리한다.
- 앱 시작 시 MCP 서버가 비어 있고 아직 기본 프로파일을 만든 적이 없으면 한 번만 자동 부트스트랩한다.

## 기본 프로파일
앱이 생성하는 기본 프로파일:

1. `coding-filesystem`
- command: `npx`
- args: `-y @modelcontextprotocol/server-filesystem <workspaceRoot>`
- 역할: 워크스페이스 파일 읽기/쓰기

2. `coding-git`
- command: `uvx`
- args: `mcp-server-git --repository <gitRepoPath>`
- 역할: git 상태/커밋/브랜치 관련 도구
- 참고: 앱이 시작 시점에 Git 루트를 찾지 못하면 기본적으로 `disabled`로 생성됨

3. `coding-shell`
- command: `npx`
- args: `-y @mako10k/mcp-shell-server`
- env:
  - `MCP_SHELL_DEFAULT_WORKDIR=<workspaceRoot>`
  - `MCP_ALLOWED_WORKDIRS=<workspaceRoot>`
  - `LOG_LEVEL=warn`
- 역할: 제한된 작업 디렉토리 내 shell 실행

## 전제 조건
- Node.js + `npx` 설치
- Python `uv` + `uvx` 설치 (`coding-git`)
- `coding-git`는 유효한 git repository 경로가 필요

## Lifecycle / 복구 정책
- MCPService는 주기적으로 서버 프로세스 생존 여부를 점검한다.
- 프로세스 종료 감지 시:
  1. 연결/도구 라우팅 정보를 정리
  2. 서버가 활성화되어 있으면 자동 재연결 시도
  3. 재연결 실패 시 `error` 상태 유지
- 도구 호출 시점에도 연결 비정상 상태를 다시 점검하고 필요 시 재연결 후 1회 재시도한다.

## 비가용 fallback 메시지
- MCP 서버 비가용(`notConnected`, `connectionFailed`) 시 사용자에게 다음 안내를 반환한다:
  - MCP 상태 확인 경로: `설정 > 통합 > MCP`
  - 임시 대안: `terminal.run`, `git.*` 내장 도구

## 운영 체크리스트
- 앱 최초 실행 후 `설정 > 통합 > MCP`에서 3개 기본 프로파일이 생성되었는지 확인
- `coding-git`가 비활성화 상태면 repository 경로를 지정해 활성화
- 의도적으로 MCP 서버 프로세스를 중단해 자동 복구 로그가 남는지 확인
- 사용자가 MCP 서버를 모두 삭제한 뒤 재시작해도 기본 프로파일이 자동으로 재생성되지 않는지 확인
