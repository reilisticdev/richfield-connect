-- 042_user_blocks.sql
--
-- Lets a member block another member outright, independent of any connection
-- state. connections.status only allows pending/accepted/declined, so there
-- was nowhere for "block someone I was never connected to" to live - a
-- separate table is the right shape. A block silently stops new messages and
-- new connection requests in both directions; it does not touch an existing
-- accepted connection or delete history, matching how the rest of this schema
-- treats removal (USING still allows read/delete of your own rows, only
-- WITH CHECK is tightened - same shape as migration 040).

-- ---------------------------------------------------------------------
-- 1. Table
-- ---------------------------------------------------------------------
create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);

create index blocks_blocked_id_idx on public.blocks (blocked_id);

alter table public.blocks enable row level security;

-- Only your own blocks are visible - not who has blocked you, matching how
-- most social apps treat this so a blocked member can't retaliate on the back
-- of finding out.
create policy "Members see their own blocks"
  on public.blocks for select
  using (auth.uid() = blocker_id);

create policy "Members create their own blocks"
  on public.blocks for insert
  with check (
    auth.uid() = blocker_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.account_status = 'active'
    )
  );

create policy "Members remove their own blocks"
  on public.blocks for delete
  using (auth.uid() = blocker_id);

revoke all on public.blocks from anon;
grant select, insert, delete on public.blocks to authenticated;

-- ---------------------------------------------------------------------
-- 2. Helper for RLS: true if either side has blocked the other. SECURITY
--    DEFINER so a policy on messages/connections can check a block that
--    involves the *other* party without that party's own blocks being
--    readable to the caller (their SELECT policy only shows their own).
-- ---------------------------------------------------------------------
create or replace function public.is_blocked(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

revoke execute on function public.is_blocked(uuid, uuid) from public, anon;
grant execute on function public.is_blocked(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Wire the block into messages and connections - WITH CHECK only, same
--    shape as migration 040. Existing message history and any already-
--    accepted connection are untouched; USING is unchanged on both tables.
-- ---------------------------------------------------------------------
drop policy if exists "Accepted connections can send messages" on public.messages;
create policy "Accepted connections can send messages"
  on public.messages for insert
  with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.account_status = 'active'
    )
    and exists (
      select 1 from public.connections c
      where c.status = 'accepted'
        and ((c.requester_id = messages.sender_id and c.addressee_id = messages.recipient_id)
          or (c.requester_id = messages.recipient_id and c.addressee_id = messages.sender_id))
    )
    and not public.is_blocked(messages.sender_id, messages.recipient_id)
  );

drop policy if exists "Users send connection requests" on public.connections;
create policy "Users send connection requests"
  on public.connections for insert
  with check (
    auth.uid() = requester_id
    and requester_id <> addressee_id
    and status = 'pending'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.account_status = 'active'
    )
    and not public.is_blocked(requester_id, addressee_id)
  );

-- ---------------------------------------------------------------------
-- 4. POPIA completeness: a block you placed is data you created, so
--    export_my_data() (030) should carry it. Deliberately not including
--    "who has blocked me" here - the SELECT policy above hides that from
--    the caller everywhere else in the app, and surfacing it only in an
--    export would be an inconsistent, product-level decision to make
--    under time pressure rather than a data-completeness one.
-- ---------------------------------------------------------------------
create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  files jsonb;
begin
  if me is null then
    raise exception 'Sign in to export your data.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'path', o.name, 'uploaded_at', o.created_at)), '[]'::jsonb)
    into files
    from storage.objects o
   where (storage.foldername(o.name))[1] = me::text;

  return jsonb_build_object(
    'generated_at', now(),
    'account', (select jsonb_build_object(
                  'email', u.email,
                  'phone', u.phone,
                  'created_at', u.created_at,
                  'email_confirmed_at', u.email_confirmed_at,
                  'last_sign_in_at', u.last_sign_in_at,
                  'signup_details', u.raw_user_meta_data)
                from auth.users u where u.id = me),
    'profile', (select to_jsonb(p) - 'skill_embedding' from profiles p where p.id = me),
    'business_profile', (select to_jsonb(b) from business_profiles b where b.profile_id = me),
    'education', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from education t where t.profile_id = me),
    'skills', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from skills t where t.profile_id = me),
    'work_experience', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from work_experience t where t.profile_id = me),
    'projects', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from projects t where t.profile_id = me),
    'certifications', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from certifications t where t.profile_id = me),
    'badges', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from badges t where t.profile_id = me),
    'achievements', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from achievements t where t.profile_id = me),
    'leadership_roles', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from leadership_roles t where t.profile_id = me),
    'profile_visibility', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from profile_visibility t where t.profile_id = me),
    'consent_records', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from consent_records t where t.profile_id = me),
    'verification_claims', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from verification_claims t where t.user_id = me),
    'verification_decisions', (select coalesce(jsonb_agg(to_jsonb(t) - 'admin_id'), '[]') from verification_audit t
                                where t.business_id = me
                                   or t.claim_id in (select c.id from verification_claims c where c.user_id = me)),
    'posts', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from posts t where t.author_id = me),
    'comments', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from comments t where t.author_id = me),
    'reactions', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from reactions t where t.author_id = me),
    'reposts', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from post_reposts t where t.user_id = me),
    'connections', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from connections t where me in (t.requester_id, t.addressee_id)),
    'blocks_given', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from blocks t where t.blocker_id = me),
    'messages', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from messages t where me in (t.sender_id, t.recipient_id)),
    'notifications', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from notifications t where t.recipient_id = me),
    'applications', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from applications t where t.student_id = me),
    'opportunities_posted', (select coalesce(jsonb_agg(to_jsonb(t) - 'embedding'), '[]') from opportunities t where t.business_id = me),
    'endorsements_given', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from endorsements t where t.endorser_id = me),
    'endorsements_received', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from endorsements t where t.recipient_id = me),
    'recommendations_written', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from recommendations t where t.author_id = me),
    'recommendations_received', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from recommendations t where t.recipient_id = me),
    'content_reports_filed', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from content_reports t where t.reported_by = me),
    'content_viewed', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from content_views t where t.viewer_id = me),
    'skill_searches', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from skill_search_log t where t.business_id = me),
    'device_tokens', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from device_tokens t where t.profile_id = me),
    'files', files
  );
end;
$$;

revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;
