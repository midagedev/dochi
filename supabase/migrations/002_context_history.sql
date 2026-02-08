-- Context edit history for tracking changes
create table if not exists context_history (
    id uuid primary key default gen_random_uuid(),
    context_file_id uuid not null references context_files(id) on delete cascade,
    workspace_id uuid not null references workspaces(id) on delete cascade,
    file_type text not null,
    content text not null,
    version integer not null,
    edited_by uuid references auth.users(id),
    edited_at timestamptz not null default now()
);

-- RLS
alter table context_history enable row level security;

create policy "history_select" on context_history for select using (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);

create policy "history_insert" on context_history for insert with check (
    workspace_id in (select workspace_id from workspace_members where user_id = auth.uid())
);
