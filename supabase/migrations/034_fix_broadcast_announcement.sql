-- 034_fix_broadcast_announcement.sql
--
-- The web Announcements page has never been able to send anything. Every
-- call to broadcast_announcement() (migration 023) failed with
--
--   42883: operator does not exist: user_role = text
--
-- because profiles.role is the user_role enum (001) and target_role is a
-- TEXT parameter. Postgres plans the whole WHERE clause up front, so the
-- comparison broke even for "Everyone" (target_role NULL). PostgREST maps
-- 42883 to HTTP 404, which is why the API logs showed
-- POST /rest/v1/rpc/broadcast_announcement -> 404 instead of a readable
-- error, and the page only said "Could not send announcement."
--
-- Reported in Keshav's QA pass on 2026-09-11 and reproduced by running the
-- function as the administrator inside a rolled-back transaction.
--
-- Also rejects a blank title or message, so an empty broadcast can't reach
-- every member's notifications from a direct API call.
--
-- CREATE OR REPLACE keeps the signature, so 023's grants still hold; they
-- are repeated so this file is correct on its own.

CREATE OR REPLACE FUNCTION public.broadcast_announcement(
  announcement_title TEXT,
  announcement_message TEXT,
  target_role TEXT DEFAULT NULL  -- NULL = everyone; 'student'|'alumni'|'business' to target one role
)
RETURNS INT AS $$
DECLARE
  recipient_count INT;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only an administrator may broadcast an announcement.';
  END IF;

  IF target_role IS NOT NULL AND target_role NOT IN ('student', 'alumni', 'business') THEN
    RAISE EXCEPTION 'Invalid target_role: %', target_role;
  END IF;

  IF btrim(coalesce(announcement_title, '')) = ''
     OR btrim(coalesce(announcement_message, '')) = '' THEN
    RAISE EXCEPTION 'An announcement needs a title and a message.';
  END IF;

  INSERT INTO public.notifications (recipient_id, type, payload)
  SELECT id, 'admin_announcement',
         jsonb_build_object('title', btrim(announcement_title), 'message', btrim(announcement_message))
  FROM public.profiles
  WHERE account_status = 'active'
    AND (target_role IS NULL OR role::text = target_role);

  GET DIAGNOSTICS recipient_count = ROW_COUNT;
  RETURN recipient_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.broadcast_announcement(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.broadcast_announcement(TEXT, TEXT, TEXT) TO authenticated;
