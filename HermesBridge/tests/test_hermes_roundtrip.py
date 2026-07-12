"""Full-stack check: Dochi protocol -> BridgeServer -> real Hermes AIAgent -> model.

A tiny OpenAI-compatible mock stands in for the model so the test is fully local
and deterministic. It exercises the *real* Hermes conversation loop (hermes-agent
must be installed); if it isn't, the test skips.

Run: PYTHONPATH=. python tests/test_hermes_roundtrip.py
"""

from __future__ import annotations

import asyncio
import importlib.util
import json
import socket
import threading
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

import websockets

from dochi_hermes_bridge.runtime import HermesRuntime
from dochi_hermes_bridge.server import BridgeServer

HERMES_AVAILABLE = importlib.util.find_spec("run_agent") is not None
REPLY = "안녕하세요, 저는 도치예요."
TOKEN = "test-token"


def _available_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


class _MockModel(BaseHTTPRequestHandler):
    def log_message(self, *args):  # silence
        pass

    def do_GET(self):
        if self.path.endswith("/models"):
            body = json.dumps({"object": "list", "data": [{"id": "mock-model", "object": "model"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        cid = "chatcmpl-" + uuid.uuid4().hex[:8]

        def chunk(delta, finish=None):
            obj = {
                "id": cid, "object": "chat.completion.chunk", "model": "mock-model",
                "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
            }
            self.wfile.write(("data: " + json.dumps(obj) + "\n\n").encode())
            self.wfile.flush()

        chunk({"role": "assistant", "content": ""})
        for i in range(0, len(REPLY), 6):
            chunk({"content": REPLY[i:i + 6]})
        chunk({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


async def _run() -> None:
    model_port = _available_port()
    ws_port = _available_port()
    model_srv = HTTPServer(("127.0.0.1", model_port), _MockModel)
    threading.Thread(target=model_srv.serve_forever, daemon=True).start()

    runtime = HermesRuntime(
        model="mock-model", api_key="sk-test",
        base_url=f"http://127.0.0.1:{model_port}/v1", provider="openai",
    )
    server = BridgeServer(runtime, token=TOKEN, port=ws_port)
    serve_task = asyncio.create_task(server.serve_forever())
    await asyncio.sleep(0.4)

    try:
        async with websockets.connect(f"ws://127.0.0.1:{ws_port}") as ws:
            await ws.send(json.dumps({"type": "hello", "token": TOKEN, "client": "dochi"}))
            ready = json.loads(await ws.recv())
            assert ready["type"] == "ready", ready

            await ws.send(json.dumps({
                "type": "user_message", "correlation_id": "c1",
                "conversation_id": "conv1", "user": "tester", "text": "자기소개 해줘",
            }))

            deltas: list[str] = []
            done_text = None
            while True:
                frame = json.loads(await asyncio.wait_for(ws.recv(), timeout=60))
                if frame["type"] == "delta":
                    deltas.append(frame["text"])
                elif frame["type"] == "done":
                    done_text = frame["text"]
                    break
                elif frame["type"] == "error":
                    raise AssertionError(f"bridge error: {frame['message']}")

            joined = "".join(deltas)
            assert REPLY in joined, f"deltas missing reply: {joined!r}"
            assert done_text and REPLY in done_text, f"done text: {done_text!r}"
    finally:
        serve_task.cancel()
        model_srv.shutdown()


def test_hermes_roundtrip() -> None:
    if not HERMES_AVAILABLE:
        print("SKIP: hermes-agent not installed")
        return
    asyncio.run(_run())


if __name__ == "__main__":
    if not HERMES_AVAILABLE:
        print("SKIP: hermes-agent not installed (pip install hermes-agent)")
    else:
        asyncio.run(_run())
        print("OK: full-stack Dochi-protocol -> bridge -> real Hermes -> model round-trip passed")
