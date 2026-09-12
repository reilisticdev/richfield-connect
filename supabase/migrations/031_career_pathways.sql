-- 031_career_pathways.sql
--
-- Career pathway explorer. career_pathways (014) listed programme, name, job
-- title and organisation: enough for a list, not for a trajectory. The view
-- now also carries each role's dates and industry, and the alumnus's campus,
-- graduation year, headline and photo. New columns are appended, so existing
-- readers of the view are unaffected.
--
-- work_experience.industry is new and optional.
--
-- The view stays security_invoker, so the education and work_experience
-- visibility policies (fixed in 030) decide which alumni a viewer sees: an
-- alumnus who shows their experience to employers only doesn't appear in a
-- student's explorer. It was also granted to anon; it is now signed-in only.
--
-- Tested in a rolled-back transaction with a throwaway alumni account, as a
-- student, an employer and anon.

alter table public.work_experience
  add column if not exists industry text
  constraint work_experience_industry_length check (industry is null or char_length(industry) <= 80);

create or replace view public.career_pathways
with (security_invoker = true) as
select e.programme,
       p.id as alumni_id,
       p.first_name,
       p.last_name,
       w.title,
       w.organisation,
       w.id as experience_id,
       w.industry,
       w.start_date,
       w.end_date,
       e.campus,
       e.graduation_year,
       p.professional_headline,
       p.avatar_path
  from profiles p
  join education e on e.profile_id = p.id
  join work_experience w on w.profile_id = p.id
 where p.role = 'alumni' and p.account_status = 'active';

revoke all on public.career_pathways from anon;
revoke insert, update, delete, truncate, references, trigger on public.career_pathways from authenticated;
grant select on public.career_pathways to authenticated;
