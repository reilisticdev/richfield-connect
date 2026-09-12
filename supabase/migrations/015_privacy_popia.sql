CREATE TABLE consent_records (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  consent_type TEXT NOT NULL,
  granted_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  revoked_at TIMESTAMP WITH TIME ZONE
);
ALTER TABLE consent_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own consent records" ON consent_records
  FOR ALL USING (auth.uid() = profile_id) WITH CHECK (auth.uid() = profile_id);

CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'profile', (SELECT to_jsonb(p) FROM profiles p WHERE id = auth.uid()),
    'skills', (SELECT jsonb_agg(s) FROM skills s WHERE profile_id = auth.uid()),
    'education', (SELECT jsonb_agg(e) FROM education e WHERE profile_id = auth.uid()),
    'work_experience', (SELECT jsonb_agg(w) FROM work_experience w WHERE profile_id = auth.uid()),
    'projects', (SELECT jsonb_agg(pr) FROM projects pr WHERE profile_id = auth.uid())
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
