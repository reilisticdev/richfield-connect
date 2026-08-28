-- Alumni identity verification ("Claim & Review"): the alumnus registers with
-- a personal email through Supabase Auth (handled_new_user sets their
-- profile to account_status = 'pending'), then submits a claim plus one
-- supporting document. An administrator reviews and approves/rejects through
-- a SECURITY DEFINER function, never a direct client update -- so the role
-- transition is always server-enforced. The document is purged on decision
-- since it has served its purpose (POPIA retention-limitation).

-- 1. Claims submitted by alumni awaiting verification
CREATE TYPE verification_claim_status AS ENUM ('pending', 'approved', 'rejected');

CREATE TABLE verification_claims (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  student_number TEXT NOT NULL,
  programme TEXT NOT NULL,
  campus TEXT NOT NULL,
  graduation_year INT NOT NULL,
  document_path TEXT,
  status verification_claim_status NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE verification_claims ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Alumni can view their own claim"
ON verification_claims FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Alumni can submit their own claim"
ON verification_claims FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Administrators can view all claims"
ON verification_claims FOR SELECT
USING (public.is_admin(auth.uid()));

-- 2. Immutable audit trail of admin decisions
CREATE TABLE verification_audit (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  claim_id UUID REFERENCES verification_claims(id) ON DELETE CASCADE NOT NULL,
  admin_id UUID REFERENCES profiles(id) NOT NULL,
  decision verification_claim_status NOT NULL,
  reason TEXT,
  decided_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE verification_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Administrators can view the audit trail"
ON verification_audit FOR SELECT
USING (public.is_admin(auth.uid()));

-- 3. Private storage bucket for supporting documents.
--    Expected upload path convention: {auth.uid()}/<filename>, so the first
--    path segment is checked against the uploader's own id.
INSERT INTO storage.buckets (id, name, public)
VALUES ('alumni-verification-docs', 'alumni-verification-docs', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Alumni can upload their own verification document"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'alumni-verification-docs'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Owners and administrators can view verification documents"
ON storage.objects FOR SELECT
USING (
  bucket_id = 'alumni-verification-docs'
  AND (auth.uid()::text = (storage.foldername(name))[1] OR public.is_admin(auth.uid()))
);

-- 4. Decision functions -- the only path that may approve/reject a claim and
--    flip the applicant's account_status. Both require the caller to already
--    be an administrator, independent of any RLS on the tables they touch.
CREATE OR REPLACE FUNCTION public.approve_alumni_verification(claim_id UUID)
RETURNS void AS $$
DECLARE
  target_user_id UUID;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only an administrator may approve a verification claim.';
  END IF;

  SELECT user_id INTO target_user_id
  FROM public.verification_claims
  WHERE id = claim_id AND status = 'pending';

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'No pending claim found for id %', claim_id;
  END IF;

  UPDATE public.verification_claims
  SET status = 'approved', document_path = NULL
  WHERE id = claim_id;

  UPDATE public.profiles
  SET account_status = 'active'
  WHERE id = target_user_id;

  INSERT INTO public.verification_audit (claim_id, admin_id, decision)
  VALUES (claim_id, auth.uid(), 'approved');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.reject_alumni_verification(claim_id UUID, reason TEXT)
RETURNS void AS $$
DECLARE
  target_user_id UUID;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only an administrator may reject a verification claim.';
  END IF;

  SELECT user_id INTO target_user_id
  FROM public.verification_claims
  WHERE id = claim_id AND status = 'pending';

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'No pending claim found for id %', claim_id;
  END IF;

  UPDATE public.verification_claims
  SET status = 'rejected', document_path = NULL
  WHERE id = claim_id;

  UPDATE public.profiles
  SET account_status = 'rejected'
  WHERE id = target_user_id;

  INSERT INTO public.verification_audit (claim_id, admin_id, decision, reason)
  VALUES (claim_id, auth.uid(), 'rejected', reason);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.approve_alumni_verification(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_alumni_verification(UUID, TEXT) TO authenticated;
