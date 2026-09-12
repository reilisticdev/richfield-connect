# Documentation Index

This folder is the entry point for anything that isn't covered in a component's own
README. Start here, then drill into the folder-level docs.

## Where things live

| Topic | Location |
|---|---|
| Project overview, tech stack, setup instructions | [`/README.md`](../README.md) |
| Database schema & migration history | [`/supabase/migrations/README.md`](../supabase/migrations/README.md) |
| Edge Functions (email, push notifications) | [`/supabase/functions/README.md`](../supabase/functions/README.md) |
| Mobile app (Flutter) | [`/mobile/README.md`](../mobile/README.md) |
| Web admin panel (React) | [`/web/README.md`](../web/README.md) |
| AI microservice (Flask) | [`/ai/app.py`](../ai/app.py) |

## Roles at a glance

Richfield Connect has four roles, each backed by Postgres Row-Level Security rather
than just hidden UI:

- **Student** - institutional-email-only signup, builds a verified portfolio, browses
  Career Pathways / opportunities.
- **Alumni** - claim-and-review verification flow before full access.
- **Business** - manual admin approval before they can post opportunities.
- **Administrator** - no self-registration; provisioned out-of-band (see root README's
  "Admin provisioning" section).

## Reporting a bug or gap in the docs

If something here is out of date, open a PR against this file rather than raising it
verbally - keeps the docs and the codebase in sync, and gives the change a paper trail
in the commit history.
