-- Dochi Cloud Schema
-- Run this in Supabase SQL Editor to set up the database

-- 1. Workspaces
create table if not exists workspaces (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    invite_code text unique,
    owner_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

-- 2. Workspace Members
create table if not exists workspace_members (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references workspaces(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null default 'member' check (role in ('owner', 'member')),
    joined_at timestamptz not null default now(),
    unique(workspace_id, user_id)
);

-- 3. Devices
create table if not exists devices (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references workspaces(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    device_name text not null,
    platform text not null default 'macOS',
    last_seen_at timestamptz not null default now(),
    is_online boolean not null default false,
    created_at timestamptz not null default now()
);

-- 4. Context Files (system.md, memory.md, etc.)
create table if not exists context_files (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references workspaces(id) on delete cascade,
    file_type text not null, -- 'system', 'memory', 'family_memory', 'user_memory'
    user_id uuid references auth.users(id) on delete cascade, -- null for shared files
    content text not null default '',
    version integer not null default 1,
    updated_at timestamptz not null default now(),
    updated_by uuid references auth.users(id),
    unique(workspace_id, file_type, user_id)
);

-- 5. Profiles (user identities within workspace)
create table if not exists profiles (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references workspaces(id) on delete cascade,
    name text not null,
    aliases text[] not null default '{}',
    description text not null default '',
    created_at timestamptz not null default now()
);

-- ============================================================
-- Row Level Security (RLS)
-- ============================================================

alter table workspaces enable row level security;
alter table workspace_members enable row level security;
alter table devices enable row level security;
alter table context_files enable row level security;
alter table profiles enable row level security;

-- Workspaces: members can read
create policy "workspace_select" on workspaces for select using (
    id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Workspaces: anyone can read by invite_code (for joining)
create policy "workspace_select_by_invite" on workspaces for select using (
    invite_code is not null
);

-- Workspaces: owner can insert
create policy "workspace_insert" on workspaces for insert with check (
    owner_id = auth.uid()
);

-- Workspaces: owner can update
create policy "workspace_update" on workspaces for update using (
    owner_id = auth.uid()
);

-- Workspace Members: members can read their workspace's members
create policy "member_select" on workspace_members for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Workspace Members: authenticated users can insert (join)
create policy "member_insert" on workspace_members for insert with check (
    user_id = auth.uid()
);

-- Workspace Members: users can delete their own membership
create policy "member_delete" on workspace_members for delete using (
    user_id = auth.uid()
);

-- Devices: workspace members can read
create policy "device_select" on devices for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Devices: user can manage own devices
create policy "device_insert" on devices for insert with check (
    user_id = auth.uid()
);

create policy "device_update" on devices for update using (
    user_id = auth.uid()
);

create policy "device_delete" on devices for delete using (
    user_id = auth.uid()
);

-- Context Files: workspace members can read
create policy "context_select" on context_files for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

-- Context Files: workspace members can insert/update
create policy "context_insert" on context_files for insert with check (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "context_update" on context_files for update using (
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
