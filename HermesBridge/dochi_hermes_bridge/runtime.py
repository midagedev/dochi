"""Hermes runtime seam.

The bridge server is agnostic about *how* a reply is produced. It talks to a
runtime: feed it the user's text, and it streams back events (text deltas, tool
start/end) and finally returns the full assistant text. The contract is:

    async def respond(text, *, conversation_id, user, emit) -> str

where `emit` streams events:
    await emit("delta", text="...")
    await emit("tool", name="web_search", phase="start", summary="...")
    await emit("tool", name="web_search", phase="end", is_error=False, summary="...")

Two implementations:

- `EchoRuntime`   — no Hermes required; streams the prompt back. Lets the whole
                    Dochi voice/avatar loop be exercised without a model.
- `HermesRuntime` — drives a real Nous Research Hermes Agent via
                    `run_agent.AIAgent` (`pip install hermes-agent`). Verified
                    against hermes-agent 0.15.x: AIAgent(...).run_conversation()
                    with stream_delta_callback / tool_start_callback /
                    tool_complete_callback.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Awaitable, Callable, Optional, Protocol

log = logging.getLogger("dochi_hermes_bridge.runtime")

EmitFn = Callable[..., Awaitable[None]]


class HermesRuntimeProtocol(Protocol):
    async def respond(self, text: str, *, conversation_id: str, user: Optional[str], emit: EmitFn) -> str: ...
    @property
    def persona(self) -> Optional[str]: ...


def _summarize(value: Any, limit: int = 120) -> str:
    text = value if isinstance(value, str) else repr(value)
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


class EchoRuntime:
    """Dependency-free runtime that streams the prompt back as the reply."""

    def __init__(self, persona: str = "도치 (echo)") -> None:
        self._persona = persona

    @property
    def persona(self) -> Optional[str]:
        return self._persona

    async def respond(self, text: str, *, conversation_id: str, user: Optional[str], emit: EmitFn) -> str:
        reply = f"(echo) {text}"
        for word in reply.split(" "):
            await emit("delta", text=word + " ")
            await asyncio.sleep(0.02)
        return reply.strip()


class HermesRuntime:
    """Adapter onto the real Hermes Agent (`run_agent.AIAgent`).

    One agent instance is built lazily and reused so Hermes' session memory
    persists across turns. Hermes' callbacks fire on the worker thread running
    the (blocking) conversation loop, so we marshal each one back onto the
    asyncio loop with ``run_coroutine_threadsafe``. Requests are serialized with
    a lock — fine for a single-user voice front-end, and it keeps the per-turn
    ``emit`` routing unambiguous.
    """

    def __init__(
        self,
        *,
        model: Optional[str] = None,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        provider: Optional[str] = None,
        user_name: Optional[str] = None,
    ) -> None:
        # None => defer to the model/provider configured in ~/.hermes/config.yaml
        # (e.g. via `hermes setup`). Only override when explicitly provided.
        self._model = model
        self._api_key = api_key
        self._base_url = base_url
        self._provider = provider
        self._user_name = user_name
        self._agent: Any = None
        self._persona: Optional[str] = None
        self._lock = asyncio.Lock()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._active_emit: Optional[EmitFn] = None

    @property
    def persona(self) -> Optional[str]:
        return self._persona

    async def start(self) -> None:
        if self._agent is not None:
            return
        self._agent = await asyncio.to_thread(self._build_agent)
        self._persona = self._user_name or getattr(self._agent, "user_name", None) or "도치"
        log.info("Hermes AIAgent ready (model=%s, persona=%s)", self._model, self._persona)

    def _build_agent(self) -> Any:
        try:
            from run_agent import AIAgent
        except ImportError as exc:  # pragma: no cover - environment dependent
            raise RuntimeError(
                "hermes-agent is not installed. `pip install hermes-agent`, or "
                "run the bridge with --echo for development."
            ) from exc

        def on_delta(text: Optional[str]) -> None:
            if text:  # Hermes sends None to mark boundaries
                self._schedule(self._emit_safe("delta", text=text))

        def on_tool_start(tool_id: Any, name: str, args: Any) -> None:
            self._schedule(self._emit_safe("tool", name=name, phase="start", summary=_summarize(args)))

        def on_tool_complete(tool_id: Any, name: str, args: Any, result: Any) -> None:
            self._schedule(self._emit_safe("tool", name=name, phase="end", is_error=False, summary=_summarize(result)))

        kwargs: dict[str, Any] = {
            "quiet_mode": True,
            "stream_delta_callback": on_delta,
            "tool_start_callback": on_tool_start,
            "tool_complete_callback": on_tool_complete,
        }

        explicit = any([self._model, self._api_key, self._base_url, self._provider])
        if explicit:
            # Operator-supplied target (e.g. --base-url for Ollama, or a test).
            if self._model:
                kwargs["model"] = self._model
            if self._api_key:
                kwargs["api_key"] = self._api_key
            if self._base_url:
                kwargs["base_url"] = self._base_url
            if self._provider:
                kwargs["provider"] = self._provider
        else:
            # Defer to ~/.hermes/config.yaml, resolving exactly like the Hermes
            # CLI does. This carries provider-specific details the bare AIAgent
            # constructor does NOT infer on its own — most importantly `api_mode`
            # (e.g. 'codex_responses' for ChatGPT Codex) and the credential pool.
            runtime = self._resolve_config_runtime()
            for src, dst in (("provider", "provider"), ("api_mode", "api_mode"),
                             ("base_url", "base_url"), ("api_key", "api_key"),
                             ("command", "acp_command")):
                value = runtime.get(src)
                if value is not None:
                    kwargs[dst] = value
            if runtime.get("args"):
                kwargs["acp_args"] = list(runtime["args"])
            if runtime.get("credential_pool") is not None:
                kwargs["credential_pool"] = runtime["credential_pool"]
            if runtime.get("model"):
                kwargs["model"] = runtime["model"]
            elif "model" not in kwargs:
                model = self._default_model_for(runtime.get("api_mode"))
                if model:
                    kwargs["model"] = model

        if self._user_name:
            kwargs["user_name"] = self._user_name
        return AIAgent(**kwargs)

    def _resolve_config_runtime(self) -> dict:
        """Resolve provider/credentials from ~/.hermes/config.yaml (CLI parity)."""
        try:
            from hermes_cli.runtime_provider import resolve_runtime_provider
            return resolve_runtime_provider()
        except Exception as exc:  # noqa: BLE001 - fall back to bare AIAgent defaults
            log.warning("resolve_runtime_provider failed (%s); using AIAgent defaults", exc)
            return {}

    @staticmethod
    def _default_model_for(api_mode: Optional[str]) -> Optional[str]:
        """Some providers (e.g. ChatGPT Codex) need an explicit model even when
        config.yaml omits one. Mirror the CLI's default selection."""
        if api_mode == "codex_responses":
            try:
                from hermes_cli.codex_models import get_codex_model_ids
                ids = get_codex_model_ids()
                if ids:
                    return ids[0]
            except Exception:  # noqa: BLE001
                pass
            return "gpt-5.5"
        return None

    def _schedule(self, coro: Awaitable[None]) -> None:
        if self._loop is not None:
            asyncio.run_coroutine_threadsafe(coro, self._loop)  # type: ignore[arg-type]

    async def _emit_safe(self, kind: str, **kwargs: Any) -> None:
        emit = self._active_emit
        if emit is not None:
            await emit(kind, **kwargs)

    async def respond(self, text: str, *, conversation_id: str, user: Optional[str], emit: EmitFn) -> str:
        if self._agent is None:
            await self.start()
        async with self._lock:
            self._loop = asyncio.get_running_loop()
            self._active_emit = emit
            worker = asyncio.create_task(
                asyncio.to_thread(self._agent.run_conversation, text)
            )
            try:
                # Shield the worker so cancellation of the WebSocket request
                # does not orphan an untracked thread that continues mutating
                # the shared Hermes session.
                result = await asyncio.shield(worker)
            except asyncio.CancelledError:
                interrupt = getattr(self._agent, "interrupt", None)
                if callable(interrupt):
                    try:
                        await asyncio.to_thread(
                            interrupt,
                            "Dochi bridge request cancelled",
                        )
                    except Exception as exc:  # noqa: BLE001 - preserve cancellation
                        log.warning("failed to interrupt Hermes worker: %s", exc)
                # Keep the serialization lock until the worker acknowledges
                # the interrupt. This prevents a new turn from racing the old
                # thread against the same AIAgent instance.
                try:
                    await asyncio.shield(worker)
                except Exception:  # noqa: BLE001 - cancellation remains authoritative
                    pass
                raise
            finally:
                self._active_emit = None
        if isinstance(result, dict):
            return result.get("final_response", "") or ""
        return str(result) if result is not None else ""
