#!/bin/bash
# Dochi Smoke Test
# Usage: ./scripts/smoke_test.sh
#
# Builds the app, launches it, waits for smoke log, then validates key state.
# Exit code 0 = all checks pass, 1 = failure.

set -euo pipefail

SMOKE_LOG="/tmp/dochi_smoke.log"
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app -maxdepth 0 2>/dev/null | head -1)

echo "=== Dochi Smoke Test ==="

# Step 1: Build
echo "[1/4] Building..."
xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug build -quiet 2>&1
echo "  Build OK"

# Step 2: Kill existing & clear old log
pkill -x Dochi 2>/dev/null || true
sleep 1
rm -f "$SMOKE_LOG"

# Step 3: Launch and wait for smoke log
echo "[2/4] Launching app..."
if [ -z "${APP_PATH:-}" ]; then
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app -maxdepth 0 2>/dev/null | head -1)
fi
open "$APP_PATH"

echo "[3/4] Waiting for smoke log..."
for i in $(seq 1 15); do
    if [ -f "$SMOKE_LOG" ]; then
        break
    fi
    sleep 1
done

if [ ! -f "$SMOKE_LOG" ]; then
    echo "  FAIL: Smoke log not created after 15 seconds"
    pkill -x Dochi 2>/dev/null || true
    exit 1
fi

echo "  Smoke log found"
echo "---"
cat "$SMOKE_LOG"
echo "---"

# Step 4: Validate
echo "[4/4] Validating..."
FAILED=0

check() {
    local key="$1"
    local expected="$2"
    local actual
    actual=$(grep "^${key}=" "$SMOKE_LOG" | cut -d= -f2-)
    if [ "$expected" = "NOT_nil" ]; then
        if [ "$actual" = "nil" ] || [ -z "$actual" ]; then
            echo "  FAIL: $key expected non-nil, got '$actual'"
            FAILED=1
        else
            echo "  OK: $key=$actual"
        fi
    elif [ "$expected" = "GT_0" ]; then
        if [ "$actual" -gt 0 ] 2>/dev/null; then
            echo "  OK: $key=$actual (> 0)"
        else
            echo "  FAIL: $key expected > 0, got '$actual'"
            FAILED=1
        fi
    else
        if [ "$actual" = "$expected" ]; then
            echo "  OK: $key=$actual"
        else
            echo "  FAIL: $key expected '$expected', got '$actual'"
            FAILED=1
        fi
    fi
}

check "status" "ok"
check "profile_count" "GT_0"
check "current_user_id" "NOT_nil"
check "current_user_name" "NOT_nil"

# Cleanup
pkill -x Dochi 2>/dev/null || true

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "=== ALL CHECKS PASSED ==="
    exit 0
else
    echo ""
    echo "=== SOME CHECKS FAILED ==="
    exit 1
fi
