-- 033_admin_account_management.sql
--
-- Lets administrators suspend, reactivate and remove member accounts from the
-- web Users page (checklist section 2: "approve, suspend and remove users").
-- Before this, 'suspended' existed as an account status but nothing set it,
-- and nothing could remove another member's account. Tested in a rolled-back
-- transaction with a throwaway account before being applied.
--
-- - admin_set_account_status() suspends an active account or reactivates a
--   suspended one. Suspension also bans the auth user, so sign-in and token
--   refresh fail, and ends their sessions. The mobile app shows a suspended
--   screen for the short window before the current access token expires.
-- - admin_remove_account() deletes the auth user; everything that references
--   the profile cascades, as with delete_my_account() (migration 030).
-- - Administrator accounts can't be suspended or removed through either:
--   they are provisioned separately and own events and verification decisions.
-- - account_actions records who did what and why. Only administrators can
--   read it, and only these functions write it. For a removed account it keeps
--   a role-and-name label, not the email address.

create table public.account_actions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  admin_id uuid references public.profiles(id) on delete set null,
  action text not null check (action in ('suspended', 'reactivated', 'removed')),
  target_label text not null,
  reason text,
  created_at timestamptz not null default now()
);

alter table public.account_actions enable row level security;

create policy "Administrators read account actions" on public.account_actions
  for select to authenticated using (public.is_admin(auth.uid()));

revoke all on public.account_actions from anon;
revoke insert, update, delete, truncate, references, trigger on public.account_actions from authenticated;
grant select on public.account_actions to authenticated;

create or replace function public.admin_set_account_status(target_id uuid, suspend boolean, reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  target record;
begin
  if not public.is_admin(me) then
    raise exception 'Only an administrator can suspend or reactivate accounts.' using errcode = '42501';
  end if;

  select p.id, p.role, p.account_status, p.first_name, p.last_name
    into target
    from profiles p
   where p.id = target_id;

  if target.id is null then
    raise exception 'No account found for id %.', target_id;
  end if;
  if target.role = 'administrator' then
    raise exception 'Administrator accounts can''t be suspended here.' using errcode = '42501';
  end if;
  if suspend and target.account_status <> 'active' then
    raise exception 'Only active accounts can be suspended; this one is %.', target.account_status;
  end if;
  if not suspend and target.account_status <> 'suspended' then
    raise exception 'Only suspended accounts can be reactivated; this one is %.', target.account_status;
  end if;

  update profiles
     set account_status = case when suspend then 'suspended'::user_account_status else 'active'::user_account_status end
   where id = target_id;

  -- A ban stops sign-in and token refresh; ending the sessions signs the
  -- member out once their current access token expires.
  update auth.users
     set banned_until = case when suspend then 'infinity'::timestamptz else null end
   where id = target_id;
  if suspend then
    delete from auth.sessions where user_id = target_id;
  end if;

  insert into account_actions (profile_id, admin_id, action, target_label, reason)
  values (target_id, me, case when suspend then 'suspended' else 'reactivated' end,
          initcap(target.role::text) || ': ' || btrim(coalesce(target.first_name, '') || ' ' || coalesce(target.last_name, '')),
          nullif(btrim(reason), ''));
end;
$$;

create or replace function public.admin_remove_account(target_id uuid, reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  target record;
begin
  if not public.is_admin(me) then
    raise exception 'Only an administrator can remove accounts.' using errcode = '42501';
  end if;

  select p.id, p.role, p.first_name, p.last_name
    into target
    from profiles p
   where p.id = target_id;

  if target.id is null then
    raise exception 'No account found for id %.', target_id;
  end if;
  if target.role = 'administrator' then
    raise exception 'Administrator accounts can''t be removed here.' using errcode = '42501';
  end if;

  insert into account_actions (profile_id, admin_id, action, target_label, reason)
  values (null, me, 'removed',
          initcap(target.role::text) || ': ' || btrim(coalesce(target.first_name, '') || ' ' || coalesce(target.last_name, '')),
          nullif(btrim(reason), ''));

  delete from auth.users where id = target_id;
end;
$$;

revoke execute on function public.admin_set_account_status(uuid, boolean, text) from public, anon;
grant execute on function public.admin_set_account_status(uuid, boolean, text) to authenticated;
revoke execute on function public.admin_remove_account(uuid, text) from public, anon;
grant execute on function public.admin_remove_account(uuid, text) to authenticated;
