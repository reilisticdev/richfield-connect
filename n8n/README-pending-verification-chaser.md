# Pending Verification Chaser — n8n Workflow

> Read `SECURITY-AND-HOSTING.md` once alongside this — it covers hosting n8n during the demo and
> the POPIA note on execution logs (this workflow's digest emails carry alumni names/emails).

Implements the schedule-driven chaser you specified:

```
every 6h → verification_claims
  where status = 'pending' and older than 24h
  → digest email to administrators
```

Runs entirely inside n8n on a cron schedule — nothing needs to stay open on your laptop, so
this keeps working straight through the demo, overnight, and after the hackathon ends. It
answers the "alumni → certificate → track ID → verification" flow: whenever a claim sits
un-actioned for more than 24 hours, admins get a digest email listing every stale claim by its
track ID until someone resolves it.

## Files

- `pending-verification-chaser-workflow.json` — the importable n8n workflow (10 nodes)
- `README.md` — this file
- `SECURITY-AND-HOSTING.md` — shared notes that apply to all four workflows in this set

## How it works

| Step | Node(s) | What happens |
|---|---|---|
| 1 | **Every 6 Hours** | Schedule Trigger — no webhook, no external caller needed |
| 2 | **⚙️ Configuration** | Thresholds and recipients in one place |
| 3 | **Compute Cutoff Timestamp** | Turns "24 hours" into a concrete ISO timestamp |
| 4 | **Fetch Stale Pending Claims** | `GET` to Supabase REST: `status=eq.pending&created_at=lt.<cutoff>` |
| 5 | **Aggregate Claims** | Normalises the response into one item: `{ claims: [...], count }` |
| 6 | **Any Stale Claims?** | If `count === 0`, the run ends quietly — no empty "0 claims" emails |
| 7 | **Build Digest Email HTML** | Renders a table: Track ID, alumni name/email, submitted date, hours pending |
| 8 | **Send Digest Email (Resend)** | `POST` to the Resend API |
| 9 | **Digest Sent ✅** | Terminal no-op, just marks a clean successful run in the execution log |

Because this is schedule-driven rather than event-driven, a claim that's still pending will
appear in *every* run until its status changes — that's the "chaser" behaviour by design (see
"Reducing repetition" below if that turns out to be too noisy for your admins).

## Setup

### 1. Import the workflow
In n8n: **Workflows → Import from File** → select `pending-verification-chaser-workflow.json`.

### 2. Set environment variables

| Variable | Where to get it |
|---|---|
| `SUPABASE_URL` | Supabase project → Settings → API → Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase project → Settings → API → `service_role` key |
| `RESEND_API_KEY` | [resend.com](https://resend.com) → API Keys (free tier is plenty for a hackathon demo) |
| `ADMIN_DIGEST_EMAILS` | Comma-separated list, e.g. `admin1@richfield.ac.za,admin2@richfield.ac.za` |
| `DIGEST_FROM_EMAIL` | A verified sender on your Resend domain, e.g. `moderation@yourdomain.com` |

> Using a different email provider (SendGrid, Mailgun, or Gmail via n8n's native **Send Email**
> node)? Swap out only the **Send Digest Email (Resend)** node — everything upstream of it
> (`html`, `subject`, `recipients`, `fromAddress`) is already provider-agnostic in the item
> passed into it.

### 3. Match the field names to your schema
`verification_claims` schemas vary a lot between teams. Open **Build Digest Email HTML** and
check the field names against your actual columns:

```js
const name    = c.alumni_name || c.full_name || c.name || '(name unavailable)';
const email   = c.alumni_email || c.email || '(email unavailable)';
const trackId = c.track_id || c.tracking_id || c.id;
const created = c.created_at || c.submitted_at;
```

If alumni name/email live on a separate `users`/`alumni` table (joined by a foreign key) rather
than directly on `verification_claims`, use PostgREST resource embedding in the **Fetch Stale
Pending Claims** node's `select` query parameter instead of `*`, e.g.:

```
select=*,alumni:users(full_name,email)
```

(adjust `alumni:users` to your actual foreign-key relationship name), then reference
`c.alumni.full_name` / `c.alumni.email` in the digest code.

### 4. Activate & test
Toggle the workflow **Active**. To test without waiting 6 hours, click **Execute Workflow**
manually, or temporarily insert a test row with an old timestamp:

```sql
insert into verification_claims (alumni_id, track_id, status, created_at)
values ('<any-existing-alumni-uuid>', 'TRK-TEST-001', 'pending', now() - interval '30 hours');
```

You should receive a digest email listing that claim within a few seconds of running the
workflow manually.

## Reducing repetition (optional enhancement)

Since every stale claim resurfaces every 6 hours until resolved, a claim stuck for days will
generate a lot of emails. If that becomes noisy before or during the demo, two easy options:

1. **Widen the schedule** for stale (but not brand-new) claims — e.g. chase every 6h for the
   first 48h, then drop to once daily.
2. **Add a `last_reminded_at` column** to `verification_claims`, set it in a new step after the
   email send (`PATCH` the rows with the current timestamp), and add a second condition to the
   fetch query like `last_reminded_at=lt.<now minus X hours>` so a claim already chased
   recently doesn't fire again immediately.

Neither is implemented here since the brief didn't call for dedup logic — but both are small,
citable design decisions if you want to mention "chaser fatigue" handling in your presentation.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Workflow never fires | It isn't toggled **Active** — Schedule Triggers only run on active workflows |
| Fetch returns 0 rows even though you know a claim is stale | Check the `created_at` column name matches, and that its timezone matches what `new Date().toISOString()` produces (UTC) |
| Email never arrives | Check `RESEND_API_KEY` is valid and `DIGEST_FROM_EMAIL` is a verified sender/domain in Resend — unverified senders get silently rejected |
| Email arrives with blank name/email columns | Your `verification_claims` table doesn't store those directly — see "Match the field names to your schema" above for the resource-embedding fix |
| Getting flooded with repeat emails | Expected "chaser" behaviour — see "Reducing repetition" above |
