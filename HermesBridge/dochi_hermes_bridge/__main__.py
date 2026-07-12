"""CLI entry point: `python -m dochi_hermes_bridge`.

Examples
--------
    # Development: no Hermes required, echoes input back through the pipeline.
    python -m dochi_hermes_bridge --echo

    # Production: drive the installed Hermes Agent.
    python -m dochi_hermes_bridge --port 8765
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os

from .runtime import EchoRuntime, HermesRuntime
from .server import BridgeServer
from .token import TOKEN_PATH, resolve_token


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="dochi-hermes-bridge")
    parser.add_argument("--host", default="127.0.0.1", help="bind host (loopback only)")
    parser.add_argument("--port", type=int, default=8765, help="bind port")
    parser.add_argument("--echo", action="store_true", help="run the dependency-free echo runtime")
    parser.add_argument("--model", default=os.environ.get("HERMES_MODEL"),
                        help="model id override; default defers to ~/.hermes/config.yaml (hermes setup)")
    parser.add_argument("--api-key", default=None,
                        help="model API key (falls back to OPENROUTER_API_KEY / OPENAI_API_KEY env)")
    parser.add_argument("--base-url", default=os.environ.get("HERMES_BASE_URL"),
                        help="OpenAI-compatible base URL (e.g. http://localhost:11434/v1 for Ollama)")
    parser.add_argument("--provider", default=os.environ.get("HERMES_PROVIDER"),
                        help="provider hint passed to Hermes")
    parser.add_argument("--user-name", default=os.environ.get("HERMES_USER_NAME"))
    parser.add_argument("--log-level", default="INFO")
    return parser.parse_args()


async def _amain(args: argparse.Namespace) -> None:
    if args.echo:
        runtime = EchoRuntime()
        logging.getLogger("dochi_hermes_bridge").info("running EchoRuntime (no Hermes)")
    else:
        api_key = args.api_key or os.environ.get("OPENROUTER_API_KEY") or os.environ.get("OPENAI_API_KEY")
        hermes = HermesRuntime(
            model=args.model,
            api_key=api_key,
            base_url=args.base_url,
            provider=args.provider,
            user_name=args.user_name,
        )
        await hermes.start()
        runtime = hermes

    token = resolve_token()
    logging.getLogger("dochi_hermes_bridge").info("token file: %s", TOKEN_PATH)
    server = BridgeServer(runtime, token=token, host=args.host, port=args.port)
    await server.serve_forever()


def main() -> None:
    args = _parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    try:
        asyncio.run(_amain(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
