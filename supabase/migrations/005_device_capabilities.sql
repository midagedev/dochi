-- Enhance devices table with capabilities for peer communication (Phase 4 prep)
alter table devices add column if not exists capabilities text[] not null default '{}';

-- Add device_id FK to context_files for tracking which device modified context
alter table context_files add column if not exists device_id uuid references devices(id) on delete set null;

-- Enable Realtime for devices table (peer status tracking)
alter publication supabase_realtime add table devices;
