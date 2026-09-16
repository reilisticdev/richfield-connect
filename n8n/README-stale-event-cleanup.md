# Stale Event Cleanup — n8n Workflow

> Read `SECURITY-AND-HOSTING.md` once alongside this — it covers hosting n8n during the demo and
> the POPIA note on execution logs.

Implements the schedule-driven cleanup you specified:

```
daily → events where date < now
  → archive and notify
```

Runs once a day, archives any event whose date has already passed, and emails admins a summary
of what was archived. As you noted, this is the lowest-value one to demo live — an empty result
looks like nothing happened on stage — so it's fine to build this last or leave it on the
roadmap and focus demo time on the other three.

## Files

- `stale-event-cleanup-workflow.json` — the importable n8n workflow (10 nodes)
- `README.md` — this file
- `SECURITY-AND-HOSTING.md` — shared notes that apply to all four workflows in this set

## How it works

| Step | Node(s) | What happens |
|---|---|---|
| 1 | **Daily at 00:15** | Schedule Trigger — runs just after midnight, so anything that expired "yesterday" gets cleaned up first thing |
| 2 | **⚙️ Configuration** | Recipients and sender, nothing else to tune |
| 3 | **Compute Now Timestamp** | One consistent "now" used both to select stale rows and to stamp `archived_at` |
| 4 | **Archive Stale Events (Supabase)** | A single `PATCH` to Supabase REST: matches `date < now AND archived_at IS NULL`, sets `archived_at` + `status: 'archived'`, and returns the updated rows directly (`Prefer: return=representation`) |
| 5 | **Aggregate Archived Events** | Normalises the PATCH response into `{ events, count }` |
| 6 | **Any Events Archived?** | If `count === 0`, the run ends quietly — no "0 events archived" emails |
| 7 | **Build Notify Email HTML** | Table of what got archived: title, date, location, event ID |
| 8 | **Send Notify Email (Resend)** | `POST` to the Resend API |
| 9 | **Notified ✅** | Terminal no-op marking a clean run |

Archiving and fetching happen in **one HTTP call**: the `PATCH` request both performs the
update and returns exactly the rows it touched, so there's no separate "find stale events" step
that could drift out of sync with what actually got archived.

Archiving sets `archived_at` rather than deleting the row — events stay recoverable from the
admin console if one gets archived by mistake (e.g. a timezone edge case around midnight).

## Setup

### 1. Import the workflow
In n8n: **Workflows → Import from File** → select `stale-event-cleanup-workflow.json`.

### 2. Add the `archived_at` column (if you don't have one)
This workflow uses `archived_at IS NULL` to find not-yet-archived events, rather than a status
enum, so a fresh event only ever gets archived once:

```sql
alter table events
  add column if not exists archived_at timestamptz;
```

If your `events` table already has a boolean flag (e.g. `is_archived`) instead, swap the query
parameter and PATCH body in the **Archive Stale Events (Supabase)** node:
- Query param `archived_at=is.null` → `is_archived=eq.false`
- Body field `archived_at: $json.nowTimestamp` → `is_archived: true`

### 3. Set environment variables
Same four variables as the other two schedule-driven workflows in this set — if you've already
configured these, there's nothing new here:

| Variable | Where to get it |
|---|---|
| `SUPABASE_URL` | Supabase project → Settings → API → Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase project → Settings → API → `service_role` key |
| `RESEND_API_KEY` | [resend.com](https://resend.com) → API Keys |
| `ADMIN_DIGEST_EMAILS` | Comma-separated list of admin emails |
| `DIGEST_FROM_EMAIL` | A verified sender on your Resend domain |

### 4. Match the field names to your schema
In **Build Notify Email HTML**:

```js
const title    = e.title || e.name || e.event_name || '(untitled event)';
const eventDate= e.date || e.event_date || e.start_date;
const location = e.location || e.campus || e.venue || '—';
```

Also confirm the `date` column name used in the PATCH query's `date=lt.<now>` filter matches
whatever your `events` table actually calls its event date/time column (`event_date`,
`start_date`, etc.) — this one's easy to get wrong silently, since a mismatched column name
means PostgREST just returns zero rows every day rather than erroring.

### 5. Make sure your event listings feed respects `archived_at`
This workflow only marks events as archived in the database — your app's event listings query
(the one students see) needs to filter out `archived_at IS NOT NULL` for archiving to actually
have a visible effect. If that filter isn't in place yet, do that first.

### 6. Activate & test
Toggle the workflow **Active**, then create a test event with a past date and no `archived_at`:

```sql
insert into events (title, date, status)
values ('Test Career Fair (Expired)', now() - interval '2 days', 'published');
```

Run the workflow manually (n8n's **Execute Workflow** button) — you should see the row's
`archived_at` get set in Supabase, and receive a notify email listing it.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Nothing ever gets archived | Column name mismatch on `date` or `archived_at` — PostgREST silently returns `[]` rather than erroring on a bad filter column name |
| Same event gets archived (and emailed) every single day | Your `date=lt.<now>&archived_at=is.null` filter isn't actually excluding already-archived rows — check the PATCH body is really writing `archived_at` and that the column name matches exactly |
| Students still see an event that should be archived | The archive workflow only updates the database — your app's own events query needs a matching `archived_at IS NULL` filter (see step 5 above) |
| Email never arrives | Check `RESEND_API_KEY` and that `DIGEST_FROM_EMAIL` is a verified sender/domain in Resend |
