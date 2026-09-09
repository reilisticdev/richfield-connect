-- 023_broadcast_announcement.sql
--
-- Closes the gap 013_events_and_notifications.sql's own comment flagged:
-- notifications.type already included 'admin_announcement' and the table's
-- comment said "the admin-announcement path write here" -- but that path
-- was never built, so Announcements.jsx just called alert() and moved on.
--
-- Mirrors approve_business_account / reject_business_account's exact
-- pattern: SECURITY DEFINER, explicit is_admin() check, REVOKE/GRANT
-- lockdown. Only sends to account_status = 'active' profiles.

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

  INSERT INTO public.notifications (recipient_id, type, payload)
  SELECT id, 'admin_announcement',
         jsonb_build_object('title', announcement_title, 'message', announcement_message)
  FROM public.profiles
  WHERE account_status = 'active'
    AND (target_role IS NULL OR role = target_role);

  GET DIAGNOSTICS recipient_count = ROW_COUNT;
  RETURN recipient_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.broadcast_announcement(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.broadcast_announcement(TEXT, TEXT, TEXT) TO authenticated;
