-- 036_webhook_secrets_to_vault.sql
--
-- Both database webhooks ("Welcome Email" on public.profiles and
-- "Alumni Verification Email" on public.verification_audit) were created
-- from the dashboard, which stores their HTTP headers as literal trigger
-- arguments. That left the service-role JWT and the x-webhook-secret in
-- plain text inside pg_trigger, readable by anyone with SQL access to the
-- project (`select pg_get_triggerdef(oid) from pg_trigger`).
--
-- This migration replaces those two triggers with one trigger function that
-- reads both values from Supabase Vault at call time, so the trigger
-- definition itself holds nothing sensitive. It also downgrades the gateway
-- credential: send-notification-email authenticates its callers with the
-- x-webhook-secret header and holds its own SUPABASE_SERVICE_ROLE_KEY as an
-- edge-function env secret, so the Authorization header only has to pass
-- the API gateway's JWT check. The public anon key does that. The
-- service-role key therefore leaves the database entirely rather than
-- merely being hidden.
--
-- The payload shape is byte-for-byte what supabase_functions.http_request
-- sends ({old_record, record, type, table, schema}), so the edge function
-- is untouched. The request is still logged to supabase_functions.hooks.
--
-- The secret VALUES are deliberately not in this file. After applying, set
-- them once (service-role key only; never the anon key, never a member):
--
--   POST $SUPABASE_URL/rest/v1/rpc/admin_upsert_vault_secret
--     apikey / Authorization: Bearer  <service-role key>
--     {"p_name":"edge_function_gateway_key",
--      "p_value":"<project anon key>",
--      "p_description":"Bearer for the API gateway on webhook calls"}
--   and again with
--     {"p_name":"edge_function_webhook_secret",
--      "p_value":"<the WEBHOOK_SECRET env of send-notification-email>",
--      "p_description":"x-webhook-secret checked by send-notification-email"}
--
-- Until both secrets exist the trigger logs a WARNING and skips the call:
-- a missing email must never block a signup or a verification decision.
-- Rotating either value later is a single call to the same RPC; nothing in
-- git or in the trigger changes.

-- ---------------------------------------------------------------------------
-- 1. Vault-backed trigger function
-- ---------------------------------------------------------------------------
create or replace function public.notify_send_notification_email()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_url            text := 'https://omyagiwmdabalxifyoth.supabase.co/functions/v1/send-notification-email';
  v_gateway_key    text;
  v_webhook_secret text;
  v_request_id     bigint;
begin
  select decrypted_secret into v_gateway_key
    from vault.decrypted_secrets
   where name = 'edge_function_gateway_key'
   limit 1;

  select decrypted_secret into v_webhook_secret
    from vault.decrypted_secrets
   where name = 'edge_function_webhook_secret'
   limit 1;

  if v_gateway_key is null or v_webhook_secret is null then
    raise warning 'notify_send_notification_email: vault secret(s) missing, webhook skipped for % on %.%',
      TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME;
    return null;
  end if;

  select net.http_post(
           url                  := v_url,
           body                 := jsonb_build_object(
                                     'old_record', OLD,
                                     'record',     NEW,
                                     'type',       TG_OP,
                                     'table',      TG_TABLE_NAME,
                                     'schema',     TG_TABLE_SCHEMA),
           headers              := jsonb_build_object(
                                     'Content-Type',     'application/json',
                                     'Authorization',    'Bearer ' || v_gateway_key,
                                     'x-webhook-secret', v_webhook_secret),
           timeout_milliseconds := 5000)
    into v_request_id;

  -- Same bookkeeping the dashboard webhooks did, so the request is still
  -- visible alongside the historical ones.
  insert into supabase_functions.hooks (hook_table_id, hook_name, request_id)
  values (TG_RELID, TG_NAME, v_request_id);

  return null;
exception
  when others then
    -- An outbound email is best-effort. Never let it fail the row insert.
    raise warning 'notify_send_notification_email: % (webhook skipped)', sqlerrm;
    return null;
end;
$$;

comment on function public.notify_send_notification_email() is
  'AFTER INSERT webhook to the send-notification-email edge function. Reads the gateway key and x-webhook-secret from Vault (edge_function_gateway_key, edge_function_webhook_secret) so no credential sits in the trigger definition.';

revoke all on function public.notify_send_notification_email() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. One RPC to set/rotate the secrets without a value ever touching git
-- ---------------------------------------------------------------------------
create or replace function public.admin_upsert_vault_secret(
  p_name        text,
  p_value       text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller_role text;
  v_id          uuid;
begin
  -- PostgREST puts the JWT role in request.jwt.claims; the SQL editor and
  -- migrations have no JWT and run as postgres. Everything else is refused
  -- even though the EXECUTE grant below already excludes it.
  v_caller_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_user);
  if v_caller_role not in ('service_role', 'postgres') then
    raise exception 'admin_upsert_vault_secret: service role only'
      using errcode = '42501';
  end if;

  if coalesce(p_name, '') = '' or coalesce(p_value, '') = '' then
    raise exception 'admin_upsert_vault_secret: name and value are required';
  end if;

  select id into v_id from vault.secrets where name = p_name limit 1;

  if v_id is null then
    v_id := vault.create_secret(p_value, p_name, p_description);
  else
    perform vault.update_secret(v_id, p_value, p_name, p_description);
  end if;

  return v_id;
end;
$$;

comment on function public.admin_upsert_vault_secret(text, text, text) is
  'Create or rotate a Vault secret by name. Service-role / SQL editor only. Used for edge_function_gateway_key and edge_function_webhook_secret (migration 036).';

revoke all on function public.admin_upsert_vault_secret(text, text, text) from public, anon, authenticated;
grant execute on function public.admin_upsert_vault_secret(text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Swap the triggers. The dashboard-created ones carried the secrets.
-- ---------------------------------------------------------------------------
drop trigger if exists "Welcome Email" on public.profiles;
drop trigger if exists "Alumni Verification Email" on public.verification_audit;

create trigger welcome_email_webhook
  after insert on public.profiles
  for each row execute function public.notify_send_notification_email();

create trigger alumni_verification_email_webhook
  after insert on public.verification_audit
  for each row execute function public.notify_send_notification_email();
