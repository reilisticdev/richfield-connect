-- 032_feed_engagement_moderation.sql
--
-- Backs liking, commenting on and reporting feed posts in the mobile app, and
-- removing reported content from the web Moderation page. Tested in a
-- rolled-back transaction before being applied.
--
-- 1. comments.body had no limit, so blank or arbitrarily long comments were
--    accepted. It is now 1 to 1000 characters after trimming.
-- 2. Administrators couldn't delete anyone's posts or comments (the only
--    delete right was "author manages own"), so the Moderation page's Remove
--    button could only relabel a report. They can now delete both; the
--    reactions, comments and reposts on a removed post go with it.
-- 3. One pending report per member per item, so repeated taps don't flood
--    the moderation queue.

alter table public.comments
  add constraint comments_body_length check (char_length(btrim(body)) between 1 and 1000);

create policy "Administrators remove posts" on public.posts
  for delete to authenticated using (public.is_admin(auth.uid()));

create policy "Administrators remove comments" on public.comments
  for delete to authenticated using (public.is_admin(auth.uid()));

create unique index content_reports_one_pending_per_reporter
  on public.content_reports (content_type, content_id, reported_by) where status = 'pending';
