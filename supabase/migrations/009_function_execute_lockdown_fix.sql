-- 008_function_execute_lockdown.sql revoked EXECUTE FROM PUBLIC, but
-- verification after applying it (has_function_privilege(...)) showed `anon`
-- and `authenticated` still had execute on every function. Supabase grants
-- EXECUTE on new public-schema functions directly to anon/authenticated (via
-- project-level default privileges), not through the PUBLIC pseudo-role --
-- so REVOKE ... FROM PUBLIC was a no-op against that grant. This migration
-- revokes from the actual grantees and re-grants only what's needed.

REVOKE EXECUTE ON FUNCTION public.is_admin(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_unauthorised_role_change() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enforce_student_domain() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.approve_alumni_verification(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_alumni_verification(UUID, TEXT) FROM anon, authenticated;

-- prevent_unauthorised_role_change / handle_new_user / enforce_student_domain
-- are trigger-only: no role needs direct EXECUTE, since trigger firing does
-- not check the invoking role's function privileges.

-- is_admin is called as the querying role from within RLS policies (006, 007),
-- so `authenticated` must keep it.
GRANT EXECUTE ON FUNCTION public.is_admin(UUID) TO authenticated;

-- approve/reject are meant to be called by a signed-in administrator's
-- client; the function body itself still enforces is_admin(auth.uid()), this
-- just removes the anon-callable surface.
GRANT EXECUTE ON FUNCTION public.approve_alumni_verification(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_alumni_verification(UUID, TEXT) TO authenticated;
