-- Dochi Cloud Schema
-- Matches current Swift codebase models

-- ============================================================
-- 1. Workspaces
-- ============================================================
-- Swift model: Workspace (id, name, inviteCode, ownerId, createdAt)

create table if not exists workspaces (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    invite_code text unique,
    owner_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

-- ============================================================
-- 2. Workspace Members
-- ============================================================
-- Swift model: WorkspaceMember (id, workspaceId, userId, role, joinedAt)

create table if not exists workspace_members (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references workspaces(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null default 'member' check (role in ('owner', 'member')),
    joined_at timestamptz not null default now(),
    unique(workspace_id, user_id)
);

-- ============================================================
-- 3. Devices
-- ============================================================
-- Swift model: Device (id, userId, name, platform, lastHeartbeat, workspaceIds)

create table if not exists devices (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    platform text not null default 'macos',
    last_heartbeat timestamptz not null default now(),
    workspace_ids uuid[] not null default '{}',
    created_at timestamptz not null default now()
);

-- ============================================================
-- 4. Conversations
-- ============================================================
-- Swift model: Conversation (id, title, messages, createdAt, updatedAt, userId, summary)

create table if not exists conversations (
    id uuid primary key,
    workspace_id uuid references workspaces(id) on delete cascade,
    title text not null default '새 대화',
    messages jsonb not null default '[]',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    user_id text,
    summary text
);

-- ============================================================
-- 5. Profiles
-- ============================================================
-- Swift model: UserProfile (id, name, aliases, description, createdAt)

create table if not exists profiles (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid references workspaces(id) on delete cascade,
    name text not null,
    aliases text[] not null default '{}',
    description text not null default '',
    created_at timestamptz not null default now()
);

-- ============================================================
-- 6. Context History (sync key-value store)
-- ============================================================
-- Used by SupabaseService.syncContext() / syncConversations()

create table if not exists context_history (
    user_id uuid not null references auth.users(id) on delete cascade,
    key text not null,
    value text,
    updated_at text,
    primary key (user_id, key)
);

-- ============================================================
-- 7. Leader Locks
-- ============================================================
-- Swift model: LeaderLock (resource, workspaceId, holderUserId, expiresAt)

create table if not exists leader_locks (
    resource text not null,
    workspace_id uuid not null references workspaces(id) on delete cascade,
    holder_user_id uuid not null references auth.users(id) on delete cascade,
    expires_at timestamptz not null,
    primary key (workspace_id, resource)
);

-- ============================================================
-- Indexes
-- ============================================================

create index if not exists idx_conversations_workspace on conversations(workspace_id, updated_at desc);
create index if not exists idx_devices_user on devices(user_id);
create index if not exists idx_leader_locks_ws_resource on leader_locks(workspace_id, resource);

-- ============================================================
-- Row Level Security
-- ============================================================

alter table workspaces enable row level security;
alter table workspace_members enable row level security;
alter table devices enable row level security;
alter table conversations enable row level security;
alter table profiles enable row level security;
alter table context_history enable row level security;
alter table leader_locks enable row level security;

-- Workspaces: owner or member can read
create policy "workspace_select" on workspaces for select using (
    owner_id = auth.uid()
    or id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "workspace_insert" on workspaces for insert with check (
    owner_id = auth.uid()
);

create policy "workspace_update" on workspaces for update using (
    owner_id = auth.uid()
);

create policy "workspace_delete" on workspaces for delete using (
    owner_id = auth.uid()
);

-- Workspace Members: no self-reference recursion
create policy "member_select" on workspace_members for select using (
    user_id = auth.uid()
);

create policy "member_insert" on workspace_members for insert with check (
    user_id = auth.uid()
);

create policy "member_delete" on workspace_members for delete using (
    user_id = auth.uid()
);

-- Devices: user manages own devices
create policy "device_select" on devices for select using (
    user_id = auth.uid()
);

create policy "device_insert" on devices for insert with check (
    user_id = auth.uid()
);

create policy "device_update" on devices for update using (
    user_id = auth.uid()
);

create policy "device_delete" on devices for delete using (
    user_id = auth.uid()
);

-- Conversations: workspace members can access
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

-- Profiles: workspace members can manage
create policy "profile_select" on profiles for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "profile_insert" on profiles for insert with check (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "profile_update" on profiles for update using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "profile_delete" on profiles for delete using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Context History: user owns their own data
create policy "context_select" on context_history for select using (
    user_id = auth.uid()
);

create policy "context_insert" on context_history for insert with check (
    user_id = auth.uid()
);

create policy "context_update" on context_history for update using (
    user_id = auth.uid()
);

-- Leader Locks
create policy "locks_select" on leader_locks for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "locks_insert" on leader_locks for insert with check (
    holder_user_id = auth.uid()
    and workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "locks_update" on leader_locks for update using (
    (holder_user_id = auth.uid())
    or (expires_at <= now() and workspace_id in (select workspace_id from workspace_members where user_id = auth.uid()))
);

create policy "locks_delete" on leader_locks for delete using (
    holder_user_id = auth.uid()
);

-- ============================================================
-- Helper Function: join workspace by invite code
-- ============================================================

create or replace function join_workspace_by_invite(code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    ws_id uuid;
    caller_id uuid;
begin
    caller_id := auth.uid();
    if caller_id is null then
        raise exception 'Not authenticated';
    end if;

    select id into ws_id from workspaces where invite_code = code;
    if ws_id is null then
        raise exception 'Invalid invite code';
    end if;

    insert into workspace_members (workspace_id, user_id, role)
    values (ws_id, caller_id, 'member')
    on conflict (workspace_id, user_id) do nothing;

    return ws_id;
end;
$$;

-- ============================================================
-- Realtime
-- ============================================================

alter publication supabase_realtime add table conversations;
alter publication supabase_realtime add table devices;
