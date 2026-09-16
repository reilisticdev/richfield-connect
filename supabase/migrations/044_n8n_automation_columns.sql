-- 044_n8n_automation_columns.sql
--
-- Schema support for the four n8n workflows Keshav built (auto-flag content,
-- pending-verification chaser, daily governance digest, stale event cleanup -
-- see /n8n in the repo). Both additions are exactly what each workflow's own
-- README already specified; this migration just applies them.
--
-- No RLS changes: both tables are only ever written here by n8n's
-- service-role credential, which already bypasses RLS by design (same model
-- as every other trusted-backend write in this project).

-- ---------------------------------------------------------------------
-- 1. content_reports: columns the auto-flag workflow's insert expects
-- ---------------------------------------------------------------------
alter table public.content_reports
  add column if not exists report_type text default 'manual',
  add column if not exists category    text,
  add column if not exists severity    integer,
  add column if not exists flagged_by  text;

-- ---------------------------------------------------------------------
-- 2. events: archived_at for the stale-event-cleanup workflow
-- ---------------------------------------------------------------------
-- Set, never deleted - matches how this schema treats every other
-- soft-removal (suspended accounts, withdrawn consent, etc.).
alter table public.events
  add column if not exists archived_at timestamptz;
