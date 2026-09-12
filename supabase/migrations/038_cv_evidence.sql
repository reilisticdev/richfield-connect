-- 038_cv_evidence.sql
--
-- Section 3 of the rubric asks the portfolio for "links or evidence such as
-- GitHub and a CV". The CV import (PR #39) reads a PDF with Gemini, fills
-- the profile from it, and throws the file away — nothing on the profile
-- proved a CV ever existed. This keeps the PDF itself.
--
--   * profiles.cv_path / cv_uploaded_at: object key inside the new private
--     `cvs` bucket. One stable key per member ("<uid>/cv.pdf", upserted), so
--     a re-import replaces the file instead of stacking copies. Named
--     cv_path, not cv_url, for the same reason as avatar_path / image_path /
--     video_path: the bucket is private, so a URL is minted per open
--     (signed, short-lived) and never stored.
--   * `cvs` bucket: private, PDF only, 5 MB (the AI service's cap). Readable
--     by the owner and administrators only. A CV is personal data; it is not
--     shown to other members or recruiters until the profile_visibility
--     system (015/030) grows a "cv" section, which is a separate decision.
--   * Column grants: 037 replaces the table-level SELECT/UPDATE on profiles
--     with explicit column lists, so these two columns are granted here
--     explicitly. ORDER MATTERS: a table-level REVOKE also drops every
--     column-level grant on that table (verified), so if this ran before 037
--     the grants below would silently vanish when 037 ran. The guard at the
--     top refuses to apply until 037 has.
--   * POPIA: export_my_data() (030) already lists every object under the
--     member's folder in every bucket, so the CV appears in an export
--     unchanged. The app's delete flow removes the member's objects bucket
--     by bucket before delete_my_account(); the mobile change in this PR
--     adds `cvs` to that sweep.

-- Guard: 037 must already have replaced the table-level privileges.
do $$
begin
  if has_table_privilege('authenticated', 'public.profiles', 'SELECT') then
    raise exception '038_cv_evidence: apply 037_profiles_column_privacy first '
      '(authenticated still holds table-level SELECT on profiles, so the column '
      'grants below would be wiped when 037 runs).';
  end if;
end
$$;

alter table public.profiles
  add column if not exists cv_path text,
  add column if not exists cv_uploaded_at timestamptz;

comment on column public.profiles.cv_path is
  'Object key of the member''s CV in the private cvs bucket ("<uid>/cv.pdf"). Null when no CV is on file.';
comment on column public.profiles.cv_uploaded_at is
  'When cv_path was last written by the member.';

grant select (cv_path, cv_uploaded_at) on public.profiles to authenticated;
grant update (cv_path, cv_uploaded_at) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- Private bucket for the PDFs
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cvs', 'cvs', false, 5242880, array['application/pdf'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Same owner-folder convention as every other bucket: the first path
-- segment is the member's uid, so foldername(name)[1] is the owner.
drop policy if exists "Members upload their own CV" on storage.objects;
create policy "Members upload their own CV"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'cvs'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );

-- The stable key means a second import is an UPDATE, not an INSERT.
drop policy if exists "Members replace their own CV" on storage.objects;
create policy "Members replace their own CV"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'cvs'
    and (auth.uid())::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'cvs'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Members delete their own CV" on storage.objects;
create policy "Members delete their own CV"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'cvs'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Owners and administrators can view CVs" on storage.objects;
create policy "Owners and administrators can view CVs"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'cvs'
    and (
      (auth.uid())::text = (storage.foldername(name))[1]
      or public.is_admin(auth.uid())
    )
  );
