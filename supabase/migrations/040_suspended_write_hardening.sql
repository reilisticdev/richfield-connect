-- 040_suspended_write_hardening.sql
--
-- admin_set_account_status() (migration 033) bans the auth user and ends
-- their sessions, but an access token that was already issued keeps
-- working until it expires (up to an hour). The mobile app shows its
-- suspended screen for that window; the raw REST API did not. posts,
-- comments, reactions, messages and connections all had bare
-- `auth.uid() = author_id`-style policies with no account_status check
-- (verified live in pg_policies, 2026-09-12), so a suspended member with a
-- still-valid token could keep writing through PostgREST. applications
-- has carried the check since migration 026 and is left alone.
--
-- Every policy keeps its name, its role list and its USING clause; only
-- WITH CHECK gains the active-account condition, written the way 026
-- wrote it for applications. For the three FOR ALL policies (012) that
-- means INSERT and UPDATE are refused while suspended - WITH CHECK is
-- evaluated against the row an UPDATE produces - while the member can
-- still read and delete their own content.
--
-- Verified in a rolled-back transaction before applying: with the
-- student's account_status set to 'suspended', every insert below and an
-- UPDATE of their own post passed RLS before this migration and fail with
-- 42501 after it; with the account 'active' all six still pass.

-- ---------------------------------------------------------------------
-- posts / comments / reactions: FOR ALL policies from 012_social_schema
-- ---------------------------------------------------------------------
drop policy if exists "Author manages own posts" on public.posts;
create policy "Author manages own posts"
  on public.posts for all
  using (auth.uid() = author_id)
  with check (
    auth.uid() = author_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.account_status = 'active'
    )
  );

drop policy if exists "Author manages own comments" on public.comments;
create policy "Author manages own comments"
  on public.comments for all
  using (auth.uid() = author_id)
  with check (
    auth.uid() = author_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.account_status = 'active'
    )
  );

drop policy if exists "Author manages own reactions" on public.reactions;
create policy "Author manages own reactions"
  on public.reactions for all
  using (auth.uid() = author_id)
  with check (
    auth.uid() = author_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.account_status = 'active'
    )
  );

-- ---------------------------------------------------------------------
-- messages: INSERT policy from 012_social_schema
-- ---------------------------------------------------------------------
drop policy if exists "Accepted connections can send messages" on public.messages;
create policy "Accepted connections can send messages"
  on public.messages for insert
  with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.account_status = 'active'
    )
    and exists (
      select 1 from public.connections c
      where c.status = 'accepted'
        and ((c.requester_id = messages.sender_id and c.addressee_id = messages.recipient_id)
          or (c.requester_id = messages.recipient_id and c.addressee_id = messages.sender_id))
    )
  );

-- ---------------------------------------------------------------------
-- connections: INSERT policy from 026_messaging_notifications_matching
-- ---------------------------------------------------------------------
drop policy if exists "Users send connection requests" on public.connections;
create policy "Users send connection requests"
  on public.connections for insert
  with check (
    auth.uid() = requester_id
    and requester_id <> addressee_id
    and status = 'pending'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.account_status = 'active'
    )
  );
