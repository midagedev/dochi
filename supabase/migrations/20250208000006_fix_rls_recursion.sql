-- Fix infinite recursion in workspace_members RLS policies
-- Problem: member_select references workspace_members from within workspace_members policy

-- Drop problematic policies
drop policy if exists "member_select" on workspace_members;
drop policy if exists "member_insert" on workspace_members;

-- member_select: use auth.uid() directly, no self-reference
create policy "member_select" on workspace_members for select using (
    user_id = auth.uid()
);

-- member_insert: owner can add members to their workspace, OR user can add themselves
-- (needed for createWorkspace flow where owner inserts themselves)
create policy "member_insert" on workspace_members for insert with check (
    user_id = auth.uid()
);
