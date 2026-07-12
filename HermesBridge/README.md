# Dochi ↔ Hermes Agent Bridge

Dochi is the **voice + 3D-character front-end**. The **brain** (reasoning,
memory, skills, tools) is [Nous Research's Hermes Agent](https://github.com/NousResearch/hermes-agent).
This package is the glue: a tiny loopback WebSocket gateway that lets the Dochi
macOS app speak to a Hermes backend as if it were just another chat channel
(like Hermes' Telegram/Discord adapters).

```
┌────────────────────────┐   ws://127.0.0.1:8765   ┌───────────────────────┐
│ Dochi.app (macOS)      │  ───────────────────▶   │ dochi-hermes-bridge   │
│  Korean STT            │   user_message          │  (this package)       │
│  Supertonic/Google TTS │  ◀───────────────────   │   ▼                   │
│  VRM 3D avatar + lips   │   delta / tool / done   │  Hermes Agent core    │
└────────────────────────┘                         └───────────────────────┘
```

Dochi owns everything the user *sees and hears*: Korean speech recognition,
local/cloud TTS, the VRM avatar and its lip-sync. Hermes owns everything the
agent *thinks and does*: the LLM loop, persistent memory, the skills system and
its 40+ tools. The bridge only moves text and status events between them.

## Install

```bash
cd HermesBridge
python -m venv .venv && source .venv/bin/activate
pip install -e .                # bridge only (echo mode works now)
pip install -e ".[hermes]"      # also pull in hermes-agent for production
```

## Run

```bash
# Development — no Hermes needed. Echoes your speech back through TTS + avatar,
# so you can verify the whole voice loop end to end.
python -m dochi_hermes_bridge --echo

# Production — drive the installed Hermes Agent.
python -m dochi_hermes_bridge --port 8765
```

On first run the bridge writes a shared token to `~/.hermes/dochi_bridge_token`
(mode `0600`). Dochi reads the same file, so no copy/paste is required. Override
with `DOCHI_BRIDGE_TOKEN` if you prefer.

## Giving Hermes a model

Hermes is the brain, but it still needs an LLM provider. Configure one **once**
with Hermes' own setup, then the bridge just works — no flags needed:

```bash
hermes setup          # first-time, interactive (e.g. ChatGPT Codex login)
hermes model          # pick/switch provider+model later
python -m dochi_hermes_bridge   # auto-resolves your configured provider
```

The bridge resolves the configured provider exactly like the Hermes CLI
(`hermes_cli.runtime_provider.resolve_runtime_provider`), so it carries the
provider-specific bits a bare `AIAgent()` does **not** infer — notably
`api_mode` (e.g. `codex_responses` for ChatGPT Codex) and the credential pool,
plus the right default model (e.g. `gpt-5.5` for Codex). Verified live against a
ChatGPT Codex account end to end.

To override instead — point the bridge straight at a provider without Hermes config:

```bash
# OpenRouter / OpenAI (set the key in your environment)
export OPENROUTER_API_KEY=sk-...
python -m dochi_hermes_bridge --model anthropic/claude-sonnet-4.6

# Any OpenAI-compatible local server (e.g. Ollama, LM Studio) — fully offline
python -m dochi_hermes_bridge \
  --base-url http://127.0.0.1:11434/v1 --provider openai --model qwen2.5 --api-key x
```

`runtime.py:HermesRuntime` drives `run_agent.AIAgent(...).run_conversation(...)`
and maps Hermes' `stream_delta_callback` / `tool_start_callback` /
`tool_complete_callback` onto the bridge's `delta` / `tool` events. Verified
against **hermes-agent 0.15.2** (Nous Research). If no provider is configured you
get a clear `No LLM provider configured. Run \`hermes model\`…` error.

## Protocol

JSON frames over a WebSocket text channel — see `protocol.py` for the complete,
stable schema. Summary:

| Direction | Frame | Purpose |
|-----------|-------|---------|
| Dochi → bridge | `hello` | authenticate with the shared token |
| Dochi → bridge | `user_message` | a transcribed utterance (`correlation_id`, `text`) |
| Dochi → bridge | `cancel` | interrupt an in-flight reply |
| bridge → Dochi | `ready` | handshake accepted (+ persona) |
| bridge → Dochi | `delta` | streamed assistant text (drives TTS sentence-by-sentence) |
| bridge → Dochi | `tool` | tool start/end (drives the avatar's "thinking" state) |
| bridge → Dochi | `done` | reply complete (full text) |
| bridge → Dochi | `proactive` | server-initiated message (Hermes nudges) |

## Tests

```bash
PYTHONPATH=. python tests/test_echo_roundtrip.py      # protocol round-trip (no Hermes)
PYTHONPATH=. python tests/test_hermes_roundtrip.py    # full stack: bridge → real Hermes → model
```

`test_hermes_roundtrip` stands up a tiny OpenAI-compatible mock model so it runs
the **real** Hermes conversation loop locally with no API key. It skips
automatically if `hermes-agent` isn't installed.
