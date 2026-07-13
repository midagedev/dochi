"""Local WebSocket server bridging the Dochi macOS app to a Hermes runtime.

Runs on 127.0.0.1 only. A shared token (see `token.py`) authenticates the
single trusted local client. Each `user_message` frame is dispatched to the
`HermesRuntime`, whose streamed events are relayed back to Dochi tagged with the
request's `correlation_id`.
"""

from __future__ import annotations

import asyncio
import ipaddress
import json
import logging
from typing import Any, Optional

import websockets
from websockets.asyncio.server import ServerConnection

from . import protocol
from .runtime import HermesRuntimeProtocol

log = logging.getLogger("dochi_hermes_bridge.server")


def is_loopback_host(host: str) -> bool:
    normalized = host.strip().lower().strip("[]")
    if normalized == "localhost" or normalized.endswith(".localhost"):
        return True
    try:
        return ipaddress.ip_address(normalized).is_loopback
    except ValueError:
        return False


class BridgeServer:
    def __init__(
        self,
        runtime: HermesRuntimeProtocol,
        *,
        token: str,
        host: str = "127.0.0.1",
        port: int = 8765,
    ) -> None:
        if not is_loopback_host(host):
            raise ValueError(
                "BridgeServer only binds to loopback. Use a TLS reverse proxy "
                "for remote access."
            )
        self._runtime = runtime
        self._token = token
        self._host = host
        self._port = port
        # correlation_id -> (owning socket, Task). Ownership prevents one
        # client from cancelling another client's request and lets disconnect
        # reliably tear down every request started by that socket.
        self._inflight: dict[
            str, tuple[ServerConnection, asyncio.Task[None]]
        ] = {}

    async def serve_forever(self) -> None:
        log.info("Dochi-Hermes bridge listening on ws://%s:%d", self._host, self._port)
        async with websockets.serve(
            self._handle_client,
            self._host,
            self._port,
            ping_interval=20,
            ping_timeout=20,
            max_size=8 * 1024 * 1024,
        ):
            await asyncio.Future()  # run until cancelled

    async def _handle_client(self, ws: ServerConnection) -> None:
        peer = ws.remote_address
        log.info("client connected: %s", peer)
        authed = False
        try:
            async for raw in ws:
                try:
                    frame = json.loads(raw)
                except json.JSONDecodeError:
                    await self._send(ws, protocol.error("invalid JSON frame"))
                    continue

                ftype = frame.get("type")

                if not authed:
                    if ftype != "hello":
                        await self._send(ws, protocol.error("expected hello frame"))
                        await ws.close(code=4401, reason="unauthenticated")
                        return
                    if frame.get("token") != self._token:
                        await self._send(ws, protocol.error("invalid token"))
                        await ws.close(code=4401, reason="invalid token")
                        return
                    authed = True
                    await self._ensure_runtime_started()
                    await self._send(
                        ws,
                        protocol.ready(persona=self._runtime.persona, session=None),
                    )
                    continue

                await self._dispatch(ws, ftype, frame)
        except websockets.ConnectionClosed:
            pass
        finally:
            await self._cancel_client_requests(ws)
            log.info("client disconnected: %s", peer)

    async def _ensure_runtime_started(self) -> None:
        """Warm the runtime (build the Hermes agent, populate persona) on connect
        so the first reply isn't slowed by lazy construction. Idempotent."""
        start = getattr(self._runtime, "start", None)
        if start is None:
            return
        try:
            await start()
        except Exception as exc:  # noqa: BLE001 - still allow the session
            log.warning("runtime warm-up failed: %s", exc)

    async def _dispatch(self, ws: ServerConnection, ftype: Optional[str], frame: dict[str, Any]) -> None:
        if ftype == "ping":
            await self._send(ws, protocol.pong())
        elif ftype == "user_message":
            await self._start_message(ws, frame)
        elif ftype == "cancel":
            self._cancel(ws, frame.get("correlation_id"))
        else:
            await self._send(ws, protocol.error(f"unknown frame type: {ftype}"))

    async def _start_message(self, ws: ServerConnection, frame: dict[str, Any]) -> None:
        correlation_id = frame.get("correlation_id")
        text = (frame.get("text") or "").strip()
        if not correlation_id:
            await self._send(ws, protocol.error("missing correlation_id"))
            return
        if not text:
            await self._send(ws, protocol.error("empty text", correlation_id))
            return
        if correlation_id in self._inflight:
            await self._send(ws, protocol.error("duplicate correlation_id", correlation_id))
            return

        task = asyncio.create_task(self._run_message(ws, correlation_id, frame, text))
        self._inflight[correlation_id] = (ws, task)
        task.add_done_callback(
            lambda completed: self._forget_if_current(correlation_id, completed)
        )

    async def _run_message(
        self,
        ws: ServerConnection,
        correlation_id: str,
        frame: dict[str, Any],
        text: str,
    ) -> None:
        async def emit(kind: str, **kwargs: Any) -> None:
            if kind == "delta":
                await self._send(ws, protocol.delta(correlation_id, kwargs["text"]))
            elif kind == "tool":
                await self._send(
                    ws,
                    protocol.tool(
                        correlation_id,
                        name=kwargs.get("name", "tool"),
                        phase=kwargs.get("phase", "start"),
                        is_error=kwargs.get("is_error", False),
                        summary=kwargs.get("summary"),
                    ),
                )

        try:
            full = await self._runtime.respond(
                text,
                conversation_id=frame.get("conversation_id", ""),
                user=frame.get("user"),
                emit=emit,
            )
            await self._send(ws, protocol.done(correlation_id, text=full or ""))
        except asyncio.CancelledError:
            await self._send(ws, protocol.error("cancelled", correlation_id))
            raise
        except Exception as exc:  # noqa: BLE001 - surface any runtime failure
            log.exception("runtime error for %s", correlation_id)
            await self._send(ws, protocol.error(str(exc), correlation_id))

    def _cancel(
        self,
        ws: ServerConnection,
        correlation_id: Optional[str],
    ) -> None:
        if not correlation_id:
            return
        entry = self._inflight.get(correlation_id)
        if entry is None:
            return
        owner, task = entry
        if owner is ws and not task.done():
            task.cancel()

    def _forget_if_current(
        self,
        correlation_id: str,
        completed: asyncio.Task[None],
    ) -> None:
        entry = self._inflight.get(correlation_id)
        if entry is not None and entry[1] is completed:
            self._inflight.pop(correlation_id, None)

    async def _cancel_client_requests(self, ws: ServerConnection) -> None:
        owned = [
            task
            for owner, task in self._inflight.values()
            if owner is ws and not task.done()
        ]
        for task in owned:
            task.cancel()
        if owned:
            await asyncio.gather(*owned, return_exceptions=True)

    async def _send(self, ws: ServerConnection, payload: dict[str, Any]) -> None:
        try:
            await ws.send(json.dumps(payload, ensure_ascii=False))
        except websockets.ConnectionClosed:
            pass
