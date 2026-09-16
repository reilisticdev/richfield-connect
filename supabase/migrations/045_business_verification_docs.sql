-- 045_business_verification_docs.sql
--
-- Business verification should require proof at signup, not just a typed
-- company name - a registration number plus a supporting document, mirroring
-- the alumni certificate pattern (007_alumni_verification.sql) exactly, so a
-- fake company can't self-attest its way to an active account. Same
-- structural limit as the alumni path: email confirmation means there's no
-- session yet at signUp() time, so only the registration number (plain text,
-- travels as signup metadata like student_number already does) can be
-- captured at signup. The document itself needs a signed-in upload step -
-- added to AccountStatusScreen's pending-approval screen, the one place a
-- pending business account is already guaranteed to land.

alter table public.business_profiles
  add column if not exists registration_number text,
  add column if not exists document_path text;

insert into storage.buckets (id, name, public)
values ('business-verification-docs', 'business-verification-docs', false)
on conflict (id) do nothing;

create policy "Business owners upload their own verification document"
on storage.objects for insert
with check (
  bucket_id = 'business-verification-docs'
  and auth.uid()::text = (storage.foldername(name))[1]
);

-- Owner can re-upload (replace) - mirrors the CV bucket's own UPDATE grant,
-- not just the alumni bucket's insert-only shape, since a business is
-- signed in when uploading and may want to fix a bad scan.
create policy "Business owners replace their own verification document"
on storage.objects for update
using (
  bucket_id = 'business-verification-docs'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'business-verification-docs'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Owners and administrators can view business verification documents"
on storage.objects for select
using (
  bucket_id = 'business-verification-docs'
  and (auth.uid()::text = (storage.foldername(name))[1] or public.is_admin(auth.uid()))
);

create policy "Business owners delete their own verification document"
on storage.objects for delete to authenticated
using (
  bucket_id = 'business-verification-docs'
  and (auth.uid())::text = (storage.foldername(name))[1]
);

-- Same POPIA-retention shape as approve/reject_alumni_verification (007):
-- the database pointer is cleared on decision. As with the alumni path, this
-- clears the column only - the storage object itself can't be deleted from
-- SQL (protect_objects_delete blocks DELETE on storage.objects for every
-- role; Storage API only), a limitation this schema already accepts for
-- alumni documents too, not a new gap introduced here.
create or replace function public.approve_business_account(target_business_id uuid)
returns void as $$
declare
  found_id uuid;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Only an administrator may approve a business account.';
  end if;

  select id into found_id
  from public.profiles
  where id = target_business_id and role = 'business' and account_status = 'pending';

  if found_id is null then
    raise exception 'No pending business account found for id %', target_business_id;
  end if;

  update public.profiles
  set account_status = 'active'
  where id = target_business_id;

  update public.business_profiles
  set document_path = null
  where profile_id = target_business_id;

  insert into public.verification_audit (business_id, admin_id, decision)
  values (target_business_id, auth.uid(), 'approved');
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.reject_business_account(target_business_id uuid, reason text default null)
returns void as $$
declare
  found_id uuid;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Only an administrator may reject a business account.';
  end if;

  select id into found_id
  from public.profiles
  where id = target_business_id and role = 'business' and account_status = 'pending';

  if found_id is null then
    raise exception 'No pending business account found for id %', target_business_id;
  end if;

  update public.profiles
  set account_status = 'rejected'
  where id = target_business_id;

  update public.business_profiles
  set document_path = null
  where profile_id = target_business_id;

  insert into public.verification_audit (business_id, admin_id, decision, reason)
  values (target_business_id, auth.uid(), 'rejected', reason);
end;
$$ language plpgsql security definer set search_path = public;

-- handle_new_user() (028): add registration_number to the business_profiles
-- insert from signup metadata, same shape as every other field here.
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
  v_registration_number text := left(nullif(btrim(meta->>'registration_number'), ''), 50);
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
    -- registration_number travels the same way student_number does for
    -- alumni; document_path stays null for the same reason as the alumni
    -- claim above - it needs a signed-in upload step, added separately.
    if requested_role = 'business' and v_company_name is not null then
      insert into public.business_profiles (profile_id, company_name, industry, location, registration_number)
      values (new.id, v_company_name, v_industry, v_location, v_registration_number);
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

revoke execute on function public.handle_new_user() from public, anon, authenticated;
