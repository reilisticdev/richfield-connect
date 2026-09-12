CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE profiles ADD COLUMN skill_embedding VECTOR(768);
ALTER TABLE opportunities ADD COLUMN embedding VECTOR(768);

CREATE INDEX ON profiles USING ivfflat (skill_embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX ON opportunities USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

CREATE OR REPLACE FUNCTION public.match_opportunities(student_profile_id UUID)
RETURNS TABLE (opportunity_id UUID, title TEXT, similarity FLOAT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT o.id, o.title, 1 - (o.embedding <=> p.skill_embedding) AS similarity
  FROM opportunities o, profiles p
  WHERE p.id = student_profile_id
    AND o.status = 'approved'
    AND (o.programme_filter IS NULL OR o.programme_filter = (
      SELECT programme FROM education
      WHERE profile_id = student_profile_id
      ORDER BY enrolment_year DESC LIMIT 1
    ))
  ORDER BY o.embedding <=> p.skill_embedding
  LIMIT 10;
$$;

CREATE OR REPLACE VIEW career_pathways AS
SELECT e.programme, p.id AS alumni_id, p.first_name, p.last_name,
       w.title, w.organisation
FROM profiles p
JOIN education e ON e.profile_id = p.id
JOIN work_experience w ON w.profile_id = p.id
WHERE p.role = 'alumni' AND p.account_status = 'active';

-- security_invoker so this view respects the querying user's own RLS
-- instead of running with the creating role's privileges.
ALTER VIEW career_pathways SET (security_invoker = true);

REVOKE EXECUTE ON FUNCTION public.match_opportunities(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.match_opportunities(UUID) TO authenticated;

-- NOTE: 768 is a placeholder embedding dimension. It must match whichever
-- Gemini embedding model Javel picks -- confirm before relying on this in a
-- demo, and ALTER COLUMN if it needs to change (no data will exist yet).
