-- 041_notifications_delete.sql
--
-- notifications had SELECT ("Users view own notifications") and UPDATE
-- ("Users mark own notifications read", read_at only) policies, but no
-- DELETE policy at all - a member could never clear their own notification
-- history, from any client, because RLS defaults to deny. Keshav flagged
-- this as a missing "delete old notifications" feature; the mobile UI
-- change is pure client work, but the policy has to live here first or
-- every delete attempt fails RLS silently (empty result, no error).
--
-- Recipient-only, same shape as the existing SELECT/UPDATE policies on this
-- table. Rows are still written exclusively by triggers/broadcast_announcement()
-- (SECURITY DEFINER) - members were never able to insert their own, and this
-- doesn't change that.

create policy "Users delete own notifications" on public.notifications
  for delete to authenticated using (auth.uid() = recipient_id);
