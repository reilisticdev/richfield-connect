-- 1. Helper function: checks whether a given user id is an administrator.
--    SECURITY DEFINER so it can read profiles.role without recursing through
--    the RLS policies defined on profiles itself (used by later migrations too).
CREATE OR REPLACE FUNCTION public.is_admin(uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = uid AND role = 'administrator'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin(UUID) TO authenticated, service_role;

-- 2. Lock the `role` column down. The existing "Users can update their own
--    profile" RLS policy has no WITH CHECK and no column restriction, which
--    currently lets any authenticated user run
--      update profiles set role = 'administrator' where id = auth.uid()
--    and self-promote. RLS alone can't restrict a single column on an
--    otherwise-permitted row, so this is enforced with a trigger instead.
CREATE OR REPLACE FUNCTION public.prevent_unauthorised_role_change()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF auth.role() <> 'service_role' AND NOT public.is_admin(auth.uid()) THEN
      RAISE EXCEPTION 'Only an administrator or the service role may change a user''s role.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER lock_role_changes
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE PROCEDURE public.prevent_unauthorised_role_change();
