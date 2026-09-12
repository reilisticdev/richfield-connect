-- Gap found while checking Sai's real Opportunities.jsx against our schema:
-- her UI already expects a company name per listing, and the guidelines
-- (S2.3) require a full company profile for business users -- neither
-- existed. profiles only ever had a person's first/last name.

CREATE TABLE business_profiles (
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE PRIMARY KEY,
  company_name TEXT NOT NULL,
  industry TEXT,
  description TEXT,
  location TEXT,
  website TEXT,
  contact_email TEXT,
  contact_phone TEXT
);
ALTER TABLE business_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Owner manages own business profile" ON business_profiles
  FOR ALL USING (auth.uid() = profile_id) WITH CHECK (auth.uid() = profile_id);
CREATE POLICY "Anyone can view business profiles" ON business_profiles
  FOR SELECT USING (true);
-- Public read is intentional and safe here: company profiles are meant to be
-- discoverable (students browsing who's hiring), unlike personal profile
-- sections which stay gated by profile_visibility.
