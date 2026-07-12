"""Wire protocol shared between the Dochi macOS app and the bridge server.

All frames are JSON objects sent as WebSocket *text* messages. The schema is
intentionally small and stable so the Swift `HermesAgentBridge` and this Python
adapter can evolve independently.

Client (Dochi) -> Server (bridge)
---------------------------------
- hello        : {"type":"hello","token":str,"client":"dochi","version":str}
- user_message : {"type":"user_message","correlation_id":str,
                  "conversation_id":str,"user":str|None,"text":str}
- cancel       : {"type":"cancel","correlation_id":str}
- ping         : {"type":"ping"}

Server (bridge) -> Client (Dochi)
---------------------------------
- ready     : {"type":"ready","persona":str|None,"session":str|None}
- delta     : {"type":"delta","correlation_id":str,"text":str}
- tool      : {"type":"tool","correlation_id":str,"name":str,
               "phase":"start"|"end","is_error":bool,"summary":str|None}
- done      : {"type":"done","correlation_id":str,
               "message_id":str|None,"text":str}
- error     : {"type":"error","correlation_id":str|None,"message":str}
- proactive : {"type":"proactive","text":str}      # server-initiated, no correlation
- pong      : {"type":"pong"}
"""

from __future__ import annotations

from typing import Any, Optional

PROTOCOL_VERSION = "1"


# -- Server -> Client builders -------------------------------------------------

def ready(persona: Optional[str], session: Optional[str]) -> dict[str, Any]:
    return {"type": "ready", "persona": persona, "session": session}


def delta(correlation_id: str, text: str) -> dict[str, Any]:
    return {"type": "delta", "correlation_id": correlation_id, "text": text}


def tool(
    correlation_id: str,
    name: str,
    phase: str,
    *,
    is_error: bool = False,
    summary: Optional[str] = None,
) -> dict[str, Any]:
    return {
        "type": "tool",
        "correlation_id": correlation_id,
        "name": name,
        "phase": phase,
        "is_error": is_error,
        "summary": summary,
    }


def done(correlation_id: str, text: str, message_id: Optional[str] = None) -> dict[str, Any]:
    return {
        "type": "done",
        "correlation_id": correlation_id,
        "message_id": message_id,
        "text": text,
    }


def error(message: str, correlation_id: Optional[str] = None) -> dict[str, Any]:
    return {"type": "error", "correlation_id": correlation_id, "message": message}


def proactive(text: str) -> dict[str, Any]:
    return {"type": "proactive", "text": text}


def pong() -> dict[str, Any]:
    return {"type": "pong"}
