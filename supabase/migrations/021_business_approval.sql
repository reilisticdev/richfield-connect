-- 021_business_approval.sql
--
-- Closes the gap send-notification-email/index.ts flagged in its own
-- comments: business account approval had no audit-table-backed RPC, so
-- the only way to activate a pending business was a bare UPDATE with no
-- email and no audit trail.
--
-- Generalizes verification_audit (previously alumni-only, hard-FK'd via
-- claim_id) to also cover business decisions via a new nullable
-- business_id column, so the Database Webhook already configured on this
-- table's INSERT (Dashboard > Database > Webhooks) fires for business
-- approvals too, with no new webhook to configure. Exactly one of
-- claim_id/business_id must be set per row.
--
-- approve_business_account() copies approve_alumni_verification()'s
-- (007_alumni_verification.sql) exact pattern: admin-only via
-- SECURITY DEFINER + an explicit is_admin() check, target-row lookup
-- doubling as the idempotency guard, audit insert last with admin_id
-- always from auth.uid().
--
-- Companion change (separate PR concern, same branch): the edge function
-- needs updating to branch on claim_id vs business_id when handling a
-- verification_audit INSERT — see supabase/functions/send-notification-email/index.ts.

ALTER TABLE public.verification_audit
  ALTER COLUMN claim_id DROP NOT NULL,
  ADD COLUMN business_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD CONSTRAINT verification_audit_exactly_one_target
    CHECK (num_nonnulls(claim_id, business_id) = 1);

CREATE OR REPLACE FUNCTION public.approve_business_account(target_business_id UUID)
RETURNS void AS $$
DECLARE
  found_id UUID;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only an administrator may approve a business account.';
  END IF;

  SELECT id INTO found_id
  FROM public.profiles
  WHERE id = target_business_id AND role = 'business' AND account_status = 'pending';

  IF found_id IS NULL THEN
    RAISE EXCEPTION 'No pending business account found for id %', target_business_id;
  END IF;

  UPDATE public.profiles
  SET account_status = 'active'
  WHERE id = target_business_id;

  INSERT INTO public.verification_audit (business_id, admin_id, decision)
  VALUES (target_business_id, auth.uid(), 'approved');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.approve_business_account(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_business_account(UUID) TO authenticated;
