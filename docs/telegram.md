# Telegram Bot (MVP)

This document tracks the MVP for the multi-interface Telegram bot.

## Goals (MVP)

- DM conversation entrypoint to Dochi (echo prototype initially)
- Same workspace context (wire-up in subsequent PRs)
- No tools or peer routing yet (future phases)

## Scope

- Swift CLI target `TelegramBot` compiled via SwiftPM
- Environment-based configuration:
  - `TELEGRAM_BOT_TOKEN`: Telegram Bot API token
- Commands:
  - `--check`: print basic configuration sanity
- Implementation plan:
  1. `getMe` call to verify bot identity
  2. Long polling `getUpdates` with in-memory offset
  3. Echo DM back to sender as functional MVP

## Run

```
export TELEGRAM_BOT_TOKEN=xxxxxxxx:yyyyyyyy
swift run TelegramBot --check
```

## Next

- Supabase auth mapping: Telegram `user_id` ↔ workspace membership
- Route user text to Dochi pipeline (streaming edits via message update)
- Persist conversation history to Supabase
- Add peer messaging and tool execution

