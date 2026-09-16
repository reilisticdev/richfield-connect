-- 050_message_reports.sql
--
-- Lets a member report a direct message. Two things were in the way:
--
-- 1. content_reports_content_type_check only allowed 'post', 'comment' and
--    'video', so the insert was rejected outright.
--
-- 2. An administrator cannot read the reported message. The `messages`
--    SELECT policy is sender-or-recipient only and there is no admin
--    override (checked live) - by design, admins are not meant to browse
--    everyone's DMs. So a report carrying only content_id would point at a
--    row the reviewer is unable to open, making the queue useless for
--    messages specifically.
--
-- content_snippet therefore stores the reported message's text as captured
-- at report time. That is the evidence the reviewer acts on, and it is also
-- the only thing they get: it does not grant any wider access to the
-- conversation, and the rest of the thread stays unreadable to them.
--
-- Deliberately NOT added to export_my_data(): a snippet belongs to the
-- other participant's message, and the reporter's own export should not
-- become a way to retain someone else's words.
--
-- No RLS change is needed. "Users file their own reports" already allows
-- the insert (with check auth.uid() = reported_by) and "Administrators
-- manage all reports" already covers review.

alter table public.content_reports
  drop constraint if exists content_reports_content_type_check;

alter table public.content_reports
  add constraint content_reports_content_type_check
  check (content_type = any (array['post'::text, 'comment'::text, 'video'::text, 'message'::text]));

alter table public.content_reports
  add column if not exists content_snippet text;

-- A report is evidence, not a transcript: cap it so a snippet cannot be
-- used to mirror an entire conversation into a table admins can read.
alter table public.content_reports
  drop constraint if exists content_reports_snippet_length_check;

alter table public.content_reports
  add constraint content_reports_snippet_length_check
  check (content_snippet is null or length(content_snippet) <= 2000);

comment on column public.content_reports.content_snippet is
  'Text of the reported content captured at report time. Required for message reports, which reviewers cannot read from the messages table.';
