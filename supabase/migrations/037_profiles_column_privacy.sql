-- 037_profiles_column_privacy.sql
--
-- profiles.email and profiles.fcm_token were readable by every signed-in
-- member. The row policies on profiles ("Authenticated users can view
-- active profiles") are correct for the public parts of a profile, but RLS
-- is row-level: once a member may see a row they may select every column
-- of it, so `GET /rest/v1/profiles?select=email,fcm_token` returned every
-- active member's email address and push token. No screen ever showed
-- them; the API still served them. The POPIA screen's own privacy text
-- acknowledged this. This migration closes it at the column level.
--
-- After this migration:
--   * anon / authenticated cannot SELECT email or fcm_token on profiles at
--     all, in any row. A member's own email still comes from Supabase Auth
--     (auth.currentUser.email), and the POPIA export RPC (030) runs as
--     security definer, so nothing a member is entitled to is lost.
--   * authenticated keeps UPDATE on fcm_token (the app registers its push
--     token on its own row; RLS limits the row) but loses UPDATE on email
--     (email changes belong to Auth, and the signup trigger writes it as
--     security definer).
--   * Administrators read email through the new public.admin_profiles view
--     instead of the table. The view is owned by postgres, so it is not
--     subject to the column revoke, and its own WHERE clause repeats the
--     "Administrators can view all profiles" policy. It exposes neither
--     fcm_token nor skill_embedding.
--   * Edge functions use the service role and are unaffected.
--
-- CLIENT IMPACT (this is why the migration ships with client changes):
-- Postgres refuses `SELECT *` when the role lacks privilege on any column,
-- and PostgREST's `select=*` is exactly that. Every `.from('profiles')
-- .select()` with no column list now fails with 42501. The same PR makes
-- the three mobile call sites explicit and points the web admin pages at
-- admin_profiles. Do not apply this migration until those clients are
-- merged and rebuilt, or existing APKs cannot sign in.
--
-- Verification (rolled back) is documented in the PR.

-- ---------------------------------------------------------------------------
-- 1. Column-level privileges
-- ---------------------------------------------------------------------------
-- A column-level REVOKE does nothing while the role still holds the
-- table-level privilege (verified: after `revoke select (email) ...` the
-- student role still read every email). The working pattern is to drop the
-- table-level privilege and grant back an explicit column list.
--
-- SELECT: everything except email and fcm_token. anon gets the same list so
-- an unauthenticated query still returns an empty set (RLS) rather than a
-- 42501, exactly as before.
revoke select on public.profiles from anon, authenticated;
grant select (
  id,
  role,
  first_name,
  last_name,
  account_status,
  professional_headline,
  career_interests,
  bio,
  avatar_path,
  github_url,
  linkedin_url,
  website_url,
  skill_embedding,
  created_at,
  last_active_at
) on public.profiles to anon, authenticated;

-- UPDATE: only what the app writes. ProfileService.updateProfile patches
-- the nine profile fields; PushNotificationService writes fcm_token. Nothing
-- client-side writes email, role, account_status or skill_embedding (role
-- and status changes go through the admin RPCs of migration 033, which are
-- security definer). anon keeps no UPDATE at all.
revoke update on public.profiles from anon, authenticated;
grant update (
  first_name,
  last_name,
  professional_headline,
  career_interests,
  bio,
  avatar_path,
  github_url,
  linkedin_url,
  website_url,
  fcm_token
) on public.profiles to authenticated;

-- INSERT / DELETE are left as they were: profiles has no INSERT or DELETE
-- policy for either role, so RLS already refuses them; the signup trigger
-- (security definer) is the only writer.

-- ---------------------------------------------------------------------------
-- 2. Administrator read path for email
-- ---------------------------------------------------------------------------
-- security_invoker = false is the point: the view runs as its owner
-- (postgres), which holds the column privilege. The WHERE clause is the
-- guard. Deliberate, and flagged as such for the Supabase advisor.
create or replace view public.admin_profiles
with (security_invoker = false)
as
  select
    id,
    role,
    first_name,
    last_name,
    email,
    account_status,
    professional_headline,
    career_interests,
    bio,
    avatar_path,
    github_url,
    linkedin_url,
    website_url,
    created_at,
    last_active_at
  from public.profiles
  where public.is_admin(auth.uid());

alter view public.admin_profiles owner to postgres;

comment on view public.admin_profiles is
  'Administrator-only read of profiles including email (never fcm_token or skill_embedding). Returns no rows for non-administrators. Replaces direct profiles reads on the web admin Users and Moderation pages after migration 037.';

revoke all on public.admin_profiles from public, anon;
grant select on public.admin_profiles to authenticated, service_role;
