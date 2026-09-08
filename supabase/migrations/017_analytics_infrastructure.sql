-- Sai's analytics_draft.sql asks for signals we never built tracking for:
-- profile view counts/trends, which skills business users search for, and
-- flagged content. Adding the tables that make those real instead of guessed.

ALTER TABLE profiles ADD COLUMN last_active_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now());
-- Updated by the client on each app/web session start. Powers "monthly active users".

CREATE TABLE content_views (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  viewer_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  content_type TEXT NOT NULL CHECK (content_type IN ('profile','opportunity','company')),
  content_id UUID NOT NULL,
  viewed_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);
ALTER TABLE content_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users log their own views" ON content_views
  FOR INSERT WITH CHECK (auth.uid() = viewer_id);
-- No SELECT policy on purpose -- raw view rows are only ever read in
-- aggregate, through the SECURITY DEFINER dashboard functions in 018.

CREATE TABLE skill_search_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  business_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  skill_name TEXT NOT NULL,
  searched_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);
ALTER TABLE skill_search_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Business logs their own searches" ON skill_search_log
  FOR INSERT WITH CHECK (auth.uid() = business_id);

CREATE TABLE content_reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  content_id UUID NOT NULL,
  content_type TEXT NOT NULL CHECK (content_type IN ('post','comment','video')),
  reported_by UUID REFERENCES profiles(id) NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','reviewed','dismissed','actioned')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);
ALTER TABLE content_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users file their own reports" ON content_reports
  FOR INSERT WITH CHECK (auth.uid() = reported_by);
CREATE POLICY "Reporter views own reports" ON content_reports
  FOR SELECT USING (auth.uid() = reported_by);
CREATE POLICY "Administrators manage all reports" ON content_reports
  FOR ALL USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));
