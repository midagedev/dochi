# Supabase Integration

## Auth & Session
- `AuthState = signedOut | signedIn(userId: UUID, email: String?)`.
- Apple Sign‑In or Email/Password.
- `restoreSession()` attempts rehydration on app start.

## Workspace Selection
- `selectedWorkspace: Workspace?` tracked in service; mirrored to settings `currentWorkspaceId` for local context.
- Methods: `createWorkspace`, `joinWorkspace(inviteCode)`, `leaveWorkspace`, `listWorkspaces`, `regenerateInviteCode`.

## Telegram Account Mapping
- Table: `telegram_accounts`
  - Fields: `telegram_user_id: int8`, `workspace_id: uuid`, `user_id: uuid`, `username?: text`, `updated_at: timestamptz`.
- Behavior:
  - Upsert mapping on first DM; update username changes.
  - Resolve workspace by most recently updated row.

## Leader Lock (Best‑effort)
- Table: `leader_locks`
  - Fields: `resource: text`, `workspace_id: uuid`, `holder_user_id: uuid`, `expires_at: timestamptz`.
- Semantics:
  - Acquire: insert if missing; if exists and expired or held by same user → update owner + `expires_at`.
  - Refresh: update `expires_at` for current holder.
  - Release: delete when current holder.
  - Failure mode: fail‑open (warnings logged; continue locally).
- Default TTL: 60s (caller can override).

## Open Items
- Full table DDL (constraints, indexes) to be captured.
- Realtime usage (if any) to be specified; current code suggests REST/RPC focus.
- Device registry/table contract (if applicable) to be added.
