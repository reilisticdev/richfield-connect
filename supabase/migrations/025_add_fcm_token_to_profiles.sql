-- 025_add_fcm_token_to_profiles.sql
--
-- Storage for a device's Firebase Cloud Messaging registration token, so
-- a backend process can actually target a push at a specific user. Before
-- this, mobile/lib/services/push_notification_service.dart obtained a
-- token and only debugPrint()'d it — nothing persisted it anywhere, so
-- nothing server-side could ever send a notification to a real device.
--
-- Single nullable text column, one token per user. Multi-device support
-- (a user signed in on two phones) would need a separate
-- profile_fcm_tokens table instead — not needed for the demo, not built
-- here; noted so it isn't mistaken for an oversight later.
--
-- No new RLS policy needed: "Users can update their own profile"
-- (auth.uid() = id, supabase/migrations/*_profiles*.sql) already covers
-- UPDATE on the whole row, this column included. Confirmed by reading the
-- live policy SQL, not assumed.

alter table public.profiles
  add column if not exists fcm_token text;

comment on column public.profiles.fcm_token is
  'Firebase Cloud Messaging registration token for this user''s device, written client-side by PushNotificationService.initialize(). Null until the user has granted notification permission at least once. Overwritten (not appended) on every app start, so this only ever holds the most recently seen device.';
