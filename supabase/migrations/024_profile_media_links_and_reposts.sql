-- 024_profile_media_links_and_reposts.sql
--
-- Backing store for the Day-2 mobile frontend repair. Every object here
-- exists because a screen in mobile/lib now writes to it; nothing is
-- speculative.
--
--   * profiles.avatar_path / bio / *_url  -> Portfolio "Edit Details" +
--     profile picture + external links (previously hardcoded strings in
--     _socialLinksRow(), e.g. 'github.com/siphok').
--   * posts.image_path                    -> PostComposerScreen image
--     attachment. `posts` already had video_path/thumbnail_path but no
--     column for a still image, so the composer's "Add PNG image" button
--     had nowhere to write even once it was wired to a real picker.
--   * post_reposts                        -> the Repost action in
--     _reactionRow(), which was `onPressed: () {}` for every post.
--   * avatars bucket                      -> profile pictures. post-media
--     already existed but is semantically for post attachments.
--   * post-media UPDATE/DELETE policies   -> the bucket only had INSERT +
--     SELECT, so any upload with `upsert: true` (a retry after a failed
--     upload, or replacing an image) failed with a 403 that surfaced as a
--     generic StorageException.
--
-- All changes are additive. No column is dropped, no policy is removed,
-- no existing row is rewritten.

-- ---------------------------------------------------------------------
-- 1. Profile media + external links
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists avatar_path  text,
  add column if not exists bio          text,
  add column if not exists github_url   text,
  add column if not exists linkedin_url text,
  add column if not exists website_url  text;

comment on column public.profiles.avatar_path is
  'Object path inside the public `avatars` bucket, e.g. "<uid>/avatar.jpg". Stored as a path, not a URL, so the CDN origin can change without a data migration.';

-- ---------------------------------------------------------------------
-- 2. Image posts
-- ---------------------------------------------------------------------
alter table public.posts
  add column if not exists image_path text;

comment on column public.posts.image_path is
  'Object path inside the public `post-media` bucket for a still-image post. Mirrors the existing video_path convention.';

-- ---------------------------------------------------------------------
-- 3. Reposts
-- ---------------------------------------------------------------------
create table if not exists public.post_reposts (
  id         uuid        primary key default gen_random_uuid(),
  post_id    uuid        not null references public.posts(id)    on delete cascade,
  user_id    uuid        not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default timezone('utc'::text, now()),
  -- One repost per user per post. The client relies on this to make the
  -- repost toggle idempotent instead of stacking duplicate rows.
  unique (post_id, user_id)
);

create index if not exists post_reposts_post_id_idx on public.post_reposts (post_id);
create index if not exists post_reposts_user_id_idx on public.post_reposts (user_id);

alter table public.post_reposts enable row level security;

-- Counts are public (they render on every feed card), but only the owner
-- may create or remove their own repost. Mirrors the posts table's split
-- between "Anyone can view posts" and "Author manages own posts".
drop policy if exists "Anyone can view reposts" on public.post_reposts;
create policy "Anyone can view reposts"
  on public.post_reposts for select
  using (true);

drop policy if exists "Users manage their own reposts" on public.post_reposts;
create policy "Users manage their own reposts"
  on public.post_reposts for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- 4. avatars bucket
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Path convention is "<uid>/<filename>", matching the existing
-- alumni-verification-docs and post-media policies, so foldername(name)[1]
-- is the owning user's id.
drop policy if exists "Anyone can view avatars" on storage.objects;
create policy "Anyone can view avatars"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "Users upload their own avatar" on storage.objects;
create policy "Users upload their own avatar"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Users update their own avatar" on storage.objects;
create policy "Users update their own avatar"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Users delete their own avatar" on storage.objects;
create policy "Users delete their own avatar"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );

-- ---------------------------------------------------------------------
-- 5. post-media: allow replace/remove, not just first write
-- ---------------------------------------------------------------------
drop policy if exists "Users update their own post media" on storage.objects;
create policy "Users update their own post media"
  on storage.objects for update
  using (
    bucket_id = 'post-media'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Users delete their own post media" on storage.objects;
create policy "Users delete their own post media"
  on storage.objects for delete
  using (
    bucket_id = 'post-media'
    and (auth.uid())::text = (storage.foldername(name))[1]
  );
