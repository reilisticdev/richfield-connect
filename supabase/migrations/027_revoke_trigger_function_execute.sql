-- 027_revoke_trigger_function_execute.sql
--
-- Follow-up to 026, from the Supabase security advisor (lints 0028/0029):
-- the five notify_* trigger functions are SECURITY DEFINER and, like every
-- function created in public, were executable by anon and authenticated
-- through /rest/v1/rpc. Postgres refuses to run a trigger function outside
-- a trigger, so calling one directly does nothing - but there is no reason
-- for them to be on the API surface at all.
--
-- Revoking EXECUTE does not stop the triggers firing: PostgreSQL checks
-- EXECUTE on a trigger function when CREATE TRIGGER runs, not each time the
-- trigger fires. Verified after applying with a rolled-back test that
-- inserts a message as an authenticated user and sees the notification.

revoke execute on function public.notify_new_message() from public, anon, authenticated;
revoke execute on function public.notify_connection_change() from public, anon, authenticated;
revoke execute on function public.notify_opportunity_matches() from public, anon, authenticated;
revoke execute on function public.notify_event_published() from public, anon, authenticated;
revoke execute on function public.notify_post_activity() from public, anon, authenticated;
