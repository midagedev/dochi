-- Fix: workspace owner must be able to SELECT their workspace
-- even before being added as a member (needed for INSERT...RETURNING)

drop policy if exists "workspace_select" on workspaces;

create policy "workspace_select" on workspaces for select using (
    owner_id = auth.uid()
    or id in (select workspace_id from workspace_members where user_id = auth.uid())
);
