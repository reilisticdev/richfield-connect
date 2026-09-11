-- 026_messaging_notifications_matching.sql
--
-- Backing store for the mobile Messages tab, the real Network screen,
-- in-app real-time notifications and skill/programme job matching. Written
-- against the hackathon guidelines rather than the checklist shorthand:
--
--   2.4  "Users can send, accept, decline, and manage connection requests"
--        "Direct messaging, connected users can send private messages"
--   2.5  "students receive notifications for events relevant to their
--        programme or interests"
--   2.8  real-time notifications for "connection requests, new messages,
--        opportunity matches, administrator announcements, and activity on
--        a user's posts", via WebSockets or push - polling not accepted -
--        and smart job matching that automatically surfaces a newly
--        approved listing to students whose skills and programme align.
--
-- Nothing is dropped except one broken policy (section 1), and no existing
-- row is rewritten.

-- ---------------------------------------------------------------------
-- 1. connections: the policy that made messaging unreachable
-- ---------------------------------------------------------------------
-- The table had a single FOR ALL policy:
--     USING      (auth.uid() = requester_id OR auth.uid() = addressee_id)
--     WITH CHECK (auth.uid() = requester_id)
-- WITH CHECK is applied to the row an UPDATE produces, so the person who
-- RECEIVED a request could never accept it (they are not requester_id),
-- while the person who SENT it could mark their own request 'accepted'.
-- messages' RLS requires an accepted connection, so this one policy meant
-- no two users could ever message each other through the app.
drop policy if exists "Participants manage their connection" on public.connections;

drop policy if exists "Participants view their connections" on public.connections;
create policy "Participants view their connections"
  on public.connections for select
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

drop policy if exists "Users send connection requests" on public.connections;
create policy "Users send connection requests"
  on public.connections for insert
  with check (
    auth.uid() = requester_id
    and requester_id <> addressee_id
    and status = 'pending'
  );

drop policy if exists "Addressee responds to a connection request" on public.connections;
create policy "Addressee responds to a connection request"
  on public.connections for update
  using (auth.uid() = addressee_id)
  with check (auth.uid() = addressee_id and status in ('accepted', 'declined'));

drop policy if exists "Participants remove a connection" on public.connections;
create policy "Participants remove a connection"
  on public.connections for delete
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- Clients only ever change `status`. Without this the addressee - who can
-- now UPDATE - could also rewrite requester_id and manufacture an accepted
-- connection (and so a private messaging channel) with anyone.
revoke update on public.connections from anon, authenticated;
grant update (status) on public.connections to authenticated;

-- One connection per pair of people, whichever of them asked first. The
-- existing unique (requester_id, addressee_id) still allowed A->B and B->A.
create unique index if not exists connections_pair_unique_idx
  on public.connections (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index if not exists connections_addressee_status_idx
  on public.connections (addressee_id, status);
create index if not exists connections_requester_status_idx
  on public.connections (requester_id, status);

-- ---------------------------------------------------------------------
-- 2. messages: read receipts may change read_at and nothing else
-- ---------------------------------------------------------------------
-- The UPDATE policy let a recipient update any column of a message they
-- received, including body and sender_id.
revoke update on public.messages from anon, authenticated;
grant update (read_at) on public.messages to authenticated;

drop policy if exists "Recipient marks message read" on public.messages;
create policy "Recipient marks message read"
  on public.messages for update
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

alter table public.messages drop constraint if exists messages_body_length;
alter table public.messages add constraint messages_body_length
  check (char_length(btrim(body)) between 1 and 4000);

create index if not exists messages_pair_sent_idx
  on public.messages (least(sender_id, recipient_id), greatest(sender_id, recipient_id), sent_at desc);
create index if not exists messages_unread_idx
  on public.messages (recipient_id, sender_id) where read_at is null;

-- ---------------------------------------------------------------------
-- 3. Inbox: one row per accepted connection, newest conversation first
-- ---------------------------------------------------------------------
-- SECURITY INVOKER: every table read here is filtered by the caller's own
-- RLS, so this can't return a conversation the caller couldn't already see.
create or replace function public.get_my_conversations()
returns table (
  partner_id uuid,
  connection_id uuid,
  first_name text,
  last_name text,
  role text,
  professional_headline text,
  avatar_path text,
  last_message text,
  last_sent_at timestamptz,
  last_from_me boolean,
  unread_count bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with partners as (
    select c.id as conn_id,
           case when c.requester_id = auth.uid() then c.addressee_id else c.requester_id end as other_id
    from public.connections c
    where c.status = 'accepted'
      and auth.uid() in (c.requester_id, c.addressee_id)
  )
  select pt.other_id,
         pt.conn_id,
         pr.first_name,
         pr.last_name,
         pr.role::text,
         pr.professional_headline,
         pr.avatar_path,
         lm.body,
         lm.sent_at,
         lm.sender_id = auth.uid(),
         (select count(*)
            from public.messages u
           where u.sender_id = pt.other_id
             and u.recipient_id = auth.uid()
             and u.read_at is null)
  from partners pt
  join public.profiles pr on pr.id = pt.other_id
  left join lateral (
    select m.body, m.sent_at, m.sender_id
    from public.messages m
    where (m.sender_id = auth.uid() and m.recipient_id = pt.other_id)
       or (m.sender_id = pt.other_id and m.recipient_id = auth.uid())
    order by m.sent_at desc
    limit 1
  ) lm on true
  order by lm.sent_at desc nulls last, pr.first_name;
$$;

revoke execute on function public.get_my_conversations() from public, anon;
grant execute on function public.get_my_conversations() to authenticated;

-- ---------------------------------------------------------------------
-- 4. People you may know: shared skills and programme first
-- ---------------------------------------------------------------------
-- SECURITY INVOKER again, so another user's skills and education only count
-- toward a suggestion when their profile_visibility settings let the caller
-- see those sections.
create or replace function public.get_connection_suggestions(max_results integer default 20)
returns table (
  suggested_id uuid,
  first_name text,
  last_name text,
  role text,
  professional_headline text,
  avatar_path text,
  shared_skills integer,
  same_programme boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  with my_skills as (
    select distinct lower(btrim(s.skill_name)) as name
    from public.skills s
    where s.profile_id = auth.uid()
  ),
  my_programme as (
    select lower(btrim(e.programme)) as name
    from public.education e
    where e.profile_id = auth.uid()
    order by e.enrolment_year desc
    limit 1
  )
  select pr.id,
         pr.first_name,
         pr.last_name,
         pr.role::text,
         pr.professional_headline,
         pr.avatar_path,
         (select count(distinct lower(btrim(sk.skill_name)))::integer
            from public.skills sk
           where sk.profile_id = pr.id
             and lower(btrim(sk.skill_name)) in (select name from my_skills)),
         exists (
           select 1 from public.education ed
           where ed.profile_id = pr.id
             and lower(btrim(ed.programme)) = (select name from my_programme)
         )
  from public.profiles pr
  where pr.id <> auth.uid()
    and pr.account_status = 'active'
    and pr.role <> 'administrator'
    and not exists (
      select 1 from public.connections c
      where (c.requester_id = auth.uid() and c.addressee_id = pr.id)
         or (c.addressee_id = auth.uid() and c.requester_id = pr.id)
    )
  order by 8 desc, 7 desc, pr.created_at desc
  limit greatest(1, least(coalesce(max_results, 20), 50));
$$;

revoke execute on function public.get_connection_suggestions(integer) from public, anon;
grant execute on function public.get_connection_suggestions(integer) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Smart job matching: skills + programme, explainable
-- ---------------------------------------------------------------------
-- match_opportunities() ranks by pgvector distance, but no profile or
-- opportunity has an embedding (nothing generates them), so it cannot rank
-- anything today. This scores on data that does exist - overlap between
-- the student's skills and required_skills, plus programme alignment - and
-- returns WHICH skills matched, so the app can say why a role was
-- recommended. A listing with no required skills and no programme filter
-- carries no signal and is never recommended (guidelines 2.8: matching
-- logic, "not a generic broadcast").
create or replace function public.recommend_opportunities(max_results integer default 10)
returns table (
  opportunity_id uuid,
  title text,
  opportunity_type text,
  matched_skills text[],
  required_skill_count integer,
  programme_match boolean,
  match_score numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  with my_skills as (
    select distinct lower(btrim(s.skill_name)) as name
    from public.skills s
    where s.profile_id = auth.uid()
  ),
  my_programme as (
    select lower(btrim(e.programme)) as name
    from public.education e
    where e.profile_id = auth.uid()
    order by e.enrolment_year desc
    limit 1
  ),
  scored as (
    select o.id as opp_id,
           o.title as opp_title,
           o.opportunity_type as opp_type,
           array(
             select distinct rs
             from unnest(coalesce(o.required_skills, '{}'::text[])) rs
             where lower(btrim(rs)) in (select name from my_skills)
           ) as matched,
           coalesce(cardinality(o.required_skills), 0) as req_count,
           o.programme_filter is not null as has_filter,
           coalesce(lower(btrim(o.programme_filter)) = (select name from my_programme), false) as prog_match
    from public.opportunities o
    where o.status = 'approved'
  )
  select opp_id,
         opp_title,
         opp_type,
         matched,
         req_count,
         prog_match,
         round(
           (case when req_count > 0 then cardinality(matched)::numeric / req_count else 0 end) * 0.8
           + (case when prog_match then 0.2 else 0 end),
           3)
  from scored
  where (not has_filter or prog_match)
    and (cardinality(matched) > 0 or prog_match)
  order by 7 desc, opp_title
  limit greatest(1, least(coalesce(max_results, 10), 50));
$$;

revoke execute on function public.recommend_opportunities(integer) from public, anon;
grant execute on function public.recommend_opportunities(integer) to authenticated;

-- ---------------------------------------------------------------------
-- 6. notifications: new types, read_at-only updates, realtime-friendly index
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'new_message',
    'new_connection',
    'connection_accepted',
    'opportunity_match',
    'admin_announcement',
    'event_published',
    'post_activity'
  ));

revoke update on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

drop policy if exists "Users mark own notifications read" on public.notifications;
create policy "Users mark own notifications read"
  on public.notifications for update
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

create index if not exists notifications_recipient_created_idx
  on public.notifications (recipient_id, created_at desc);

-- Internal helper for the triggers below. Not callable by clients: it would
-- otherwise return the name of any profile id, active or not.
create or replace function public.profile_display_name(uid uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
    'A Richfield member')
  from public.profiles p
  where p.id = uid;
$$;

revoke execute on function public.profile_display_name(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 7. Notification triggers
-- ---------------------------------------------------------------------
-- All SECURITY DEFINER: notifications has no client INSERT policy, by
-- design - a client must never be able to write a notification into
-- someone else's feed. Every payload carries 'title' and 'body' so the app
-- renders all types the same way; the ids alongside drive navigation.
-- broadcast_announcement() (migration 023) writes 'title' and 'message'.

-- 7a. New message -> recipient
create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (recipient_id, type, payload)
  values (new.recipient_id, 'new_message', jsonb_build_object(
    'title', public.profile_display_name(new.sender_id),
    'body', left(new.body, 140),
    'sender_id', new.sender_id,
    'message_id', new.id));
  return new;
end;
$$;

drop trigger if exists messages_notify_recipient on public.messages;
create trigger messages_notify_recipient
  after insert on public.messages
  for each row execute function public.notify_new_message();

-- 7b. Connection request -> addressee; accepted -> requester
create or replace function public.notify_connection_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (recipient_id, type, payload)
    values (new.addressee_id, 'new_connection', jsonb_build_object(
      'title', public.profile_display_name(new.requester_id),
      'body', 'wants to connect with you',
      'actor_id', new.requester_id,
      'connection_id', new.id));
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status is distinct from 'accepted' then
    insert into public.notifications (recipient_id, type, payload)
    values (new.requester_id, 'connection_accepted', jsonb_build_object(
      'title', public.profile_display_name(new.addressee_id),
      'body', 'accepted your connection request',
      'actor_id', new.addressee_id,
      'connection_id', new.id));
  end if;
  return new;
end;
$$;

drop trigger if exists connections_notify on public.connections;
create trigger connections_notify
  after insert or update of status on public.connections
  for each row execute function public.notify_connection_change();

-- 7c. Opportunity approved -> students and alumni whose skills/programme align.
-- Fires when the admin web panel flips status to 'approved'
-- (web/src/pages/Opportunities.jsx updates the row directly).
create or replace function public.notify_opportunity_matches()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'approved' or (tg_op = 'UPDATE' and old.status = 'approved') then
    return new;
  end if;

  insert into public.notifications (recipient_id, type, payload)
  select p.id,
         'opportunity_match',
         jsonb_build_object(
           'title', new.title,
           'body', case
                     when cardinality(ms.matched) > 0
                       then 'Matches your skills: ' || array_to_string(ms.matched, ', ')
                     else 'Open to students in your programme'
                   end,
           'opportunity_id', new.id,
           'matched_skills', to_jsonb(ms.matched))
  from public.profiles p
  cross join lateral (
    select array(
      select distinct rs
      from unnest(coalesce(new.required_skills, '{}'::text[])) rs
      where exists (
        select 1 from public.skills s
        where s.profile_id = p.id
          and lower(btrim(s.skill_name)) = lower(btrim(rs))
      )
    ) as matched
  ) ms
  cross join lateral (
    select new.programme_filter is not null and exists (
      select 1 from public.education e
      where e.profile_id = p.id
        and lower(btrim(e.programme)) = lower(btrim(new.programme_filter))
    ) as same_programme
  ) pg
  where p.role in ('student', 'alumni')
    and p.account_status = 'active'
    and (new.programme_filter is null or pg.same_programme)
    and (cardinality(ms.matched) > 0 or pg.same_programme);

  return new;
end;
$$;

drop trigger if exists opportunities_notify_matches on public.opportunities;
create trigger opportunities_notify_matches
  after insert or update of status on public.opportunities
  for each row execute function public.notify_opportunity_matches();

-- 7d. Event published -> students and alumni in the event's programme (or all)
create or replace function public.notify_event_published()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'published' or (tg_op = 'UPDATE' and old.status = 'published') then
    return new;
  end if;

  insert into public.notifications (recipient_id, type, payload)
  select p.id,
         'event_published',
         jsonb_build_object(
           'title', new.title,
           'body', to_char(new.event_date at time zone 'Africa/Johannesburg', 'DD Mon YYYY, HH24:MI')
                   || coalesce(' - ' || new.location, ''),
           'event_id', new.id)
  from public.profiles p
  where p.account_status = 'active'
    and p.role in ('student', 'alumni')
    and (
      new.programme_filter is null
      or exists (
        select 1 from public.education e
        where e.profile_id = p.id
          and lower(btrim(e.programme)) = lower(btrim(new.programme_filter))
      )
    );

  return new;
end;
$$;

drop trigger if exists events_notify_published on public.events;
create trigger events_notify_published
  after insert or update of status on public.events
  for each row execute function public.notify_event_published();

-- 7e. Comment or reaction on a post -> the post's author (not for your own)
create or replace function public.notify_post_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_author uuid;
begin
  select author_id into post_author from public.posts where id = new.post_id;
  if post_author is null or post_author = new.author_id then
    return new;
  end if;

  -- to_jsonb(new) rather than new.body: reactions has no body column, and
  -- plpgsql resolves a field reference even in a CASE branch never taken.
  insert into public.notifications (recipient_id, type, payload)
  values (post_author, 'post_activity', jsonb_build_object(
    'title', public.profile_display_name(new.author_id),
    'body', case
              when tg_table_name = 'comments'
                then 'commented: ' || left(coalesce(to_jsonb(new) ->> 'body', ''), 100)
              else 'reacted to your post'
            end,
    'actor_id', new.author_id,
    'post_id', new.post_id));
  return new;
end;
$$;

drop trigger if exists comments_notify_post_author on public.comments;
create trigger comments_notify_post_author
  after insert on public.comments
  for each row execute function public.notify_post_activity();

drop trigger if exists reactions_notify_post_author on public.reactions;
create trigger reactions_notify_post_author
  after insert on public.reactions
  for each row execute function public.notify_post_activity();

-- ---------------------------------------------------------------------
-- 8. Realtime (WebSockets) for the three tables the app subscribes to
-- ---------------------------------------------------------------------
-- supabase_realtime existed with no tables in it, so no postgres_changes
-- subscription could ever have fired. Realtime applies each table's SELECT
-- policy per subscriber, so a user only receives their own rows.
do $$
declare
  t text;
begin
  foreach t in array array['messages', 'notifications', 'connections'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
