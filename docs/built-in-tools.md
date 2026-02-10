# Built-in Tools Guide

This guide documents Dochi’s built-in tools: what each tool does, its input schema, and quick examples you can copy into tool calls. Tools follow MCP-style schemas and are exposed to the LLM via `BuiltInToolService`.

Note: Only a baseline set is exposed by default to reduce token usage. Use the registry tools to enable additional tools per session, optionally with a TTL.

## Availability and Registry

- Baseline tools always exposed: `tools.list`, `tools.enable`, Reminders (`create_reminder`, `list_reminders`, `complete_reminder`), Alarm (`set_alarm`, `list_alarms`, `cancel_alarm`), Memory/Profile basics (`save_memory`, `update_memory`, `set_current_user`), Utility (`web_search`, `print_image`, `generate_image`).
- Conditional exposure:
  - `web_search` requires Tavily API key.
  - `generate_image` requires fal.ai API key.
  - Settings/Agent/AgentEditor/Context/ProfileAdmin need settings/context services present.
  - Workspace tools need Supabase configured and signed-in.
  - Telegram tools need TelegramService wired and a token.
- Registry control: enable additional tools by name or category.

Examples:

```json
{"tool_name":"tools.list","arguments":{}}
```

```json
{"tool_name":"tools.enable_categories","arguments":{"categories":["agent","agent_edit","settings","workspace","telegram","context","profile_admin"]}}
```

```json
{"tool_name":"tools.enable","arguments":{"names":["agent.create","agent.set_active","agent.persona_update"]}}
```

```json
{"tool_name":"tools.enable_ttl","arguments":{"minutes":20}}
```

```json
{"tool_name":"tools.reset","arguments":{}}
```

## Settings

- `settings.set` { key, value<string> } — Updates an app setting or API key.
- `settings.get` { key } — Returns current value (API keys are masked).
- `settings.list` {} — Lists supported keys and current values.
- `settings.mcp_add_server` { name, command:url, arguments?, environment?, is_enabled? }
- `settings.mcp_update_server` { id:uuid, name?, command?, arguments?, environment?, is_enabled? }
- `settings.mcp_remove_server` { id:uuid }

Keys include: `wakeWordEnabled`, `wakeWord`, `llmProvider`, `llmModel`, `supertonicVoice`, `ttsSpeed`, `ttsDiffusionSteps`, `chatFontSize`, `sttSilenceTimeout`, `contextAutoCompress`, `contextMaxSize`, `activeAgentName`, `telegramEnabled`, `defaultUserId`, and API keys `openaiApiKey`, `anthropicApiKey`, `zaiApiKey`, `tavilyApiKey`, `falaiApiKey`, `telegramBotToken`.

Examples:

```json
{"tool_name":"settings.set","arguments":{"key":"llmProvider","value":"anthropic"}}
```

```json
{"tool_name":"settings.set","arguments":{"key":"llmModel","value":"claude-3-5-sonnet-20241022"}}
```

```json
{"tool_name":"settings.set","arguments":{"key":"telegramEnabled","value":"true"}}
```

## Agent

- `agent.create` { name, wake_word?, description? } — Workspace-aware if current workspace is set.
- `agent.list` {} — Lists agents (workspace-aware).
- `agent.set_active` { name } — Sets `AppSettings.activeAgentName` after validating existence.

Examples:

```json
{"tool_name":"agent.create","arguments":{"name":"여행도치","wake_word":"여행도치야","description":"여행 일정/맛집 전문가"}}
```

```json
{"tool_name":"agent.set_active","arguments":{"name":"여행도치"}}
```

## Agent Editor

Persona:
- `agent.persona_get` { name? }
- `agent.persona_search` { query, name? }
- `agent.persona_update` { mode:"replace|append", content, name? }
- `agent.persona_replace` { find, replace, name?, preview?, confirm? }
- `agent.persona_delete_lines` { contains, name?, preview?, confirm? }

Memory:
- `agent.memory_get` { name? }
- `agent.memory_append` { content, name? }
- `agent.memory_replace` { content, name? }
- `agent.memory_update` { find, replace, name? } — replace empty string deletes the line.

Config:
- `agent.config_get` { name? }
- `agent.config_update` { wake_word?, description?, name? }

Guardrails: For bulk modifications (`persona_replace`, `persona_delete_lines`), use `preview:true` to see impact; if matches > 5 and `confirm:true` is not provided, the call is rejected.

## Context

- `context.update_base_system_prompt` { mode:"replace|append", content } — Edits `system_prompt.md`.

## Profile (identify)

- `set_current_user` { name } — Identifies current user by name/alias; creates a new profile if needed.

## Profile Admin

- `profile.create` { name, aliases?, description? }
- `profile.add_alias` { name, alias }
- `profile.rename` { from, to }
- `profile.merge` { source, target, merge_memory:"append|skip|replace" }

Merges move personal memory (`memory/{userId}.md`) and re-map conversations’ `userId` from source to target.

## Workspace (Supabase)

- `workspace.create` { name }
- `workspace.join_by_invite` { invite_code }
- `workspace.list` {}
- `workspace.switch` { id:uuid }
- `workspace.regenerate_invite_code` { id:uuid }

## Memory

- `save_memory` { content, scope:"family|personal" }
- `update_memory` { old_content, new_content, scope:"family|personal" }

Notes:
- For `personal`, identify the user first via `set_current_user`.
- Line-oriented: memories are stored as `- ...` entries.

## Reminders (Apple Reminders)

- `create_reminder` { title, due_date?, notes?, list_name? }
- `list_reminders` { list_name?, show_completed? }
- `complete_reminder` { title }

Date format: ISO 8601 (`2026-02-07T15:00:00`) preferred; several common formats are accepted.

## Alarm (Voice TTS)

- `set_alarm` { label, fire_date?, delay_seconds? } — one of time specs required.
- `list_alarms` {}
- `cancel_alarm` { label }

## Web Search (Tavily)

- `web_search` { query } — requires Tavily API key in settings.

## Image Generation (fal.ai)

- `generate_image` { prompt, image_size? } — requires fal.ai API key.
  - Sizes: `square_hd`, `square`, `landscape_4_3`, `landscape_16_9`, `portrait_4_3`, `portrait_16_9`.
  - Returns a markdown image linking to a local `file://` path.

## Image Printing

- `print_image` { image_path:file-url } — prints to default printer (A4, aspect-fit).

## Telegram

- `telegram.enable` { enabled:boolean, token? }
- `telegram.set_token` { token }
- `telegram.get_me` {}
- `telegram.send_message` { chat_id:int, text }

Tips:
- When enabling, if a token is provided it’s saved first; otherwise the stored token is used.
- `get_me` validates the token and returns bot username.

