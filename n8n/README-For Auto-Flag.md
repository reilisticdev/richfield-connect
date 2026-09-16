# Auto-Flag Inappropriate Content — n8n Workflow

Implements the pipeline you specified for Richfield Connect's admin-side moderation automation:

```
posts INSERT → database webhook → n8n
  → keyword list (+ optional Gemini call)
  → insert content_reports, reported_by NULL
  → appears in Moderation
```

No new UI is needed — this drops system-generated reports straight into the same
`content_reports` table the Flagged Content queue already renders, using `reported_by = NULL`
to distinguish automated flags from user reports. Admins keep using the existing Keep/Remove
buttons.

## Files

- `auto-flag-content-workflow.json` — the importable n8n workflow (16 nodes)
- `README.md` — this file

## How it works

| Step | Node(s) | What happens |
|---|---|---|
| 1 | **Post Created (Webhook)** | Receives the DB webhook call fired on `posts` INSERT |
| 2 | **⚙️ Configuration** | Single place to tune thresholds without touching code |
| 3 | **Parse & Validate Payload** | Confirms it's really a new `posts` row, extracts content |
| 4 | **Keyword Scan** | Free, instant check against harassment/spam/scam/profanity term lists |
| 5 | **Keyword Threshold Exceeded?** | If score ≥ threshold → skip straight to filing a report |
| 6 | **AI Moderation Enabled?** | If keywords found nothing, optionally escalate to Gemini |
| 7 | **Gemini Moderation Check** | Asks Gemini to classify the post (flagged/category/severity/reason) |
| 8 | **Prepare Report (…)** | Builds the `content_reports` insert payload with a human-readable reason |
| 9 | **Insert content_reports Row** | `POST` to Supabase's REST API (PostgREST) with `reported_by: null` |
| 10 | **Respond 200 (…)** | Acknowledges the webhook so the DB doesn't retry |

The keyword pass and the AI pass are independent layers: keyword matches file a report
immediately (cheapest, fastest); if nothing matches, Gemini gets one shot to catch things a
word list can't (paraphrased hate speech, disguised scams, etc.). If the Gemini call fails for
any reason, the workflow fails **open** on that layer (it does not flag) rather than crashing —
the error is captured in `aiError` if you want to alert on it separately.

## Setup

### 1. Import the workflow
In n8n: **Workflows → Import from File** → select `auto-flag-content-workflow.json`.

### 2. Set environment variables
This template reads secrets from n8n environment variables (`$env.X`) rather than hard-coding
them, so nothing sensitive lives in the JSON file. Set these on your n8n instance:

| Variable | Where to get it |
|---|---|
| `SUPABASE_URL` | Supabase project → Settings → API → Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase project → Settings → API → `service_role` key (needed to bypass RLS for a system insert — keep this secret, server-side only) |
| `GEMINI_API_KEY` | [Google AI Studio](https://aistudio.google.com/apikey) |

If you're self-hosting n8n via Docker, add them to your `docker-compose.yml` under
`environment:`, or a `.env` file it loads from.

### 3. Wire up the database webhook
In Supabase: **Database → Webhooks → Create a new webhook**
- Table: `posts`
- Events: `Insert`
- Type: `HTTP Request`
- URL: your n8n webhook's **Production URL** (copy it from the "Post Created (Webhook)" node
  once the workflow is **Active**) — it will look like
  `https://<your-n8n-host>/webhook/post-created`
- Method: `POST`

> Not on Supabase? Any mechanism that fires an HTTP POST on insert works — a Postgres
> `AFTER INSERT` trigger calling `pg_net.http_post`, a Firestore Cloud Function, or your own
> backend calling the webhook right after it writes the row. Avoid polling for this — n8n's
> Postgres node only supports trigger-based execution via a webhook/notify bridge, which is
> also more consistent with the "no polling" requirement elsewhere in your real-time features.

### 4. Confirm your `content_reports` columns
The insert payload uses these columns — add any that don't already exist:

```sql
alter table content_reports
  add column if not exists report_type text default 'manual',
  add column if not exists category    text,
  add column if not exists severity    integer,
  add column if not exists flagged_by  text;
```

`reported_by` should already allow `NULL` (per your note) — that's what makes a system report
indistinguishable-in-structure from a user report, so your existing Moderation UI needs zero
changes.

### 5. Activate & test
Toggle the workflow **Active**, then insert a test row directly in Supabase's table editor:

```sql
insert into posts (author_id, content)
values ('<any-existing-user-uuid>', 'guaranteed income, send bitcoin now, act now!!');
```

You should see a new row appear in `content_reports` within a few seconds, and it should show
up in your Moderation queue exactly like a user-submitted report.

## Configuration knobs

All in the **⚙️ Configuration** node — no need to open any code node to tune behaviour:

- `keywordThreshold` (default `3`) — total severity score needed to auto-file a report on
  keywords alone. Harassment/scam/hate-speech terms are weighted higher than profanity.
- `enableAiModeration` (default `true`) — set `false` to run keyword-only (useful for a demo
  where you don't want to depend on the Gemini API being reachable).
- `aiModel` (default `gemini-2.0-flash`) — swap for another Gemini model if needed.

## Extending the hate-speech keyword list

The `hateSpeech` array inside the **Keyword Scan** node is intentionally left empty rather than
shipped with a hard-coded slur list — that's a policy decision your team/institution should
own, not something to bake into a shared repo. Two solid options for the demo/presentation:

1. Populate the array yourselves with your reviewed term list before presenting.
2. Lean on the Gemini layer for this category — it's already prompted to catch hate speech —
   and mention in your slides that you deliberately chose an AI-based approach over a
   hard-coded list for this category, which is a genuinely defensible design decision to cite
   under "AI profile assistant / chatbot" or "content moderation" in your presentation.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Webhook never fires | Workflow isn't **Active**, or Supabase webhook is pointed at the Test URL instead of the Production URL |
| Every post gets flagged | `keywordThreshold` too low, or Gemini's `temperature` isn't `0` (already set to `0` here for consistency) |
| Gemini node errors out | Check `GEMINI_API_KEY` is set and the model name in Configuration matches an available Gemini model |
| Insert to `content_reports` fails with 401/403 | You're using the `anon` key instead of `service_role`, or Row-Level Security is blocking the insert — `service_role` bypasses RLS by design |
| Insert succeeds but nothing shows in the Moderation UI | Confirm the UI query includes rows where `reported_by IS NULL`, not just rows with a non-null reporter |
