# Richfield Connect - Web Admin Panel

React 19 + Vite single-page app. This is an **administrator-only back office**, not a
parallel consumer experience - the primary product surface is the mobile app (see
[root README](../README.md)).

## Getting started

```bash
cd web
npm install
```

Create `web/.env.local`:

VITE_SUPABASE_URL=https://<your-project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<your-anon-key>


```bash
npm run dev
```

## Structure

src/
|-- App.jsx Route definitions
|-- main.jsx Entry point
|-- lib/ Supabase client + shared helpers
|-- components/ Shared UI (see below)
`-- pages/ One file per admin page (see below)


### Pages

| Page | Purpose |
|---|---|
| `Login.jsx` | Admin sign-in (no self-registration - see root README's "Admin provisioning") |
| `Dashboard.jsx` | Landing overview after login |
| `Users.jsx` | User management: suspend, reactivate and remove accounts (roles are fixed at sign-up) |
| `Opportunities.jsx` | Review/approve business-posted opportunities |
| `Events.jsx` | Manage institutional events |
| `Announcements.jsx` | Broadcast announcements |
| `Moderation.jsx` | Feed/content moderation queue |
| `Analytics.jsx` | Role-specific analytics dashboards, backed by Postgres aggregate functions |

### Shared components

`Sidebar.jsx` / `Header.jsx` (app chrome), `RequireAdmin.jsx` (route guard - redirects
non-admins, backed by the real RLS policies at the database level, not just this
client-side check), `StatCard.jsx` / `StatusBadge.jsx` (reusable display primitives
used across `Dashboard`, `Analytics`, and `Users`).

## Notes

- Only the Supabase **anon** key belongs in `.env.local` - never the service role key.
- Authorization here is a UX convenience layer; the real enforcement is Postgres
  Row-Level Security, so a bug in `RequireAdmin.jsx` can't itself expose data.
