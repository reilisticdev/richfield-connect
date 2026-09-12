-- 030_popia_privacy.sql
--
-- Backs the mobile Privacy & data screen. Tested in a rolled-back transaction
-- first, using a throwaway account for the deletion case.
--
-- 1. Profile visibility was never enforced for other members. Each section's
--    SELECT policy looked up profile_visibility as the viewer, but that table
--    only lets owners read their own rows, so every viewer saw "no
--    restrictions". The check now runs in can_view_profile_section(), which
--    can read the owner's settings.
-- 2. profile_visibility accepts 'none', so a section can be hidden from
--    everyone but its owner (no rows still means all members), and
--    set_section_visibility() replaces a section's settings in one
--    transaction so a half-applied change can't leave it wider open.
-- 3. export_my_data() returned five tables. It now returns everything held
--    about the caller: the auth account and signup details, every table that
--    references them, and a list of the files they uploaded.
-- 4. delete_my_account() failed for anyone who had reported content, because
--    content_reports.reported_by had no ON DELETE rule. Reports now survive
--    without the reporter. Administrator accounts get a clear refusal instead
--    of a foreign-key error from their events and verification decisions.
-- 5. consent_records: members could rewrite or delete their consent history.
--    They can now add a consent and withdraw an active one; the database sets
--    the withdrawal time, and a withdrawn consent stays withdrawn.
-- 6. Owners can delete their own alumni verification document, so the app can
--    remove it with their avatar and post media when the account is deleted.

-- 1. Enforce visibility ------------------------------------------------------

create or replace function public.can_view_profile_section(owner_id uuid, section_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select owner_id = auth.uid()
      or not exists (
           select 1 from profile_visibility pv
            where pv.profile_id = owner_id and pv.section = section_name)
      or exists (
           select 1 from profile_visibility pv
            where pv.profile_id = owner_id and pv.section = section_name
              and (pv.visible_to = 'public'
                   or pv.visible_to = (select p.role::text from profiles p where p.id = auth.uid())));
$$;

revoke execute on function public.can_view_profile_section(uuid, text) from public, anon;
grant execute on function public.can_view_profile_section(uuid, text) to authenticated;

drop policy "Others can view per visibility settings" on public.skills;
create policy "Others can view per visibility settings" on public.skills
  for select to authenticated using (public.can_view_profile_section(profile_id, 'skills'));

drop policy "Others can view per visibility settings" on public.education;
create policy "Others can view per visibility settings" on public.education
  for select to authenticated using (public.can_view_profile_section(profile_id, 'education'));

drop policy "Others can view per visibility settings" on public.work_experience;
create policy "Others can view per visibility settings" on public.work_experience
  for select to authenticated using (public.can_view_profile_section(profile_id, 'work_experience'));

drop policy "Others can view per visibility settings" on public.projects;
create policy "Others can view per visibility settings" on public.projects
  for select to authenticated using (public.can_view_profile_section(profile_id, 'projects'));

drop policy "Others can view per visibility settings" on public.certifications;
create policy "Others can view per visibility settings" on public.certifications
  for select to authenticated using (public.can_view_profile_section(profile_id, 'certifications'));

drop policy "Others can view per visibility settings" on public.badges;
create policy "Others can view per visibility settings" on public.badges
  for select to authenticated using (public.can_view_profile_section(profile_id, 'badges'));

drop policy "Others can view per visibility settings" on public.achievements;
create policy "Others can view per visibility settings" on public.achievements
  for select to authenticated using (public.can_view_profile_section(profile_id, 'achievements'));

drop policy "Others can view per visibility settings" on public.leadership_roles;
create policy "Others can view per visibility settings" on public.leadership_roles
  for select to authenticated using (public.can_view_profile_section(profile_id, 'leadership_roles'));

-- 2. 'none' and one-step updates ---------------------------------------------

alter table public.profile_visibility drop constraint profile_visibility_visible_to_check;
alter table public.profile_visibility add constraint profile_visibility_visible_to_check
  check (visible_to in ('public', 'student', 'alumni', 'business', 'none'));
alter table public.profile_visibility add constraint profile_visibility_section_check
  check (section in ('skills', 'education', 'work_experience', 'projects',
                     'certifications', 'badges', 'achievements', 'leadership_roles'));

create or replace function public.set_section_visibility(section_name text, audiences text[])
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Sign in to change who can see your profile.' using errcode = '42501';
  end if;

  delete from profile_visibility where profile_id = me and section = section_name;

  -- All three audiences is the default, stored as no rows.
  if coalesce(cardinality(audiences), 0) = 0 then
    insert into profile_visibility (profile_id, section, visible_to)
    values (me, section_name, 'none');
  elsif not (array['student', 'alumni', 'business'] <@ audiences) then
    insert into profile_visibility (profile_id, section, visible_to)
    select distinct me, section_name, a from unnest(audiences) as a;
  end if;
end;
$$;

revoke execute on function public.set_section_visibility(text, text[]) from public, anon;
grant execute on function public.set_section_visibility(text, text[]) to authenticated;

-- 3. Complete export ---------------------------------------------------------

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

-- 4. Deletion that works -----------------------------------------------------

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Sign in to delete your account.' using errcode = '42501';
  end if;
  if exists (select 1 from profiles where id = me and role = 'administrator') then
    raise exception 'Administrator accounts can''t be deleted from the app. Ask another administrator to remove it.'
      using errcode = '42501';
  end if;
  delete from auth.users where id = me;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

alter table public.content_reports alter column reported_by drop not null;
alter table public.content_reports drop constraint content_reports_reported_by_fkey;
alter table public.content_reports add constraint content_reports_reported_by_fkey
  foreign key (reported_by) references public.profiles(id) on delete set null;

-- 5. Consent history members can't rewrite ----------------------------------

alter table public.consent_records
  add constraint consent_records_type_check check (consent_type in ('registration', 'ai_processing'));

create unique index consent_records_one_active
  on public.consent_records (profile_id, consent_type) where revoked_at is null;

revoke all on public.consent_records from anon;
revoke insert, update, delete, truncate, references, trigger on public.consent_records from authenticated;
grant select on public.consent_records to authenticated;
grant insert (profile_id, consent_type) on public.consent_records to authenticated;
grant update (revoked_at) on public.consent_records to authenticated;

create or replace function public.consent_records_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.revoked_at is not null then
    raise exception 'This consent was already withdrawn. Give it again to record a new consent.'
      using errcode = '42501';
  end if;
  new.revoked_at := case when new.revoked_at is null then null else now() end;
  return new;
end;
$$;

revoke execute on function public.consent_records_guard() from public, anon, authenticated;

create trigger consent_records_guard
  before update on public.consent_records
  for each row execute function public.consent_records_guard();

-- 6. Verification documents can be removed by their owner --------------------

drop policy if exists "Owners delete their own verification document" on storage.objects;
create policy "Owners delete their own verification document"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'alumni-verification-docs'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );
