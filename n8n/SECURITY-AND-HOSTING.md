# Security & Hosting — read this once, applies to all four workflows

This file covers the parts of the architecture that are the same across all four automations
(auto-flag, verification chaser, governance digest, event cleanup). Each workflow's own README
covers what's specific to it; this one is the shared story to have ready for judges.

## What n8n is, and what it must never be

**n8n is an operations layer, not a security layer.** Every one of these workflows reads or
writes data using a single service-role credential that lives inside n8n's environment/credential
store and is never sent to a client, never appears in the mobile app's code or config, and never
appears in a pull request. Nothing these workflows do bypasses your app's own policies — a system-
generated content report still goes through the same `content_reports` table and the same
Row-Level Security your app's own writes go through; it's just authenticated as a trusted backend
process instead of as a logged-in user.

The test worth stating out loud if a judge asks "does adding an automation tool weaken your
security model?": **if n8n is switched off, the app keeps working and nothing becomes unsafe.**
No feature depends on n8n being reachable for the app itself to function correctly and securely —
n8n only adds background jobs (auto-flagging, chasing, digesting, archiving) on top of an app
that's already correct without it.

## The one place n8n receives inbound traffic: the auto-flag webhook

Three of the four workflows are schedule-driven — n8n calls out to Supabase on a timer, nothing
calls in. The **auto-flag** workflow is the exception: Supabase calls n8n on every `posts` insert,
which means that inbound URL needs to be protected the same way the project already protects its
Supabase edge functions — a shared secret held in Supabase Vault, checked before any work happens.
See the auto-flag workflow's own README for the exact wiring steps. The short version: the very
first node after the webhook trigger rejects any request that doesn't carry the correct
`x-webhook-secret` header, before any parsing, keyword scanning, or database write occurs.

## Where to host n8n during the hackathon

**Use n8n Cloud's trial for the demo window, not the presenting laptop.** If a webhook-based
service dies whenever the demo machine sleeps or its tunnel URL changes on restart, that's the
same failure mode as any other laptop-hosted dependency — solved once by moving it off the machine
that's on the lectern. If self-hosting is required for some reason, host it on a separate machine
from the one presenting, so a laptop hiccup during the live demo can't take down the automations
you're trying to show off.

Note that this affects the “Set environment variables” step in the other three READMEs: whether
your n8n Cloud plan supports custom environment variables varies by plan. If yours doesn't, the
values these workflows read via `$env.X` (Supabase URL, admin email list, API keys) will need to
move into n8n's **Credentials** store or directly into the relevant node instead — check your
plan's docs before assuming `$env` will work, and budget time to switch if it doesn't.

## POPIA: n8n's execution log also contains member data

n8n keeps a log of every workflow execution, and by default that log includes the full payload
that passed through each node — which, for these workflows, includes real names, emails, post
content, and verification details. That's exactly the kind of data POPIA asks you to think about
retention limits for.

**Set a short execution-log retention period** in n8n (Settings → Log Streaming / Workflow
Settings → "Save execution progress" and the data-pruning / retention settings, naming varies by
version) rather than leaving it on indefinite retention. Mention in your presentation that you did
this — it's a small, concrete, easy-to-explain example of the exact privacy-by-design thinking the
POPIA section of the rubric is looking for, and it costs you one settings screen to have it ready
to cite.

**Update 2026-09-16**: on Reilyn's local dev instance this is set via env vars rather than the
Settings UI, since that's easier to carry over to whatever host n8n ends up on permanently:

```
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=24
```

`EXECUTIONS_DATA_MAX_AGE` is in hours - 24 is enough to debug a failed run without indefinitely
retaining member data in the execution log. Whoever sets up n8n Cloud or Railway for the actual
demo (see "Where to host n8n" above - still not done as of this writing) should set the equivalent
on that instance too; on n8n Cloud this may only be available via the Settings UI rather than env
vars depending on plan, same caveat as the `$env` custom-variables note above.

## Keeping the service-role key actually secret

Every workflow in this set references the Supabase service-role key as `{{ $env.SUPABASE_SERVICE_ROLE_KEY }}`
— an expression, never the literal key value — so the raw key never appears in the workflow JSON,
never gets committed to a repo if you export/version these files, and never shows up if someone
screenshots a node's configuration for a slide. Keep it that way:

- Never paste the actual key value into a node field "just to test it quickly" — use the
  environment variable (or a proper n8n Credential, if your hosting plan requires that route)
  every time, including while debugging.
- Before screenshotting any node for your slides, check that the field showing the key is showing
  `$env.SUPABASE_SERVICE_ROLE_KEY` and not a decrypted/expanded value — some node UIs will show
  the resolved value in a preview pane if you click "execute" on that node in isolation.
- The moment the real key appears in a plain-text field, a git commit, or a screenshot, treat it
  as compromised and rotate it in Supabase's dashboard — it's a five-minute fix if caught early
  and a much bigger one if it ships on a public repo or a recorded demo.
