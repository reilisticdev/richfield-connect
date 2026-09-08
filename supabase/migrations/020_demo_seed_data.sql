-- 020_demo_seed_data.sql
--
-- Realistic demo data so the live demo doesn't run against an empty
-- database. Every table in the platform currently has 0 rows.
--
-- WHY auth.users, NOT a bare INSERT INTO profiles:
--   profiles.id is a hard FK to auth.users.id. handle_new_user()
--   (002_profile_trigger.sql, redefined in 005_signup_role_restriction.sql)
--   fires AFTER INSERT ON auth.users and creates the matching profiles row
--   itself, reading first_name/last_name/role out of raw_user_meta_data. So
--   this script inserts into auth.users (+ a matching auth.identities row,
--   required for email/password sign-in to actually work) and lets that
--   trigger create profiles, then follows up with UPDATE/INSERT for the
--   fields the trigger doesn't set. A bare "INSERT INTO profiles" for an
--   invented id would just fail the FK.
--
--   check_student_domain_before_insert (003_domain_restriction.sql) also
--   fires BEFORE INSERT ON auth.users and rejects student-role emails
--   outside @my.richfield.ac.za / @richfield.ac.za / @my.aaa.ac.za /
--   @aaa.ac.za — every student email below uses one of those domains.
--   Business/alumni emails are exempt.
--
-- DEMO LOGIN CREDENTIALS (throwaway hackathon seed data only — never do
-- this in a real seed script):
--   Student:  thabo.demo@my.richfield.ac.za / Demo1234!
--   Business: hiring@demo-company.co.za     / Demo1234!
-- All other seeded accounts get an unusable random-shaped password since
-- nobody needs to log in as them — they exist to populate feeds/lists.
--
-- IDEMPOTENCY: each user-creation block is guarded by
-- "IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = ...)", so
-- re-running this migration won't duplicate accounts. The opportunity/
-- post/comment/event inserts below that are not guarded are one-shot —
-- documented here rather than adding more ceremony than a hackathon seed
-- script needs. applications/connections use ON CONFLICT DO NOTHING since
-- they have natural unique constraints to lean on.
--
-- DELIBERATE CHOICE: the second business (Horizon Retail Group) is left
-- at account_status='pending' — that's handle_new_user()'s own default
-- for business/alumni roles, so simply NOT overriding it gives Saiyusha's
-- web admin "Pending Business Accounts" section (the one genuinely
-- backend-wired part of her Moderation page) real data to approve live.

create extension if not exists pgcrypto;

-- =====================================================================
-- STUDENTS
-- =====================================================================

-- Student 1: Thabo Nkosi — known password, usable for a live demo login.
do $$
declare
  sid uuid := gen_random_uuid();
begin
  if not exists (select 1 from auth.users where email = 'thabo.demo@my.richfield.ac.za') then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000', sid, 'authenticated', 'authenticated',
      'thabo.demo@my.richfield.ac.za', extensions.crypt('Demo1234!', extensions.gen_salt('bf')), now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('first_name', 'Thabo', 'last_name', 'Nkosi', 'role', 'student'),
      '', '', '', '', now(), now()
    );

    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      sid::text, sid,
      jsonb_build_object('sub', sid::text, 'email', 'thabo.demo@my.richfield.ac.za', 'email_verified', true),
      'email', now(), now(), now()
    );

    -- handle_new_user() already created the profiles row (active, per student default).
    update profiles set professional_headline = 'Aspiring Backend Developer', career_interests = 'Backend engineering, cloud infrastructure'
      where id = sid;

    insert into skills (profile_id, skill_name) values (sid, 'Python'), (sid, 'SQL');
    insert into education (profile_id, programme, campus, enrolment_year)
      values (sid, 'BSc Information Technology', 'Braamfontein', 2023);
    insert into projects (profile_id, title, description, github_url)
      values (sid, 'Campus Event Finder', 'React Native app for discovering campus events and RSVPing.', 'https://github.com/demo/campus-events');
  end if;
end $$;

-- Student 2: Naledi Mahlangu
do $$
declare
  sid uuid := gen_random_uuid();
begin
  if not exists (select 1 from auth.users where email = 'naledi.demo@my.aaa.ac.za') then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000', sid, 'authenticated', 'authenticated',
      'naledi.demo@my.aaa.ac.za', extensions.crypt('SeedOnly!2026', extensions.gen_salt('bf')), now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('first_name', 'Naledi', 'last_name', 'Mahlangu', 'role', 'student'),
      '', '', '', '', now(), now()
    );

    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      sid::text, sid,
      jsonb_build_object('sub', sid::text, 'email', 'naledi.demo@my.aaa.ac.za', 'email_verified', true),
      'email', now(), now(), now()
    );

    update profiles set professional_headline = 'Marketing & Brand Strategy Student', career_interests = 'Brand management, digital marketing'
      where id = sid;

    insert into skills (profile_id, skill_name) values (sid, 'Graphic Design'), (sid, 'Content Strategy');
    insert into education (profile_id, programme, campus, enrolment_year, graduation_year)
      values (sid, 'BA Marketing Communications', 'AAA School of Advertising', 2022, 2026);
    insert into projects (profile_id, title, description, live_url)
      values (sid, 'Personal Brand Portfolio', 'A portfolio site showcasing campaign case studies.', 'https://naledi-demo.example.com');
  end if;
end $$;

-- Student 3: Sipho Dlamini
do $$
declare
  sid uuid := gen_random_uuid();
begin
  if not exists (select 1 from auth.users where email = 'sipho.demo@richfield.ac.za') then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000', sid, 'authenticated', 'authenticated',
      'sipho.demo@richfield.ac.za', extensions.crypt('SeedOnly!2026', extensions.gen_salt('bf')), now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('first_name', 'Sipho', 'last_name', 'Dlamini', 'role', 'student'),
      '', '', '', '', now(), now()
    );

    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      sid::text, sid,
      jsonb_build_object('sub', sid::text, 'email', 'sipho.demo@richfield.ac.za', 'email_verified', true),
      'email', now(), now(), now()
    );

    update profiles set professional_headline = 'Software Development Diploma Student', career_interests = 'Web development, freelancing'
      where id = sid;

    insert into skills (profile_id, skill_name) values (sid, 'Java'), (sid, 'React');
    insert into education (profile_id, programme, campus, enrolment_year)
      values (sid, 'Diploma in Software Development', 'Braamfontein', 2024);
    insert into work_experience (profile_id, title, organisation, description, start_date)
      values (sid, 'Freelance Web Developer', 'Self-employed', 'Building small business websites part-time.', '2025-01-15');
  end if;
end $$;

-- =====================================================================
-- BUSINESSES
-- =====================================================================

-- Business 1: Demo Company (Pty) Ltd — known password, flipped active so
-- it can post approved opportunities and log in live during the demo.
do $$
declare
  bid uuid := gen_random_uuid();
begin
  if not exists (select 1 from auth.users where email = 'hiring@demo-company.co.za') then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000', bid, 'authenticated', 'authenticated',
      'hiring@demo-company.co.za', extensions.crypt('Demo1234!', extensions.gen_salt('bf')), now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('first_name', 'Lerato', 'last_name', 'Dube', 'role', 'business'),
      '', '', '', '', now(), now()
    );

    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      bid::text, bid,
      jsonb_build_object('sub', bid::text, 'email', 'hiring@demo-company.co.za', 'email_verified', true),
      'email', now(), now(), now()
    );

    -- handle_new_user() defaults business accounts to account_status='pending' — override to active.
    update profiles set account_status = 'active' where id = bid;

    insert into business_profiles (profile_id, company_name, industry, description, location, website, contact_email)
      values (bid, 'Demo Company (Pty) Ltd', 'Software', 'A software consultancy building tools for the SA graduate market.', 'Sandton, Johannesburg', 'https://demo-company.example.com', 'hiring@demo-company.co.za');
  end if;
end $$;

-- Business 2: Horizon Retail Group — deliberately left 'pending' (do NOT
-- override account_status) so the admin Moderation page has a real
-- pending-business row to approve on stage.
do $$
declare
  bid uuid := gen_random_uuid();
begin
  if not exists (select 1 from auth.users where email = 'careers@horizon-retail.demo') then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000', bid, 'authenticated', 'authenticated',
      'careers@horizon-retail.demo', extensions.crypt('SeedOnly!2026', extensions.gen_salt('bf')), now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('first_name', 'Karabo', 'last_name', 'Molefe', 'role', 'business'),
      '', '', '', '', now(), now()
    );

    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      bid::text, bid,
      jsonb_build_object('sub', bid::text, 'email', 'careers@horizon-retail.demo', 'email_verified', true),
      'email', now(), now(), now()
    );

    insert into business_profiles (profile_id, company_name, industry, description, location, contact_email)
      values (bid, 'Horizon Retail Group', 'Retail', 'A national retail chain building out its graduate programme.', 'Cape Town', 'careers@horizon-retail.demo');
  end if;
end $$;

-- =====================================================================
-- OPPORTUNITIES (both from the active business — a pending business
-- realistically wouldn't have live listings yet)
-- =====================================================================

insert into opportunities (business_id, title, description, opportunity_type, required_skills, programme_filter, status)
select id, 'Junior Software Developer Internship',
  'A 6-month internship building internal tooling alongside our engineering team. Great fit for students comfortable with Python and SQL.',
  'internship', array['Python', 'SQL'], 'BSc Information Technology', 'approved'
from profiles where email = 'hiring@demo-company.co.za';

insert into opportunities (business_id, title, description, opportunity_type, required_skills, programme_filter, status)
select id, 'Marketing Graduate Programme',
  'A 12-month graduate rotation across brand, content, and campaign strategy.',
  'graduate_vacancy', array['Marketing', 'Content Strategy'], 'BA Marketing Communications', 'approved'
from profiles where email = 'hiring@demo-company.co.za';

-- =====================================================================
-- APPLICATIONS
-- =====================================================================

insert into applications (opportunity_id, student_id, status)
select o.id, p.id, 'submitted'
from opportunities o, profiles p
where o.title = 'Junior Software Developer Internship' and p.email = 'thabo.demo@my.richfield.ac.za'
on conflict (opportunity_id, student_id) do nothing;

insert into applications (opportunity_id, student_id, status)
select o.id, p.id, 'reviewed'
from opportunities o, profiles p
where o.title = 'Junior Software Developer Internship' and p.email = 'sipho.demo@richfield.ac.za'
on conflict (opportunity_id, student_id) do nothing;

insert into applications (opportunity_id, student_id, status)
select o.id, p.id, 'submitted'
from opportunities o, profiles p
where o.title = 'Marketing Graduate Programme' and p.email = 'naledi.demo@my.aaa.ac.za'
on conflict (opportunity_id, student_id) do nothing;

-- =====================================================================
-- SOCIAL: connections, posts, comments
-- =====================================================================

insert into connections (requester_id, addressee_id, status)
select a.id, b.id, 'accepted'
from profiles a, profiles b
where a.email = 'thabo.demo@my.richfield.ac.za' and b.email = 'naledi.demo@my.aaa.ac.za'
on conflict (requester_id, addressee_id) do nothing;

insert into connections (requester_id, addressee_id, status)
select a.id, b.id, 'pending'
from profiles a, profiles b
where a.email = 'thabo.demo@my.richfield.ac.za' and b.email = 'sipho.demo@richfield.ac.za'
on conflict (requester_id, addressee_id) do nothing;

insert into posts (author_id, body)
select id, 'Excited to start my internship search! Just finished a React Native app for finding campus events. 🚀'
from profiles where email = 'thabo.demo@my.richfield.ac.za';

insert into posts (author_id, body)
select id, 'Had an amazing time at the Richfield career fair today — met some great recruiters and picked up so many tips for my portfolio.'
from profiles where email = 'naledi.demo@my.aaa.ac.za';

insert into posts (author_id, body)
select id, 'Demo Company is hiring! We just opened applications for our Junior Software Developer Internship — check the Opportunities tab.'
from profiles where email = 'hiring@demo-company.co.za';

insert into comments (post_id, author_id, body)
select p.id, a.id, 'Congrats! Let me know if you want a study buddy for interview prep.'
from posts p, profiles a
where p.body like 'Excited to start my internship search%' and a.email = 'sipho.demo@richfield.ac.za';

-- =====================================================================
-- EVENT (created_by must be an existing administrator profile — you
-- already have one from running provision-admin.ts; if none exists yet
-- this insert is skipped rather than failing the whole migration)
-- =====================================================================

insert into events (title, description, event_date, location, status, created_by)
select 'Graduate Career Fair 2026',
  'Meet recruiters from Richfield''s corporate partners and explore internship and graduate opportunities.',
  now() + interval '14 days', 'Braamfontein Campus', 'published', id
from profiles where role = 'administrator'
limit 1;
