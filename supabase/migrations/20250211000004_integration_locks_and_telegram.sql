-- Leader locks for integration single-consumer semantics
create table if not exists leader_locks (
    resource text not null,
    workspace_id uuid not null references workspaces(id) on delete cascade,
    holder_user_id uuid not null references auth.users(id) on delete cascade,
    expires_at timestamptz not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (workspace_id, resource)
);

-- Telegram user ↔ workspace mapping
create table if not exists telegram_accounts (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references workspaces(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    telegram_user_id bigint not null,
    username text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(workspace_id, telegram_user_id)
);

-- RLS
alter table leader_locks enable row level security;
alter table telegram_accounts enable row level security;

-- Leader locks policies
-- Members of workspace can read locks in their workspace
drop policy if exists "locks_select" on leader_locks;
create policy "locks_select" on leader_locks for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Insert: only members; holder must be current user
drop policy if exists "locks_insert" on leader_locks;
create policy "locks_insert" on leader_locks for insert with check (
    holder_user_id = auth.uid()
    and workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Update: allow holder to refresh; also allow any member to take over if expired
drop policy if exists "locks_update" on leader_locks;
create policy "locks_update" on leader_locks for update using (
    (holder_user_id = auth.uid())
    or (expires_at <= now() and workspace_id in (select workspace_id from workspace_members where user_id = auth.uid()))
);

-- Delete: only holder can delete
drop policy if exists "locks_delete" on leader_locks;
create policy "locks_delete" on leader_locks for delete using (
    holder_user_id = auth.uid()
);

create index if not exists idx_leader_locks_ws_resource on leader_locks(workspace_id, resource);

-- Telegram accounts policies
drop policy if exists "tg_select" on telegram_accounts;
create policy "tg_select" on telegram_accounts for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

drop policy if exists "tg_insert" on telegram_accounts;
create policy "tg_insert" on telegram_accounts for insert with check (
    user_id = auth.uid()
    and workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

drop policy if exists "tg_update" on telegram_accounts;
create policy "tg_update" on telegram_accounts for update using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create index if not exists idx_telegram_accounts_ws_user on telegram_accounts(workspace_id, telegram_user_id);
