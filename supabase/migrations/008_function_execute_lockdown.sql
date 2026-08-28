-- Every new function in this session was created SECURITY DEFINER, and
-- Postgres grants EXECUTE to PUBLIC by default on function creation -- an
-- explicit GRANT TO authenticated does not strip that implicit PUBLIC grant.
-- The Supabase security advisor flagged all of them as callable by `anon`
-- over PostgREST (e.g. POST /rest/v1/rpc/is_admin with no auth header).
--
-- None of them are meant to be called anonymously:
--   - prevent_unauthorised_role_change / handle_new_user / enforce_student_domain
--     are trigger functions only. Triggers fire regardless of the invoking
--     role's EXECUTE grants, so revoking PUBLIC here does not touch how
--     inserts/updates on auth.users or profiles behave.
--   - is_admin needs to stay callable by `authenticated` (the RLS policies in
--     006/007 call it as the querying role) but has no reason to be anon-callable.
--   - approve_alumni_verification / reject_alumni_verification are meant to be
--     called by a signed-in administrator's client; the function body already
--     rejects non-admins via is_admin(auth.uid()), but there's no reason to
--     expose the RPC endpoint to anon at all.
REVOKE EXECUTE ON FUNCTION public.is_admin(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prevent_unauthorised_role_change() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enforce_student_domain() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_alumni_verification(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reject_alumni_verification(UUID, TEXT) FROM PUBLIC;

-- The explicit grants from 004/007 (authenticated, service_role) are untouched
-- by the REVOKE ... FROM PUBLIC above, so admins and internal RLS checks keep
-- working; only the unauthenticated PUBLIC grant is removed.

-- Bonus fix, same theme: enforce_student_domain (003) was defined without a
-- pinned search_path, which the advisor separately flags as mutable-search-path
-- risk on a SECURITY DEFINER function. One-line pin, no behaviour change.
ALTER FUNCTION public.enforce_student_domain() SET search_path = public;
