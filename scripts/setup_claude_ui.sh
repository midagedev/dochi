#!/usr/bin/env bash
set -euo pipefail

# Claude Code UI + Dochi integration bootstrapper
# - Installs/starts claudecodeui (optionally via pm2)
# - Registers or logs in to get API token
# - Writes Dochi settings (UserDefaults) and token (AppSupport file store)

PORT=3001
BASE_URL=""
USERNAME=""
PASSWORD=""
METHOD="npm"        # npm|npx
INSTALL_PM2=1        # 1=true, 0=false
SETTINGS_DOMAIN="com.hckim.dochi"

usage() {
  cat <<USAGE
Usage: $0 --username <u> --password <p> [--port 3001] [--base-url http://localhost:3001] [--method npm|npx] [--no-pm2]

Examples:
  $0 --username admin --password secret --port 3001 --method npm
  $0 --username me --password pass --base-url http://localhost:3001 --no-pm2
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2;;
    --password) PASSWORD="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --base-url) BASE_URL="$2"; shift 2;;
    --method) METHOD="$2"; shift 2;;
    --no-pm2) INSTALL_PM2=0; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
  echo "ERROR: --username and --password are required" >&2
  usage; exit 1
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: Node.js and npm are required. Install via https://nodejs.org/" >&2
  exit 1
fi

BASE_URL=${BASE_URL:-"http://localhost:${PORT}"}

echo "==> Installing/starting Claude Code UI (method=$METHOD, pm2=$INSTALL_PM2, port=$PORT)"
if [[ "$METHOD" == "npm" ]]; then
  npm install -g @siteboon/claude-code-ui >/dev/null 2>&1 || npm install -g @siteboon/claude-code-ui
fi

if [[ "$INSTALL_PM2" -eq 1 ]]; then
  if ! command -v pm2 >/dev/null 2>&1; then
    npm install -g pm2 >/dev/null 2>&1 || npm install -g pm2
  fi
  pm2 delete claude-code-ui >/dev/null 2>&1 || true
  pm2 start cloudcli --name "claude-code-ui" -- --port "$PORT"
  pm2 save >/dev/null 2>&1 || true
else
  echo "NOTE: Running via npx in foreground (Ctrl+C to stop). Consider --method npm + pm2 for background."
  npx @siteboon/claude-code-ui --port "$PORT" &
fi

echo "==> Waiting for server health at ${BASE_URL}/health"
for i in {1..30}; do
  if curl -fsS "$BASE_URL/health" >/dev/null 2>&1; then
    echo "OK"
    break
  fi
  sleep 0.5
  if [[ $i -eq 30 ]]; then
    echo "ERROR: Server health check failed" >&2
    exit 1
  fi
done

echo "==> Checking auth status"
STATUS_JSON=$(curl -fsS -H "Content-Type: application/json" "$BASE_URL/api/auth/status" || echo '{}')
NEEDS_SETUP=$(python3 - <<'PY'
import json,sys
try:
  obj=json.loads(sys.stdin.read())
  print('true' if obj.get('needsSetup') else 'false')
except Exception:
  print('false')
PY
<<<"$STATUS_JSON")

TOKEN=""
if [[ "$NEEDS_SETUP" == "true" ]]; then
  echo "==> Registering first user"
  REGISTER_JSON=$(curl -fsS -X POST -H "Content-Type: application/json" \
    -d '{"username":"'"$USERNAME"'","password":"'"$PASSWORD"'"}' \
    "$BASE_URL/api/auth/register")
  TOKEN=$(python3 - <<'PY'
import json,sys
obj=json.loads(sys.stdin.read())
print(obj.get('token',''))
PY
<<<"$REGISTER_JSON")
else
  echo "==> Logging in"
  LOGIN_JSON=$(curl -fsS -X POST -H "Content-Type: application/json" \
    -d '{"username":"'"$USERNAME"'","password":"'"$PASSWORD"'"}' \
    "$BASE_URL/api/auth/login")
  TOKEN=$(python3 - <<'PY'
import json,sys
obj=json.loads(sys.stdin.read())
print(obj.get('token',''))
PY
<<<"$LOGIN_JSON")
fi

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: Failed to obtain API token" >&2
  exit 1
fi

echo "==> Writing Dochi settings"
defaults write "$SETTINGS_DOMAIN" settings.claudeUIEnabled -bool YES || true
defaults write "$SETTINGS_DOMAIN" settings.claudeUIBaseURL -string "$BASE_URL" || true

APP_SUPPORT_DIR="$HOME/Library/Application Support/Dochi"
mkdir -p "$APP_SUPPORT_DIR"
echo -n "$TOKEN" > "$APP_SUPPORT_DIR/key_claude_ui_token"

echo "==> Done"
echo "Base URL: $BASE_URL"
echo "Token saved to: $APP_SUPPORT_DIR/key_claude_ui_token"
echo "You can now open Dochi and use the Coding tab / claude_ui.* tools."

