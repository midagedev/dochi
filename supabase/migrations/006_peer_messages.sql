-- Peer-to-peer messaging via Supabase Realtime relay
create table if not exists peer_messages (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references workspaces(id) on delete cascade,
    from_device_id uuid not null references devices(id) on delete cascade,
    to_device_id uuid references devices(id) on delete cascade, -- null = broadcast to all peers
    message_type text not null, -- 'ping', 'pong', 'queryForward', 'responseForward', 'capabilityRequest', 'capabilityResponse', 'notification'
    payload jsonb not null default '{}',
    created_at timestamptz not null default now(),
    read_at timestamptz -- null = unread
);

-- RLS
alter table peer_messages enable row level security;

-- Workspace members can read messages in their workspace
create policy "peer_message_select" on peer_messages for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Workspace members can insert messages
create policy "peer_message_insert" on peer_messages for insert with check (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Only the recipient device's owner can update (mark as read)
create policy "peer_message_update" on peer_messages for update using (
    to_device_id in (select id from devices where user_id = auth.uid())
    or to_device_id is null -- allow marking broadcasts as read
);

-- Workspace members can delete their messages
create policy "peer_message_delete" on peer_messages for delete using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Index for efficient queries
create index if not exists idx_peer_messages_to_device on peer_messages(to_device_id, created_at desc)
    where read_at is null;
create index if not exists idx_peer_messages_workspace on peer_messages(workspace_id, created_at desc);

-- Enable Realtime for instant delivery
alter publication supabase_realtime add table peer_messages;

-- Auto-cleanup: peer_messages 는 빈번한 ping/pong/capability 메시지로 인해 빠르게 증가할 수 있음.
-- 아래 pg_cron 설정으로 24시간 이상 된 메시지를 자동 삭제 (Supabase 대시보드 > Database > Extensions 에서 pg_cron 활성화 필요):
--
-- select cron.schedule(
--     'cleanup_peer_messages',
--     '0 * * * *',
--     $$delete from peer_messages where created_at < now() - interval '24 hours'$$
-- );
--
-- 또는 Supabase Edge Function + cron trigger 로 대체 가능.
