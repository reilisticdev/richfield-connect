-- Student portfolio tables + profile visibility, per the Engineering Manual
-- Steps 1-2, including the two diagnostic fixes from that review:
--   (1) base profiles table opened up so any active account is viewable
--   (2) real cross-user visibility policies on every portfolio table,
--       defaulting to visible unless the owner has explicitly restricted it.

CREATE TABLE skills (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  skill_name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE education (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  programme TEXT NOT NULL,
  campus TEXT NOT NULL,
  enrolment_year INT NOT NULL,
  graduation_year INT
);

CREATE TABLE work_experience (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  organisation TEXT NOT NULL,
  description TEXT,
  start_date DATE,
  end_date DATE
);

CREATE TABLE projects (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  github_url TEXT,
  live_url TEXT
);

CREATE TABLE certifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  issuer TEXT,
  credential_url TEXT,
  date_earned DATE
);

CREATE TABLE badges (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  issuer TEXT,
  credential_url TEXT,
  date_earned DATE
);

CREATE TABLE achievements (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  date_earned DATE
);

CREATE TABLE leadership_roles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  role_title TEXT NOT NULL,
  organisation TEXT NOT NULL,
  description TEXT
);

ALTER TABLE profiles ADD COLUMN career_interests TEXT;
ALTER TABLE profiles ADD COLUMN professional_headline TEXT;

CREATE TABLE profile_visibility (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  section TEXT NOT NULL,
  visible_to TEXT NOT NULL CHECK (visible_to IN ('public','student','alumni','business')),
  UNIQUE (profile_id, section, visible_to)
);
ALTER TABLE profile_visibility ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Owner manages own visibility settings" ON profile_visibility
  FOR ALL USING (auth.uid() = profile_id) WITH CHECK (auth.uid() = profile_id);

-- Diagnostic fix: open the base profile up so any active account is visible
-- to any signed-in user (OR's with the existing self-view policy from 001).
CREATE POLICY "Authenticated users can view active profiles" ON profiles
  FOR SELECT USING (account_status = 'active');

-- Owner-manages-own-rows on every portfolio table, plus cross-user visibility
-- driven by profile_visibility, defaulting to visible unless restricted.
DO $$
DECLARE
  tbl TEXT;
  tables TEXT[] := ARRAY['skills','education','work_experience','projects',
                          'certifications','badges','achievements','leadership_roles'];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', tbl);
    EXECUTE format($f$
      CREATE POLICY "Owner manages own rows" ON %I
        FOR ALL USING (auth.uid() = profile_id) WITH CHECK (auth.uid() = profile_id)
    $f$, tbl);
    EXECUTE format($f$
      CREATE POLICY "Others can view per visibility settings" ON %I
        FOR SELECT USING (
          auth.uid() = profile_id
          OR NOT EXISTS (
            SELECT 1 FROM profile_visibility pv
            WHERE pv.profile_id = %I.profile_id AND pv.section = %L
          )
          OR EXISTS (
            SELECT 1 FROM profile_visibility pv
            WHERE pv.profile_id = %I.profile_id AND pv.section = %L
              AND (pv.visible_to = 'public'
                   OR pv.visible_to = (SELECT role::text FROM profiles WHERE id = auth.uid()))
          )
        )
    $f$, tbl, tbl, tbl, tbl, tbl);
  END LOOP;
END $$;
