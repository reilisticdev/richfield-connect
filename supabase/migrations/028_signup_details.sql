-- 028_signup_details.sql
--
-- The mobile register screen asked for programme, campus, years, a student
-- number (alumni) and company details (employers), then threw all of it away:
-- signUp() only sent role and name. That left three gaps:
--
--   * Students started with no `education` row, so recommend_opportunities()
--     and the programme comparison in student analytics had nothing to match
--     on until the student found the Portfolio form.
--   * Alumni could never be approved. approve_alumni_verification() needs a
--     pending verification_claims row, and nothing in the mobile or web app
--     created one, so every alumni signup stayed 'pending' for good.
--   * Employers had no business_profiles row, so their listings showed
--     "Unknown company" and the admin Moderation page showed a person's name
--     where the company should be.
--
-- Email confirmation is on, so straight after signUp() there is no session
-- and the app can't insert these rows itself under RLS. The details now
-- travel as user metadata and handle_new_user() writes them alongside the
-- profile.
--
-- Nothing written here goes beyond what the new user could write for
-- themselves once signed in: RLS already lets an owner insert their own
-- education, verification claim, business profile and consent rows.
--
-- The new part must never block a signup. An exception in this AFTER INSERT
-- trigger rolls back the auth.users row too, so a malformed year or an
-- unexpected constraint is caught, reported as a WARNING, and the account is
-- still created; the details can be added later from the Portfolio tab. The
-- administrator check that existed before still raises.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role user_role;
  v_programme text := left(nullif(btrim(meta->>'programme'), ''), 200);
  v_campus text := left(nullif(btrim(meta->>'campus'), ''), 100);
  v_student_number text := left(nullif(btrim(meta->>'student_number'), ''), 50);
  v_company_name text := left(nullif(btrim(meta->>'company_name'), ''), 200);
  v_industry text := left(nullif(btrim(meta->>'industry'), ''), 200);
  v_location text := left(nullif(btrim(meta->>'location'), ''), 200);
  v_enrolment_year int;
  v_graduation_year int;
begin
  requested_role := coalesce((meta->>'role')::user_role, 'student'::user_role);

  if requested_role = 'administrator' then
    raise exception 'Registration Failed: Administrator accounts cannot be self-registered.';
  end if;

  insert into public.profiles (id, email, first_name, last_name, role, account_status)
  values (
    new.id,
    new.email,
    meta->>'first_name',
    meta->>'last_name',
    requested_role,
    case
      when requested_role in ('business', 'alumni') then 'pending'::user_account_status
      else 'active'::user_account_status
    end
  );

  begin
    -- A year is four digits in a plausible range, or it is ignored. The
    -- pattern is checked in its own IF before the cast, because SQL doesn't
    -- promise to evaluate the left side of an AND first.
    if meta->>'enrolment_year' ~ '^[0-9]{4}$' then
      v_enrolment_year := (meta->>'enrolment_year')::int;
      if v_enrolment_year not between 1970 and 2100 then
        v_enrolment_year := null;
      end if;
    end if;
    if meta->>'graduation_year' ~ '^[0-9]{4}$' then
      v_graduation_year := (meta->>'graduation_year')::int;
      if v_graduation_year not between 1970 and 2100 then
        v_graduation_year := null;
      end if;
    end if;

    if requested_role in ('student', 'alumni')
       and v_programme is not null and v_campus is not null and v_enrolment_year is not null then
      insert into public.education (profile_id, programme, campus, enrolment_year, graduation_year)
      values (
        new.id, v_programme, v_campus, v_enrolment_year,
        case when v_graduation_year >= v_enrolment_year then v_graduation_year end
      );
    end if;

    -- The claim approve_alumni_verification() looks for. document_path stays
    -- null: nothing is uploaded at signup, and the Moderation page doesn't
    -- read it.
    if requested_role = 'alumni'
       and v_student_number is not null and v_programme is not null
       and v_campus is not null and v_graduation_year is not null then
      insert into public.verification_claims (user_id, student_number, programme, campus, graduation_year)
      values (new.id, v_student_number, v_programme, v_campus, v_graduation_year);
    end if;

    -- contact_email is deliberately left empty: business_profiles is
    -- readable by everyone, and a signup address isn't consent to publish it.
    if requested_role = 'business' and v_company_name is not null then
      insert into public.business_profiles (profile_id, company_name, industry, location)
      values (new.id, v_company_name, v_industry, v_location);
    end if;

    -- The app's register form can't be submitted without ticking its consent
    -- box and sends registration_consent = true when it is ticked. Accounts
    -- created any other way get no consent row assumed on their behalf.
    if meta->>'registration_consent' = 'true' then
      insert into public.consent_records (profile_id, consent_type)
      values (new.id, 'registration');
    end if;
  exception when others then
    raise warning 'handle_new_user: signup details for % were not saved: %', new.id, sqlerrm;
  end;

  return new;
end;
$$;

-- Unchanged from before (CREATE OR REPLACE keeps privileges); restated so the
-- intent is visible here. Only the auth.users trigger should ever run this.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
