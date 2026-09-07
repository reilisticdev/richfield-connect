-- ============================================================
-- RICHFIELD CONNECT
-- STEP 6: ANALYTICS SQL DRAFT
-- ============================================================
--
-- These are draft analytics queries based on the hackathon
-- guidelines.
--
-- IMPORTANT:
-- These queries are drafts for Reilyn to review and implement.
-- Table/column names must be mapped to the project's actual
-- database schema before they are applied.
--
-- DO NOT create new tables or run these queries yet.
-- ============================================================


-- ============================================================
-- 1. STUDENT ANALYTICS DASHBOARD
-- ============================================================
--
-- The Student dashboard must show:
-- 1. Profile view count and trends over time
-- 2. Connection growth
-- 3. Post and video engagement metrics
-- 4. Profile completeness compared with peers in the same
--    programme
-- 5. Which of the student's skills are most searched for
--    by business users
--
-- Expected visualisations:
-- - Line chart: profile views over time
-- - Line/bar chart: connection growth
-- - Bar chart: post/video engagement
-- - Comparison indicator: student's profile completeness
--   vs programme average
-- - Bar chart: most searched skills


SELECT
    student_id,
    profile_view_date,
    profile_view_count,
    connection_count,
    post_engagement_count,
    video_engagement_count,
    profile_completeness_percentage,
    programme_average_completeness_percentage,
    skill_name,
    business_skill_search_count
FROM [ACTUAL_STUDENT_ANALYTICS_SOURCE]
WHERE student_id = :student_id
ORDER BY profile_view_date;


-- ============================================================
-- 2. BUSINESS USER ANALYTICS DASHBOARD
-- ============================================================
--
-- The Business dashboard must show:
-- 1. Total applicant pipeline per posted opportunity
-- 2. Engagement rate on job listings
-- 3. Candidate skill distribution across Richfield programmes
-- 4. Demographic breakdown of applicants by programme and
--    year of study
-- 5. Overall reach and visibility statistics for the
--    company profile
--
-- Expected visualisations:
-- - Bar chart: applicants per opportunity
-- - Bar/line chart: job listing engagement rate
-- - Bar chart: candidate skills by programme
-- - Stacked/grouped bar chart: applicants by programme/year
-- - Stat cards + chart: company reach and profile visibility


SELECT
    business_id,
    opportunity_id,
    opportunity_title,
    applicant_count,
    listing_view_count,
    listing_engagement_count,
    listing_engagement_rate,
    candidate_skill,
    candidate_skill_count,
    programme,
    applicant_count_by_programme,
    year_of_study,
    applicant_count_by_year,
    company_profile_views,
    company_profile_reach
FROM [ACTUAL_BUSINESS_ANALYTICS_SOURCE]
WHERE business_id = :business_id
ORDER BY opportunity_id;


-- ============================================================
-- 3. ADMINISTRATOR ANALYTICS DASHBOARD
-- ============================================================
--
-- The Administrator dashboard must show:
-- 1. Total registered users by type
-- 2. Monthly active users
-- 3. New registrations over time
-- 4. Content volume:
--      - Posts
--      - Videos
--      - Opportunities
-- 5. Flagged content count
-- 6. Business user approval pipeline status
--
-- Expected visualisations:
-- - Bar chart: registered users by type
-- - Line chart: monthly active users
-- - Line chart: new registrations over time
-- - Bar chart: content volume
-- - Stat card/indicator: flagged content
-- - Bar/donut chart: business approval pipeline


SELECT
    user_type,
    total_registered_users,
    month,
    monthly_active_users,
    new_registration_count,
    post_count,
    video_count,
    opportunity_count,
    flagged_content_count,
    pending_business_count,
    approved_business_count,
    rejected_business_count
FROM [ACTUAL_ADMIN_ANALYTICS_SOURCE]
ORDER BY month;