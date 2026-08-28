-- 1. Create a function to check email domains for students
CREATE OR REPLACE FUNCTION public.enforce_student_domain()
RETURNS TRIGGER AS $$
BEGIN
  -- If the user is registering as a student (or defaults to student)
  IF (new.raw_user_meta_data->>'role' = 'student' OR new.raw_user_meta_data->>'role' IS NULL) THEN
    -- Check if the email ends with one of the approved domains
    IF NOT (
      new.email LIKE '%@my.richfield.ac.za' OR 
      new.email LIKE '%@richfield.ac.za' OR 
      new.email LIKE '%@my.aaa.ac.za' OR 
      new.email LIKE '%@aaa.ac.za'
    ) THEN
      RAISE EXCEPTION 'Registration Failed: Students must use a valid Richfield or AAA institutional email address.';
    END IF;
  END IF;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Attach the trigger to run BEFORE the user is created
CREATE TRIGGER check_student_domain_before_insert
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.enforce_student_domain();