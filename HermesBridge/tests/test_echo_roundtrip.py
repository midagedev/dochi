"""End-to-end check of the bridge protocol against the echo runtime.

Run: python -m pytest, or simply `python tests/test_echo_roundtrip.py`.
Requires only `websockets` (no Hermes).
"""

from __future__ import annotations

import asyncio
import json
import socket

import websockets

from dochi_hermes_bridge.runtime import EchoRuntime
from dochi_hermes_bridge.server import BridgeServer

TOKEN = "test-token"


def _available_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


async def _run() -> None:
    port = _available_port()
    server = BridgeServer(EchoRuntime(), token=TOKEN, port=port)
    serve_task = asyncio.create_task(server.serve_forever())
    await asyncio.sleep(0.3)  # let the listener bind

    try:
        async with websockets.connect(f"ws://127.0.0.1:{port}") as ws:
            # Reject bad token.
            await ws.send(json.dumps({"type": "hello", "token": "wrong"}))
            err = json.loads(await ws.recv())
            assert err["type"] == "error", err

        async with websockets.connect(f"ws://127.0.0.1:{port}") as ws:
            await ws.send(json.dumps({"type": "hello", "token": TOKEN, "client": "dochi"}))
            ready = json.loads(await ws.recv())
            assert ready["type"] == "ready", ready

            await ws.send(
                json.dumps(
                    {
                        "type": "user_message",
                        "correlation_id": "c1",
                        "conversation_id": "conv1",
                        "user": "tester",
                        "text": "안녕 도치",
                    }
                )
            )

            deltas: list[str] = []
            while True:
                frame = json.loads(await ws.recv())
                assert frame["correlation_id"] == "c1", frame
                if frame["type"] == "delta":
                    deltas.append(frame["text"])
                elif frame["type"] == "done":
                    assert frame["text"] == "(echo) 안녕 도치", frame
                    break
                else:
                    raise AssertionError(f"unexpected frame: {frame}")

            joined = "".join(deltas).strip()
            assert joined == "(echo) 안녕 도치", joined
    finally:
        serve_task.cancel()


def test_echo_roundtrip() -> None:
    asyncio.run(_run())


if __name__ == "__main__":
    asyncio.run(_run())
    print("OK: echo round-trip passed")
