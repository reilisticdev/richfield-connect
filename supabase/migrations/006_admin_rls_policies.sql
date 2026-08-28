-- Administrators need to view and manage every profile (approve business
-- users, verify alumni, suspend accounts -- §2.2) but the only policies that
-- existed so far were "view/update your own row". These are additional
-- PERMISSIVE policies, so they OR together with the existing self-access
-- policies rather than replacing them.
--
-- Note: even for an administrator, changing profiles.role through these
-- policies still passes through the lock_role_changes trigger from
-- 004_role_change_lockdown.sql -- is_admin() must be true for the change to
-- be allowed, so this does not reopen the self-escalation gap.

CREATE POLICY "Administrators can view all profiles"
ON profiles FOR SELECT
USING (public.is_admin(auth.uid()));

CREATE POLICY "Administrators can update all profiles"
ON profiles FOR UPDATE
USING (public.is_admin(auth.uid()));
