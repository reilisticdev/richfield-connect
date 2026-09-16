-- 047_pin_opportunity_status.sql
--
-- "Business manages own opportunities" (011) is an ALL policy with
-- with_check (auth.uid() = business_id) only - it never constrains the
-- `status` column. opportunities.status has full INSERT/UPDATE grants for
-- `authenticated` (never column-restricted, unlike profiles.account_status
-- in 037), so nothing at the RLS or grant level stops a business from
-- inserting a listing with status='approved' directly, or self-updating a
-- pending listing to 'approved' - completely bypassing admin moderation.
--
-- Verified live via a rolled-back transaction 2026-09-17: both
--   insert into opportunities (..., status) values (..., 'approved')
--   insert ... status='pending' then update ... set status='approved'
-- succeeded for a real business account before this migration.
--
-- Fix: a BEFORE INSERT OR UPDATE trigger pins status for any non-admin
-- caller - 'pending' on insert, unchanged (OLD.status) on update. Chosen
-- over tightening the RLS policy itself because a WITH CHECK can't easily
-- distinguish "editing my own approved listing's description" (should
-- still be allowed) from "changing status" (should not) without a fragile
-- self-referential subquery; a trigger makes the intent explicit and
-- leaves the existing admin direct-update flow (Opportunities.jsx,
-- AdminModerationScreen - there is no approve_opportunity RPC, per the
-- PR #59 note) completely untouched, since is_admin(auth.uid()) callers
-- pass straight through.

create or replace function public.pin_opportunity_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.is_admin(auth.uid()) then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    NEW.status := 'pending';
  else
    NEW.status := OLD.status;
  end if;

  return NEW;
end;
$$;

comment on function public.pin_opportunity_status() is
  'Prevents a business from setting or changing its own opportunity''s status - always pending on insert, unchanged on update, for any non-admin caller. Admins (is_admin(auth.uid())) pass through unchanged, matching the existing direct-update moderation flow.';

revoke all on function public.pin_opportunity_status() from public, anon, authenticated;

drop trigger if exists trg_pin_opportunity_status on public.opportunities;
create trigger trg_pin_opportunity_status
  before insert or update on public.opportunities
  for each row execute function public.pin_opportunity_status();
