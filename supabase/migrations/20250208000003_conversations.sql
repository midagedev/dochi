-- Cloud conversations table
create table if not exists conversations (
    id uuid primary key,
    workspace_id uuid not null references workspaces(id) on delete cascade,
    device_id uuid references devices(id) on delete set null,
    title text not null,
    messages jsonb not null default '[]',
    summary text,
    user_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz -- soft delete
);

-- RLS
alter table conversations enable row level security;

create policy "conversation_select" on conversations for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "conversation_insert" on conversations for insert with check (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "conversation_update" on conversations for update using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "conversation_delete" on conversations for delete using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Index for faster workspace queries
create index if not exists idx_conversations_workspace on conversations(workspace_id, updated_at desc);
