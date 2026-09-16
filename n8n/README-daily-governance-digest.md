# Daily Governance Digest — n8n Workflow

> Read `SECURITY-AND-HOSTING.md` once alongside this — it covers hosting n8n during the demo and
> the POPIA note on execution logs (this digest email itself is full of member/admin activity data).

Implements the schedule-driven digest you specified:

```
daily → account_actions + verification_audit
  from the last 24 hours
  → one email
```

One email per day summarising every account action (suspend, unsuspend, approve, remove) and
every verification decision made in the last 24 hours — a clean governance story to present
alongside your audit log page, showing the platform is both auditable in the UI *and* proactively
reported on.

## Files

- `daily-governance-digest-workflow.json` — the importable n8n workflow (14 nodes)
- `README.md` — this file
- `SECURITY-AND-HOSTING.md` — shared notes that apply to all four workflows in this set

## How it works

| Step | Node(s) | What happens |
|---|---|---|
| 1 | **Daily at 07:00** | Schedule Trigger — fires once a day, no webhook, nothing to keep running |
| 2 | **⚙️ Configuration** | Lookback window, recipients, and the send-even-if-empty toggle |
| 3 | **Compute Since Timestamp** | Turns "24 hours" into a concrete ISO timestamp |
| 4 | **Fetch Account Actions** / **Fetch Verification Audit** | Two parallel `GET` calls to Supabase REST, each filtered to `created_at gte <since>` |
| 5 | **Aggregate …** (x2) | Each branch normalises its HTTP response into `{ table, records, count }` |
| 6 | **Merge Both Sources** | Combines the two aggregated branches into one list (Append mode) |
| 7 | **Combine & Decide** | Splits them back apart by table name, totals the count, decides whether to skip |
| 8 | **Should Skip Today?** | Only skips if `onlySendIfActivity` is on *and* there was zero activity |
| 9 | **Build Digest Email HTML** | Two tables — Account Actions, then Verification Decisions |
| 10 | **Send Digest Email (Resend)** | `POST` to the Resend API |
| 11 | **Digest Sent ✅** | Terminal no-op marking a clean run |

By default the digest sends **every day regardless of activity** — an empty digest ("No account
actions in this window") is itself useful governance signal, since it confirms the monitoring
pipeline is alive. Flip `onlySendIfActivity` to `true` in the Configuration node if you'd rather
only be emailed on days something actually happened.

## Setup

### 1. Import the workflow
In n8n: **Workflows → Import from File** → select `daily-governance-digest-workflow.json`.

### 2. Set environment variables

| Variable | Where to get it |
|---|---|
| `SUPABASE_URL` | Supabase project → Settings → API → Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase project → Settings → API → `service_role` key |
| `RESEND_API_KEY` | [resend.com](https://resend.com) → API Keys |
| `ADMIN_DIGEST_EMAILS` | Comma-separated list, e.g. `admin1@richfield.ac.za,admin2@richfield.ac.za` |
| `DIGEST_FROM_EMAIL` | A verified sender on your Resend domain |

This workflow reuses the same four environment variables as the **pending verification
chaser** workflow, so if you've already set those up for that one, there's nothing new to
configure here beyond importing the JSON.

### 3. Match the field names to your schema
Two tables feed this digest, so there are two sets of field names to check in
**Build Digest Email HTML**:

```js
// account_actions row
const action      = r.action_type || r.action || '(unknown)';
const targetUser  = r.target_user_email || r.target_user_name || r.target_user_id || '(unknown)';
const performedBy = r.performed_by_name || r.performed_by_email || r.performed_by || r.admin_id;

// verification_audit row
const trackId    = r.track_id || r.tracking_id || r.claim_id || r.id;
const decision   = r.decision || r.status || '(unknown)';
const reviewedBy = r.reviewed_by_name || r.reviewed_by_email || r.reviewed_by || r.admin_id;
```

If either table stores a foreign key to `users` rather than a name/email directly, add
PostgREST resource embedding to that table's `select` query parameter in the corresponding
**Fetch …** node (currently `select=*`), e.g. `select=*,performed_by:users(full_name,email)`,
then reference `r.performed_by.full_name` in the code above.

### 4. Pick your send time
Currently set to **07:00 server time** (start of business day). Change `triggerAtHour` /
`triggerAtMinute` on the **Daily at 07:00** node if you want a different time — e.g. end-of-day
at 18:00, so the digest covers the working day just finished rather than crossing midnight.

### 5. Activate & test
Toggle the workflow **Active**, then use n8n's **Execute Workflow** button to trigger a manual
run immediately rather than waiting for 07:00. If your `account_actions` / `verification_audit`
tables are empty, you'll get a digest showing "No account actions in this window" for both
sections — that confirms the plumbing works end-to-end even before real governance activity
exists to report on.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Workflow never fires | It isn't toggled **Active** — Schedule Triggers only run on active workflows |
| Digest always shows zero for one table | Check that table's `created_at` column name and that the Supabase service-role key has read access (RLS can silently return `[]` instead of erroring) |
| Getting two separate emails instead of one | Check the **Merge Both Sources** node is wired to *both* Aggregate nodes (input 0 and input 1) — if one branch bypasses the merge you'll get inconsistent combined counts, not two emails, but it's worth double-checking after any manual rewiring |
| Email never arrives | Check `RESEND_API_KEY` and that `DIGEST_FROM_EMAIL` is a verified sender/domain in Resend |
| Want it to only email when something happened | Set `onlySendIfActivity` to `true` in the **⚙️ Configuration** node |
