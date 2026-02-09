# Telegram Bot (MVP)

This document tracks the MVP for the in-app Telegram bot integration.

## Goals (Enhanced MVP)

- Receive Telegram DMs while the macOS app is running
- Configure Bot Token in Settings; enable/disable toggle; getMe test
- Persist conversations locally
- Stream LLM replies back to Telegram by editing a placeholder message
- Execute tools during streaming and append progress snippets to Telegram
- Best-effort Supabase mapping: link Telegram user to the current workspace

## Scope

- In-app `TelegramService` with long polling (`getUpdates`) and `sendMessage`
- Settings UI for token storage and enable toggle
- Conversation logging via `ConversationService` (userId = `tg:<chat_id>`)

## Test

- Settings → 메신저: 토큰 입력 → 연결 테스트( getMe )
- 토글을 켜면 수신 대기 시작; 개인 DM으로 메시지를 보내면 앱이 스트리밍으로 응답하고 기록됨

## Next

- Refine Supabase mapping (multi-workspace selection and explicit binding UI)
- Cloud conversation sync enhancements (attachments, images)
- Peer routing to specific devices with status streamed to Telegram
