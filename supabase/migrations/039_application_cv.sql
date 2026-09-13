-- 039_application_cv.sql
--
-- Keshav's QA request (2026-09-12): when a student or alumnus applies for
-- an opportunity, the business must be able to open that applicant's CV
-- for that specific application.
--
-- Design
--   * applications.cv_path: the object key of the CV that was submitted
--     WITH the application. The app copies the member's current CV
--     (profiles.cv_path, migration 038) to
--     "<uid>/applications/<stamp>.pdf" at apply time and stores that key,
--     so the business sees exactly what was submitted even if the member
--     later replaces or removes the CV on their profile. Null when the
--     applicant had no CV on file.
--   * Businesses read it through a new SELECT policy on the private `cvs`
--     bucket, scoped by can_view_application_cv(): the object must be the
--     cv_path of an application to one of the caller's own opportunities.
--     Nothing else in the bucket becomes visible to businesses — Guidelines
--     2.1: business users see only what a student has explicitly made
--     visible, and applying is that explicit act (the app says so before
--     the member confirms).
--   * The snapshot still lives under the member's own folder, so the 038
--     owner policies (replace / delete) and the account-deletion sweep keep
--     covering it, and export_my_data() lists it.
--
-- Requires 038 (the cvs bucket). Apply order: 037 -> 038 -> 039.

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'cvs') then
    raise exception '039_application_cv: apply 038_cv_evidence first (the cvs bucket does not exist).';
  end if;
end
$$;

alter table public.applications
  add column if not exists cv_path text;

comment on column public.applications.cv_path is
  'Object key in the private cvs bucket of the CV submitted with this application ("<uid>/applications/<stamp>.pdf"). Null when the applicant had no CV on file.';

-- ---------------------------------------------------------------------------
-- Who may open an application CV: the business that owns the listing.
-- ---------------------------------------------------------------------------
-- security definer so the check does not depend on the caller's RLS view
-- of applications/opportunities (which would be the same answer, but a
-- storage policy is not the place to rely on that).
create or replace function public.can_view_application_cv(object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.applications a
      join public.opportunities o on o.id = a.opportunity_id
     where a.cv_path = object_name
       and o.business_id = auth.uid()
  );
$$;

comment on function public.can_view_application_cv(text) is
  'True when the cvs object is the cv_path of an application to one of the calling business''s own opportunities (migration 039).';

revoke all on function public.can_view_application_cv(text) from public, anon;
grant execute on function public.can_view_application_cv(text) to authenticated;

drop policy if exists "Businesses view CVs attached to applications on their listings" on storage.objects;
create policy "Businesses view CVs attached to applications on their listings"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'cvs'
    and public.can_view_application_cv(name)
  );
