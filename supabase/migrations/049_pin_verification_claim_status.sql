-- 049_pin_verification_claim_status.sql
--
-- "Alumni can submit their own claim" (007) is an INSERT policy checking
-- ownership only (auth.uid() = user_id) - it never constrained the status
-- column. Same class of gap as migration 047's opportunities.status fix,
-- found the same way: a live rolled-back probe.
--
-- Verified live 2026-09-16: an alumni could insert() a brand new
-- verification_claims row with status already set to 'approved', bypassing
-- the pending queue entirely. There is no UPDATE policy for alumni on this
-- table at all (confirmed by the same probe - a self-UPDATE affects 0
-- rows), so this INSERT path was the only gap, not a matching UPDATE one.
--
-- Real-world blast radius was already narrower than the opportunities bug:
-- nothing reads verification_claims.status to grant access by itself -
-- profiles.account_status is the actual gate, flipped only by
-- approve_alumni_verification()/reject_alumni_verification() (both
-- SECURITY DEFINER, both check is_admin() themselves), and profiles has no
-- client UPDATE grant on account_status at all (verified same session).
-- Still a real gap worth closing: a self-approved claim row is misleading
-- data regardless of whether it grants anything.
--
-- Fix: WITH CHECK now also requires status = 'pending' on insert. Doesn't
-- touch handle_new_user() (028/048) - that insert never sets status
-- explicitly, it relies on the column default ('pending', from 007), so it
-- already satisfies this check either way.

drop policy if exists "Alumni can submit their own claim" on public.verification_claims;
create policy "Alumni can submit their own claim"
on public.verification_claims for insert
with check (auth.uid() = user_id and status = 'pending');
