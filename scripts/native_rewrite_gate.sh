#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${1:-$ROOT_DIR/.artifacts/native-rewrite-gate/$TIMESTAMP}"
LOG_FILE="$ARTIFACT_DIR/xcodebuild.log"
JSON_REPORT="$ARTIFACT_DIR/native-rewrite-gate-report.json"
MARKDOWN_REPORT="$ARTIFACT_DIR/native-rewrite-gate-report.md"

mkdir -p "$ARTIFACT_DIR"

echo "[1/2] Running native rewrite gate tests"
DOCHI_GATE_REPORT_DIR="$ARTIFACT_DIR" \
  xcodebuild test \
  -project Dochi.xcodeproj \
  -scheme Dochi \
  -destination 'platform=macOS' \
  -only-testing:DochiTests/NativeRewriteGateRunnerTests \
  | tee "$LOG_FILE"

echo "[2/2] Verifying generated reports"
if [[ ! -f "$JSON_REPORT" || ! -f "$MARKDOWN_REPORT" ]]; then
  # xcodebuild test 환경에서는 사용자 정의 env가 테스트 프로세스로 전달되지 않을 수 있어
  # 테스트가 임시 디렉터리 fallback 경로에 리포트를 기록한다.
  LATEST_JSON="$(find "${TMPDIR:-/tmp}" -path '*dochi-native-rewrite-gate-*/native-rewrite-gate-ci/native-rewrite-gate-report.json' -print 2>/dev/null | xargs ls -t 2>/dev/null | head -n 1 || true)"
  if [[ -n "$LATEST_JSON" && -f "$LATEST_JSON" ]]; then
    LATEST_MD="${LATEST_JSON%.json}.md"
    cp "$LATEST_JSON" "$JSON_REPORT"
    if [[ -f "$LATEST_MD" ]]; then
      cp "$LATEST_MD" "$MARKDOWN_REPORT"
    fi
  fi
fi

if [[ ! -f "$JSON_REPORT" ]]; then
  echo "Missing JSON report: $JSON_REPORT" >&2
  exit 1
fi

if [[ ! -f "$MARKDOWN_REPORT" ]]; then
  echo "Missing Markdown report: $MARKDOWN_REPORT" >&2
  exit 1
fi

echo "Native rewrite gate complete"
echo "- JSON: $JSON_REPORT"
echo "- Markdown: $MARKDOWN_REPORT"
echo "- Build log: $LOG_FILE"
