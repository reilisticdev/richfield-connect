-- 022_reject_business_account.sql
--
-- Companion to approve_business_account (021_business_approval.sql). The
-- Moderation page's reject path was calling a raw UPDATE on
-- profiles.account_status directly, with no audit trail and bypassing the
-- Database Webhook that already fires off verification_audit inserts for
-- decisions. Mirrors reject_alumni_verification's (007_alumni_verification.sql)
-- exact shape, using the business_id column approve_business_account already
-- added to verification_audit.

CREATE OR REPLACE FUNCTION public.reject_business_account(target_business_id UUID, reason TEXT DEFAULT NULL)
RETURNS void AS $$
DECLARE
  found_id UUID;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only an administrator may reject a business account.';
  END IF;

  SELECT id INTO found_id
  FROM public.profiles
  WHERE id = target_business_id AND role = 'business' AND account_status = 'pending';

  IF found_id IS NULL THEN
    RAISE EXCEPTION 'No pending business account found for id %', target_business_id;
  END IF;

  UPDATE public.profiles
  SET account_status = 'rejected'
  WHERE id = target_business_id;

  INSERT INTO public.verification_audit (business_id, admin_id, decision, reason)
  VALUES (target_business_id, auth.uid(), 'rejected', reason);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.reject_business_account(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_business_account(UUID, TEXT) TO authenticated;
