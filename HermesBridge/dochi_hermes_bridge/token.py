"""Shared-token management for the local bridge.

The bridge and the Dochi app must agree on a token. Resolution order:

1. $DOCHI_BRIDGE_TOKEN
2. ~/.hermes/dochi_bridge_token   (created with 0600 perms if missing)

The Dochi app reads the same file, so a first run "just works" with no manual
copy/paste. The token only guards a loopback socket; it exists to stop other
local processes from talking to your agent.
"""

from __future__ import annotations

import os
import secrets
from pathlib import Path

ENV_VAR = "DOCHI_BRIDGE_TOKEN"
TOKEN_PATH = Path.home() / ".hermes" / "dochi_bridge_token"


def resolve_token() -> str:
    env = os.environ.get(ENV_VAR, "").strip()
    if env:
        return env

    if TOKEN_PATH.exists():
        existing = TOKEN_PATH.read_text(encoding="utf-8").strip()
        if existing:
            return existing

    token = secrets.token_urlsafe(32)
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    TOKEN_PATH.write_text(token, encoding="utf-8")
    os.chmod(TOKEN_PATH, 0o600)
    return token
