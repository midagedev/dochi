-- Enable Supabase Realtime for cross-device live sync
-- Tables must be added to the supabase_realtime publication for Postgres Changes to work

alter publication supabase_realtime add table context_files;
alter publication supabase_realtime add table profiles;
alter publication supabase_realtime add table conversations;
