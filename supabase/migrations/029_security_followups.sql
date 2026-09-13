-- 029_security_followups.sql
--
-- Two access-control gaps found while checking the live database on
-- 2026-09-11. Both were tested in a rolled-back transaction first.
--
-- 1. match_opportunities(student_profile_id) is SECURITY DEFINER and ranks
--    listings for whatever profile id it is handed, so any signed-in user
--    could run it for someone else. Nothing calls it (no function, view,
--    trigger, mobile or web code), and it can't rank anything because no
--    embeddings are generated. recommend_opportunities() from 026 replaced
--    it and reads auth.uid() instead of taking an id. EXECUTE stays with
--    postgres and service_role.
--
-- 2. applications had a single FOR ALL policy, auth.uid() = student_id. Any
--    role could apply (a business applied to its own listing on 2026-09-09),
--    listings that were pending or rejected could be applied to, and an
--    applicant could set their own application to 'accepted'. Applicants can
--    now see, submit and withdraw their own applications; submitting needs an
--    active student or alumni account and an approved listing; status is no
--    longer theirs to change. "Business views applicants to own
--    opportunities" is unchanged.

revoke execute on function public.match_opportunities(uuid) from public, anon, authenticated;

drop policy if exists "Student manages own applications" on public.applications;

create policy "Applicants view own applications" on public.applications
  for select to authenticated
  using (auth.uid() = student_id);

create policy "Students and alumni apply to approved listings" on public.applications
  for insert to authenticated
  with check (
    auth.uid() = student_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('student', 'alumni')
        and p.account_status = 'active'
    )
    and exists (
      select 1 from public.opportunities o
      where o.id = opportunity_id and o.status = 'approved'
    )
  );

create policy "Applicants withdraw own applications" on public.applications
  for delete to authenticated
  using (auth.uid() = student_id);
