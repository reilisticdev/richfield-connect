CREATE TABLE opportunities (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  business_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  opportunity_type TEXT NOT NULL CHECK (opportunity_type IN ('internship','learnership','part_time','graduate_vacancy')),
  required_skills TEXT[] DEFAULT '{}',
  programme_filter TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE applications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  opportunity_id UUID REFERENCES opportunities(id) ON DELETE CASCADE NOT NULL,
  student_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  status TEXT NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted','reviewed','accepted','rejected')),
  applied_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE (opportunity_id, student_id)
);

ALTER TABLE opportunities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Business manages own opportunities" ON opportunities
  FOR ALL USING (auth.uid() = business_id) WITH CHECK (auth.uid() = business_id);
CREATE POLICY "Everyone can view approved opportunities" ON opportunities
  FOR SELECT USING (status = 'approved');
CREATE POLICY "Administrators manage all opportunities" ON opportunities
  FOR ALL USING (public.is_admin(auth.uid()));

ALTER TABLE applications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Student manages own applications" ON applications
  FOR ALL USING (auth.uid() = student_id) WITH CHECK (auth.uid() = student_id);
CREATE POLICY "Business views applicants to own opportunities" ON applications
  FOR SELECT USING (
    opportunity_id IN (SELECT id FROM opportunities WHERE business_id = auth.uid())
  );
