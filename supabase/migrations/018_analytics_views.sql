-- Built directly against Sai's requirements doc (WhatsApp, 7 Sep) and
-- analytics_draft.sql. Split into one focused function per chart rather
-- than one flat table -- a profile-views trend, a connection-growth trend,
-- an engagement count, a completeness comparison, and a top-skills list
-- are five different shapes, not one row set.

-- ============ STUDENT ============

CREATE OR REPLACE FUNCTION public.get_student_profile_views(days INT DEFAULT 30)
RETURNS TABLE (view_date DATE, view_count BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT viewed_at::date, count(*)
  FROM content_views
  WHERE content_type = 'profile' AND content_id = auth.uid()
    AND viewed_at >= now() - (days || ' days')::interval
  GROUP BY viewed_at::date ORDER BY viewed_at::date;
$$;

CREATE OR REPLACE FUNCTION public.get_student_connection_growth(days INT DEFAULT 30)
RETURNS TABLE (join_date DATE, connection_count BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT created_at::date, count(*)
  FROM connections
  WHERE status = 'accepted' AND (requester_id = auth.uid() OR addressee_id = auth.uid())
    AND created_at >= now() - (days || ' days')::interval
  GROUP BY created_at::date ORDER BY created_at::date;
$$;

CREATE OR REPLACE FUNCTION public.get_student_engagement()
RETURNS TABLE (total_posts BIGINT, total_reactions BIGINT, total_comments BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    (SELECT count(*) FROM posts WHERE author_id = auth.uid()),
    (SELECT count(*) FROM reactions r JOIN posts p ON p.id = r.post_id WHERE p.author_id = auth.uid()),
    (SELECT count(*) FROM comments c JOIN posts p ON p.id = c.post_id WHERE p.author_id = auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.get_student_completeness()
RETURNS TABLE (my_completeness_pct NUMERIC, programme_avg_completeness_pct NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE my_programme TEXT;
BEGIN
  SELECT programme INTO my_programme FROM education WHERE profile_id = auth.uid() ORDER BY enrolment_year DESC LIMIT 1;
  RETURN QUERY
  WITH scored AS (
    SELECT p.id,
      ( (EXISTS(SELECT 1 FROM skills WHERE profile_id = p.id))::int
      + (EXISTS(SELECT 1 FROM education WHERE profile_id = p.id))::int
      + (EXISTS(SELECT 1 FROM work_experience WHERE profile_id = p.id))::int
      + (EXISTS(SELECT 1 FROM projects WHERE profile_id = p.id))::int
      + (EXISTS(SELECT 1 FROM certifications WHERE profile_id = p.id))::int
      + (p.professional_headline IS NOT NULL)::int
      ) * 100.0 / 6 AS pct
    FROM profiles p
    JOIN education e ON e.profile_id = p.id
    WHERE p.role = 'student' AND e.programme = my_programme
  )
  SELECT (SELECT pct FROM scored WHERE id = auth.uid()), (SELECT avg(pct) FROM scored);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_top_searched_skills()
RETURNS TABLE (skill_name TEXT, search_count BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.skill_name, count(l.*)
  FROM skills s
  JOIN skill_search_log l ON l.skill_name = s.skill_name
  WHERE s.profile_id = auth.uid()
  GROUP BY s.skill_name ORDER BY count(l.*) DESC LIMIT 10;
$$;

-- ============ BUSINESS ============

CREATE OR REPLACE FUNCTION public.get_business_applicant_pipeline()
RETURNS TABLE (opportunity_id UUID, title TEXT, applicant_count BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT o.id, o.title, count(a.*)
  FROM opportunities o LEFT JOIN applications a ON a.opportunity_id = o.id
  WHERE o.business_id = auth.uid()
  GROUP BY o.id, o.title ORDER BY o.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_business_listing_engagement()
RETURNS TABLE (opportunity_id UUID, title TEXT, view_count BIGINT, application_count BIGINT, engagement_rate NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT o.id, o.title,
    (SELECT count(*) FROM content_views WHERE content_type = 'opportunity' AND content_id = o.id) AS view_count,
    (SELECT count(*) FROM applications WHERE opportunity_id = o.id) AS application_count,
    CASE WHEN (SELECT count(*) FROM content_views WHERE content_type = 'opportunity' AND content_id = o.id) = 0 THEN 0
      ELSE round((SELECT count(*) FROM applications WHERE opportunity_id = o.id)::numeric
        / (SELECT count(*) FROM content_views WHERE content_type = 'opportunity' AND content_id = o.id) * 100, 1)
    END AS engagement_rate
  FROM opportunities o WHERE o.business_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_business_candidate_skill_distribution()
RETURNS TABLE (programme TEXT, skill_name TEXT, candidate_count BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT e.programme, s.skill_name, count(DISTINCT a.student_id)
  FROM applications a
  JOIN opportunities o ON o.id = a.opportunity_id AND o.business_id = auth.uid()
  JOIN education e ON e.profile_id = a.student_id
  JOIN skills s ON s.profile_id = a.student_id
  GROUP BY e.programme, s.skill_name ORDER BY count(DISTINCT a.student_id) DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_business_applicant_demographics()
RETURNS TABLE (programme TEXT, enrolment_year INT, applicant_count BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT e.programme, e.enrolment_year, count(DISTINCT a.student_id)
  FROM applications a
  JOIN opportunities o ON o.id = a.opportunity_id AND o.business_id = auth.uid()
  JOIN education e ON e.profile_id = a.student_id
  GROUP BY e.programme, e.enrolment_year;
$$;

CREATE OR REPLACE FUNCTION public.get_business_profile_reach()
RETURNS TABLE (profile_view_count BIGINT, unique_viewers BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*), count(DISTINCT viewer_id)
  FROM content_views WHERE content_type = 'company' AND content_id = auth.uid();
$$;

-- ============ ADMINISTRATOR ============
-- Each self-checks is_admin() -- same pattern as approve/reject alumni
-- verification in migration 007.

CREATE OR REPLACE FUNCTION public.get_admin_user_counts()
RETURNS TABLE (role TEXT, total BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN QUERY SELECT p.role::text, count(*) FROM profiles p GROUP BY p.role;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_mau()
RETURNS BIGINT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN (SELECT count(*) FROM profiles WHERE last_active_at >= now() - interval '30 days');
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_registration_trend(days INT DEFAULT 90)
RETURNS TABLE (reg_date DATE, new_registrations BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN QUERY SELECT p.created_at::date, count(*) FROM profiles p
    WHERE p.created_at >= now() - (days || ' days')::interval
    GROUP BY p.created_at::date ORDER BY p.created_at::date;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_content_volume()
RETURNS TABLE (post_count BIGINT, video_count BIGINT, opportunity_count BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN QUERY SELECT
    (SELECT count(*) FROM posts),
    (SELECT count(*) FROM posts WHERE video_path IS NOT NULL),
    (SELECT count(*) FROM opportunities);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_flagged_content_count()
RETURNS BIGINT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN (SELECT count(*) FROM content_reports WHERE status = 'pending');
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_business_pipeline()
RETURNS TABLE (status TEXT, total BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN QUERY SELECT p.account_status::text, count(*) FROM profiles p
    WHERE p.role = 'business' GROUP BY p.account_status;
END;
$$;

-- Lock every function above down to authenticated only.
DO $$
DECLARE fn TEXT;
  fns TEXT[] := ARRAY[
    'get_student_profile_views(int)','get_student_connection_growth(int)',
    'get_student_engagement()','get_student_completeness()','get_student_top_searched_skills()',
    'get_business_applicant_pipeline()','get_business_listing_engagement()',
    'get_business_candidate_skill_distribution()','get_business_applicant_demographics()',
    'get_business_profile_reach()','get_admin_user_counts()','get_admin_mau()',
    'get_admin_registration_trend(int)','get_admin_content_volume()',
    'get_admin_flagged_content_count()','get_admin_business_pipeline()'
  ];
BEGIN
  FOREACH fn IN ARRAY fns LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%s FROM PUBLIC, anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', fn);
  END LOOP;
END $$;
