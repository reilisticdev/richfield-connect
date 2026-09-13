-- 035_app_config.sql
--
-- Runtime settings every installed app has to agree on, starting with the
-- address of the AI microservice (ai/app.py).
--
-- The service runs behind an ngrok tunnel. Until now the mobile app could
-- only learn that address from a --dart-define baked into the APK, or from
-- each member typing it into the "AI server address" dialog. Keshav's QA
-- build (2026-09-11) had neither, so CV import and every Career AI action
-- failed with "The AI server address hasn't been set" while the service was
-- up and healthy. With this table an administrator sets the address once and
-- every signed-in app picks it up on its next AI request.
--
-- Deliberately not seeded: a tunnel URL committed to git is stale by the time
-- anyone pulls it. Set or change it with
--
--   insert into public.app_config (key, value) values ('ai_base_url', 'https://...')
--   on conflict (key) do update set value = excluded.value, updated_at = now();

CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- Any signed-in member can read it: the app needs the address, and nothing
-- secret belongs here (the Gemini key stays on the AI server). Not anon.
CREATE POLICY "Signed-in members read app config"
  ON public.app_config FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Administrators manage app config"
  ON public.app_config FOR ALL TO authenticated
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

REVOKE ALL ON public.app_config FROM anon;
