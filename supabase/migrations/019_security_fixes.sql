-- career_pathways was created without security_invoker, so Postgres ran it
-- with the creating (service) role's privileges -- bypassing RLS on
-- profiles/education/work_experience for anyone who queried it. Fixed.
ALTER VIEW career_pathways SET (security_invoker = true);

-- Cosmetic hardening: move the vector extension out of the public schema.
CREATE SCHEMA IF NOT EXISTS extensions;
ALTER EXTENSION vector SET SCHEMA extensions;
