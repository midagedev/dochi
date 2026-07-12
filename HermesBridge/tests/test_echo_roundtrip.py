"""End-to-end check of the bridge protocol against the echo runtime.

Run: python -m pytest, or simply `python tests/test_echo_roundtrip.py`.
Requires only `websockets` (no Hermes).
"""

from __future__ import annotations

import asyncio
import json
import socket
import threading

import websockets

from dochi_hermes_bridge.runtime import EchoRuntime, HermesRuntime
from dochi_hermes_bridge.server import BridgeServer

TOKEN = "test-token"


class BlockingRuntime:
    persona = "test"

    def __init__(self) -> None:
        self.started = asyncio.Event()
        self.cancelled = asyncio.Event()

    async def respond(self, text, *, conversation_id, user, emit):
        self.started.set()
        try:
            await asyncio.Future()
        except asyncio.CancelledError:
            self.cancelled.set()
            raise


class InterruptibleHermesAgent:
    def __init__(self) -> None:
        self.started = threading.Event()
        self.interrupted = threading.Event()

    def run_conversation(self, text: str) -> dict[str, str]:
        self.started.set()
        if not self.interrupted.wait(timeout=2):
            raise RuntimeError("test worker was not interrupted")
        return {"final_response": "interrupted"}

    def interrupt(self, message: str | None = None) -> None:
        self.interrupted.set()


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


def test_server_rejects_non_loopback_bind() -> None:
    try:
        BridgeServer(EchoRuntime(), token=TOKEN, host="0.0.0.0")
        raise AssertionError("non-loopback bind unexpectedly accepted")
    except ValueError as error:
        assert "loopback" in str(error)


async def _disconnect_cancels_inflight() -> None:
    port = _available_port()
    runtime = BlockingRuntime()
    server = BridgeServer(runtime, token=TOKEN, port=port)
    serve_task = asyncio.create_task(server.serve_forever())
    await asyncio.sleep(0.3)

    try:
        ws = await websockets.connect(f"ws://127.0.0.1:{port}")
        await ws.send(json.dumps({"type": "hello", "token": TOKEN, "client": "dochi"}))
        ready = json.loads(await ws.recv())
        assert ready["type"] == "ready", ready
        await ws.send(
            json.dumps(
                {
                    "type": "user_message",
                    "correlation_id": "disconnect-me",
                    "conversation_id": "conv1",
                    "text": "오래 걸리는 요청",
                }
            )
        )
        await asyncio.wait_for(runtime.started.wait(), timeout=2)
        await ws.close()
        await asyncio.wait_for(runtime.cancelled.wait(), timeout=2)
        await asyncio.sleep(0)
        assert not server._inflight, server._inflight
    finally:
        serve_task.cancel()


def test_disconnect_cancels_inflight() -> None:
    asyncio.run(_disconnect_cancels_inflight())


async def _hermes_runtime_interrupts_worker() -> None:
    runtime = HermesRuntime(model="test")
    agent = InterruptibleHermesAgent()
    runtime._agent = agent

    async def ignore_emit(kind: str, **kwargs) -> None:
        return None

    task = asyncio.create_task(
        runtime.respond(
            "cancel me",
            conversation_id="test",
            user=None,
            emit=ignore_emit,
        )
    )
    started = await asyncio.to_thread(agent.started.wait, 1)
    assert started
    task.cancel()
    try:
        await task
        raise AssertionError("cancelled runtime task unexpectedly completed")
    except asyncio.CancelledError:
        pass
    assert agent.interrupted.is_set()


def test_hermes_runtime_interrupts_worker_on_cancellation() -> None:
    asyncio.run(_hermes_runtime_interrupts_worker())


async def _run_script_suite() -> None:
    await _run()
    await _disconnect_cancels_inflight()
    await _hermes_runtime_interrupts_worker()


if __name__ == "__main__":
    asyncio.run(_run_script_suite())
    print("OK: echo, disconnect cancellation, and worker interruption passed")
