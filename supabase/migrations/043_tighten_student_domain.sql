-- 043_tighten_student_domain.sql
--
-- enforce_student_domain() (003) matched with LIKE '%@my.richfield.ac.za' etc.
-- The leading '%' accepts any local part at all - '.@my.richfield.ac.za'
-- passed, and so did any string of dots. Switched to a regex that requires a
-- real local part (starts and ends with an alphanumeric, no bare dots) while
-- staying exactly as domain-locked as before. Deliberately NOT restricting to
-- numeric-only student numbers - nobody has confirmed every student address
-- is a student number, and rejecting a legitimate address format on stage
-- would be worse than the previous looseness. Case-insensitive (~*) since
-- GoTrue's own lowercasing behaviour on the incoming email was never
-- confirmed either way.
--
-- Unchanged: the IF still only runs for role = 'student' (or null). Alumni
-- and Corporate accept any address by design - they're gated by admin
-- approval instead - and that bypass is not what this migration touches.

create or replace function public.enforce_student_domain()
returns trigger as $$
begin
  if (new.raw_user_meta_data->>'role' = 'student' or new.raw_user_meta_data->>'role' is null) then
    if not (new.email ~* '^[a-z0-9]([a-z0-9._%+-]*[a-z0-9])?@(my\.)?(richfield|aaa)\.ac\.za$') then
      raise exception 'Registration Failed: Students must use a valid Richfield or AAA institutional email address.';
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer;
