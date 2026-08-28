-- 1. Account status: business and alumni signups need an approval/verification
--    step before they get full access (hackathon guidelines §2.1). Students
--    default to active since the domain trigger already gates their signup.
CREATE TYPE user_account_status AS ENUM ('pending', 'active', 'suspended', 'rejected');

ALTER TABLE profiles
  ADD COLUMN account_status user_account_status NOT NULL DEFAULT 'active';

-- 2. Restrict which roles a client can self-assign at signup. Previously
--    handle_new_user() trusted raw_user_meta_data->>'role' verbatim, so
--    signUp({ data: { role: 'administrator' } }) minted an admin account with
--    no approval step at all. Administrator accounts must never be
--    self-registerable (§2.1) -- that path is rejected outright here; the
--    only legitimate way to create one is the out-of-band service-role
--    provisioning script.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  requested_role user_role;
BEGIN
  requested_role := COALESCE((new.raw_user_meta_data->>'role')::user_role, 'student'::user_role);

  IF requested_role = 'administrator' THEN
    RAISE EXCEPTION 'Registration Failed: Administrator accounts cannot be self-registered.';
  END IF;

  INSERT INTO public.profiles (id, email, first_name, last_name, role, account_status)
  VALUES (
    new.id,
    new.email,
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name',
    requested_role,
    CASE
      WHEN requested_role IN ('business', 'alumni') THEN 'pending'::user_account_status
      ELSE 'active'::user_account_status
    END
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
