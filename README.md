# Richfield Connect

A graduate networking platform built for the 2026 Richfield Hackathon, connecting **students**, **alumni**, **business partners**, and **institutional administrators** on one platform: verified digital portfolios, business-approved opportunity listings, a social feed, and role-specific analytics dashboards.

The primary product is the **mobile app** (Flutter) — the web app is an administrator-only back office, not a parallel consumer experience.

## Project Overview

Richfield Connect solves a common gap at tertiary institutions: students and alumni have no single, verified place to showcase skills and experience, and businesses have no trustworthy pipeline into that talent pool. The platform enforces real identity and role guarantees end to end:

- **Four distinct roles** — Student, Alumni, Business, Administrator — each with backend-enforced permissions (Postgres Row-Level Security, not just hidden UI).
- **No self-registering administrators.** Admin accounts are provisioned out-of-band via a service-role script (see [Admin provisioning](#admin-provisioning) below).
- **Domain-restricted student signup.** Student accounts must use an institutional email address; the rule is enforced by a database trigger, not just client-side validation.
- **Verified onboarding.** Alumni go through a claim-and-review flow; business accounts go through manual admin approval before they can post opportunities — both logged to an audit trail and triggering a real notification email.
- **Verified digital portfolios** — skills, education, work experience, projects, certifications, badges, endorsements, and recommendations, with per-section visibility controls.
- **Business-posted, admin-approved opportunity listings** that students can browse, filter, and apply to.
- **Role-specific analytics dashboards** for students, businesses, and administrators, backed by real Postgres aggregate functions (no client-side mock math).

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| **Backend** | [Supabase](https://supabase.com) (Postgres, Auth, Storage, Edge Functions, Realtime, pgvector) | One managed platform covering a relational database, authentication, row-level authorization, file storage, serverless functions, and vector similarity search (for skills/opportunity matching) — avoids stitching together five separate services under hackathon time pressure. |
| **Mobile app** | [Flutter](https://flutter.dev) + [go_router](https://pub.dev/packages/go_router) | Single codebase targeting Android and iOS from day one, with a router that reacts to live Supabase auth state (role/account-status-aware redirects) rather than a static route table. |
| **Web admin** | [React](https://react.dev) 19 + [Vite](https://vitejs.dev) + [react-router-dom](https://reactrouter.com) | Fast dev loop for an internal-only admin surface — no server-rendering or SEO requirements, so a lightweight SPA setup is the right fit. |
| **AI microservice** | Python + [Flask](https://flask.palletsprojects.com) + [Gemini](https://ai.google.dev) | Powers CV parsing/NLP-assisted profile building, an AI onboarding/profile assistant, post-writing help, and personalized recommendations — kept as a separate service so it can be iterated on and deployed independently of the Supabase Edge Functions layer. |
| **Database** | Postgres (via Supabase), with `pgvector` | Relational integrity (foreign keys, RLS policies enforcing who-can-see/do-what) matters more here than horizontal write scale, and `pgvector` gives skills/opportunity matching without a separate vector database. |

## Repository Structure

```
richfield-connect/
├── mobile/                 Flutter app — the primary product surface
├── web/                    React admin panel (Vite) — administrators only
├── ai/                     Python/Flask AI microservice (CV parsing, profile assistant, recommendations)
├── supabase/
│   ├── migrations/         Numbered, sequential SQL migrations — source of truth for the schema
│   ├── functions/          Supabase Edge Functions (e.g. transactional email)
│   └── scripts/            One-off operational scripts (e.g. admin provisioning)
└── README.md
```

### Folder ownership

Each folder above has a single owner during development, to keep concurrent work conflict-free:

| Folder | Owner |
|---|---|
| `/mobile/` | Mobile |
| `/web/` | Web admin |
| `/supabase/migrations/` | Database/Security |
| `/supabase/functions/` | Backend |
| `/ai/` | AI microservice |

Cross-folder changes happen only as explicit, reviewed exceptions — never assumed.

All work happens on a branch and merges into `main` via pull request; nobody pushes to `main` directly.

## Setup Instructions

### Prerequisites

- A Supabase project (Postgres + Auth + Storage + Edge Functions enabled)
- [Node.js](https://nodejs.org) 18+ (for the web admin panel and Supabase scripts)
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) for the mobile app
- Python 3.11+ for the AI microservice

### 1. Database

Apply the migrations in `supabase/migrations/` in order (numeric prefix), either via the Supabase CLI:

```bash
supabase db push
```

or via the Supabase MCP/dashboard SQL editor, one file at a time in numeric order. Migrations are additive and sequential — do not skip or reorder them.

### 2. Web admin panel

```bash
cd web
npm install
```

Create `web/.env.local`:

```
VITE_SUPABASE_URL=https://<your-project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<your-anon-key>
```

```bash
npm run dev
```

### 3. Mobile app

```bash
cd mobile
flutter pub get
```

Set your project URL and anon key in `mobile/lib/config/supabase_config.dart` (anon key is safe to commit — it's rate-limited and RLS-gated, not a secret).

```bash
flutter analyze   # run this before flutter run — catches issues early
flutter run
```

### 4. Admin provisioning

There is no self-registration path for administrators by design. To create the first admin account:

```bash
cd supabase/scripts
npm install
cp .env.example .env   # fill in SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ADMIN_EMAIL, ADMIN_PASSWORD
npx tsx provision-admin.ts
```

This uses the **service role key** — never commit `.env` or expose the service role key to a client. The script refuses to run a second time unless `--force` is passed.

### 5. AI microservice

```bash
cd ai
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

Set `GEMINI_API_KEY`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY` as environment variables (or in a `.env` file, not committed), then:

```bash
flask run
```

## Security Notes

- **Row-Level Security is the real authorization boundary** — every table with sensitive data has RLS policies enforced at the database level, not just conditional rendering in the UI.
- **Never commit** a service role key, the AI microservice's `GEMINI_API_KEY`, or any `.env` file. Only the Supabase *anon* key is safe to check in.
- POPIA-relevant user data export/delete is available via `export_my_data()` and `delete_my_account()` database functions.
