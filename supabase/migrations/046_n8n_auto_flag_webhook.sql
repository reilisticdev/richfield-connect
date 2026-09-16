-- 046_n8n_auto_flag_webhook.sql
--
-- Wires the real Database Webhook the n8n Auto-Flag workflow's own README
-- has always called for: posts INSERT -> n8n -> content_reports. Built as
-- a trigger function rather than a dashboard-created webhook, mirroring
-- migration 036's notify_send_notification_email() exactly - the secret
-- lives in Vault, never in the trigger definition, and the call fails open
-- (warning + skip) so a broken/unreachable n8n never blocks a post insert.
--
-- One real difference from 036: send-notification-email is a permanent
-- Supabase-hosted URL, but n8n is currently reached over a free-tier ngrok
-- tunnel whose hostname changes on every restart. The base URL is read
-- from app_config at call time instead of hardcoded, exactly like
-- ai_base_url already is - rotate it with a plain UPDATE, no migration:
--   update public.app_config set value = 'https://NEW-URL', updated_at = now()
--     where key = 'n8n_webhook_base_url';
--
-- The webhook secret itself lives in Vault as 'n8n_webhook_secret', set via
-- admin_upsert_vault_secret (same RPC and pattern as migration 036's two
-- secrets).

insert into public.app_config (key, value)
values ('n8n_webhook_base_url', 'https://headset-shrubbery-rejoicing.ngrok-free.dev')
on conflict (key) do nothing;

create or replace function public.notify_n8n_post_created()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_base_url   text;
  v_secret     text;
  v_request_id bigint;
begin
  select value into v_base_url
    from public.app_config
   where key = 'n8n_webhook_base_url';

  select decrypted_secret into v_secret
    from vault.decrypted_secrets
   where name = 'n8n_webhook_secret'
   limit 1;

  if v_base_url is null or v_secret is null then
    raise warning 'notify_n8n_post_created: app_config/vault value missing, n8n webhook skipped for post %', NEW.id;
    return null;
  end if;

  select net.http_post(
           url                  := v_base_url || '/webhook/post-created',
           body                 := jsonb_build_object(
                                     'old_record', OLD,
                                     'record',     NEW,
                                     'type',       TG_OP,
                                     'table',      TG_TABLE_NAME,
                                     'schema',     TG_TABLE_SCHEMA),
           headers              := jsonb_build_object(
                                     'Content-Type',     'application/json',
                                     'x-webhook-secret',  v_secret),
           timeout_milliseconds := 5000)
    into v_request_id;

  -- Same bookkeeping migration 036 uses for the other two webhooks, so the
  -- request is visible alongside them in supabase_functions.hooks.
  insert into supabase_functions.hooks (hook_table_id, hook_name, request_id)
  values (TG_RELID, 'n8n_auto_flag', v_request_id);

  return null;
exception
  when others then
    -- Auto-flagging is best-effort moderation, not a data constraint.
    -- Never let a broken/unreachable n8n block a real user's post.
    raise warning 'notify_n8n_post_created: % (webhook skipped)', sqlerrm;
    return null;
end;
$$;

comment on function public.notify_n8n_post_created() is
  'AFTER INSERT webhook to the n8n Auto-Flag workflow. Reads the base URL from app_config.n8n_webhook_base_url (rotates with the ngrok tunnel, same pattern as ai_base_url) and the x-webhook-secret from Vault (n8n_webhook_secret, migration 036 pattern).';

revoke all on function public.notify_n8n_post_created() from public, anon, authenticated;

drop trigger if exists trg_notify_n8n_post_created on public.posts;
create trigger trg_notify_n8n_post_created
  after insert on public.posts
  for each row execute function public.notify_n8n_post_created();
