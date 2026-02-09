# Telegram Bot (MVP)

This document tracks the MVP for the in-app Telegram bot integration.

## Goals (MVP)

- Receive Telegram DMs while the macOS app is running
- Configure Bot Token in Settings; enable/disable toggle; getMe test
- Persist conversations locally; simple ACK reply to confirm connectivity

## Scope

- In-app `TelegramService` with long polling (`getUpdates`) and `sendMessage`
- Settings UI for token storage and enable toggle
- Conversation logging via `ConversationService` (userId = `tg:<chat_id>`)

## Test

- Settings → 메신저: 토큰 입력 → 연결 테스트( getMe )
- 토글을 켜면 수신 대기 시작; 개인 DM으로 메시지를 보내면 앱이 ACK로 응답하고 기록됨

## Next

- Supabase auth mapping: Telegram `user_id` ↔ workspace membership
- Route user text to Dochi pipeline (streaming edits via message update)
- Persist conversation history to Supabase
- Add peer messaging and tool execution
