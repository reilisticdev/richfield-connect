# Richfield Connect

A secure, four-role professional networking platform built for the **Richfield / AAA Hackathon 2026**, connecting **students**, **alumni**, **businesses**, and **institutional administrators** on one platform — from a student's first enrolment through to career growth as an alumnus.

The **mobile app (Flutter)** is the primary product surface, per the hackathon rubric. The **React web app** is an administrator-only back office, not a parallel consumer experience.

> **Live project:** Supabase (`eu-central-1`) · **Repo:** [`github.com/reilisticdev/richfield-connect`](https://github.com/reilisticdev/richfield-connect)

---

## Table of Contents

- [The Problem](#the-problem)
- [What We Built](#what-we-built)
- [Feature Tour by Role](#feature-tour-by-role)
- [System Architecture](#system-architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Security Model](#security-model)
- [AI Microservice](#ai-microservice)
- [Testing & Quality](#testing--quality)
- [Engineering Process](#engineering-process)
- [Team](#team)

---

## The Problem

Employability now depends on a digital portfolio and a professional network established well before graduation day, not after. Three gaps show up at most institutions, including Richfield:

- **Graduates need visible careers before they graduate.** Skills, projects, and work experience live scattered across CVs, chat threads, and memory — not in one verifiable place.
- **Institutions need a bridge to industry.** There is no trusted channel connecting current students, alumni, recruiters, and industry partners in one ecosystem.
- **Existing tools are generic.** LinkedIn is not built for one institution; a campus portal is not built for careers. Nothing verifies a Richfield identity, guides a student's profile, or matches talent to opportunity automatically.

**Our response:** Richfield Connect — a mobile-first platform where students build a portfolio from day one, alumni stay engaged for life, businesses discover verified Richfield talent, and administrators govern the whole ecosystem with real backend security.

## What We Built

Richfield Connect is **one ecosystem, four working parts**, sharing a single Postgres database and a single set of authorization rules:

1. **Flutter mobile app** — the primary demo surface, for students, alumni, and businesses.
2. **React web admin dashboard** — administrator-only console for platform governance.
3. **Supabase backend** — Postgres, Auth, Storage, Edge Functions, and Realtime, all gated by Row-Level Security.
4. **Python/Flask AI microservice** — CV parsing, an onboarding/profile chat assistant, and skill suggestions, powered by Google Gemini.

Every authorization rule that matters — who can read a profile, who can post an opportunity, who can suspend a member — is enforced **in the database**, not just hidden behind a disabled button in the UI. A raw REST call from a suspended account, an unauthenticated client, or a member outside their role is rejected by Postgres itself.

## Feature Tour by Role

### Student & Alumni

- **Verified sign-up.** Student accounts require an institutional email address, enforced by a database trigger — not just client-side validation.
- **Digital portfolio, not a bio** — skills, education, work experience, projects, certifications, badges (Credly-style), achievements, and endorsements, each with independent per-section visibility controls.
- **CV import** — upload a PDF and have Gemini parse it directly (no local text extraction, so scanned CVs still work) into strict, structured JSON that pre-fills the portfolio. The original PDF is kept on the profile as evidence, and a fresh copy is snapshotted onto every job application at the moment of applying.
- **AI onboarding & career assistant** — a context-aware chat assistant that reads the caller's real profile and helps with onboarding, profile completion, and career questions.
- **Employability Score** — nine equal-weight, computed-on-device signals (skills, education, work experience, projects, a CV on file, a public link, a badge, and more), designed to return a meaningful number even for a brand-new profile with no history — unlike the peer-comparison RPC it sits alongside, which needs an `education` row to return anything at all.
- **Career Pathways** — a peer-comparison view showing how a student's profile stacks up against others in the same programme.
- **Social feed** — posts (including short-form video, compressed and thumbnailed on-device before upload), reactions, comments, and a feed ranked by role affinity, connections, engagement, and recency (with a "Newest first" fallback).
- **Networking** — connection requests, a searchable member directory, and **QR Connect**: a QR code encoding a deep link (`richfield://member/<uid>`) that opens straight to a member's profile, with a "Copy link" fallback.
- **Direct messaging** — realtime, one-to-one.
- **Opportunities** — browse and apply to business-posted, admin-approved job/internship listings, with the relevant CV attached automatically.
- **Notifications** — real-time in-app and push (Firebase Cloud Messaging), confirmed working end-to-end on a real device build.
- **POPIA privacy controls** — export your own data or delete your account, both backed by real database functions, not a support ticket.
- **First-run tutorial** — an interactive walkthrough that fires automatically on first launch.

### Business

- **Manual, admin-gated verification** before a business account can post anything — no self-serve trust.
- **Post and manage opportunity listings**, with the ability to withdraw or delete a listing.
- **Review applicants**, including their attached CV, for each listing.
- **Business analytics dashboard** — real engagement and applicant metrics from Postgres aggregate functions, not client-side mock math.

### Administrator

- **No self-registration, ever.** Admin accounts exist only via an out-of-band, service-role provisioning script — never through the app.
- **Full moderation console**, now on **both web and mobile**: approve or reject alumni verification claims and business applications, delete posts, suspend/reactivate/remove members, and take down opportunity listings.
- **Audit Log** — a read-only, append-only record of every admin action (who, what, when), backed by dedicated audit tables.
- **Platform-wide announcements**, broadcast to every member.
- **Event management** — create, edit, and delete institutional events; every upcoming event surfaces in the mobile feed in the correct order.
- **Analytics dashboard** — platform-wide KPIs and trend charts (registrations, engagement, moderation volume) computed by the database, refreshed live.

### Cross-cutting

- **Realtime everywhere it matters** — messages, feed reactions/comments, and live dashboard figures update without a manual refresh.
- **Smart matching** — Gemini-backed skill suggestions surface relevant opportunities and connections based on a member's actual profile content.
- **Video pipeline** — on-device 720p compression, automatic thumbnail generation, and playback in the feed, so no raw, unoptimized video ever reaches storage.

## System Architecture

```
                    ┌─────────────────────┐        ┌──────────────────────────┐
                    │   Flutter Mobile     │        │   React Web Admin        │
                    │ (students · alumni · │        │  (administrators only)   │
                    │      businesses)     │        │                          │
                    └──────────┬───────────┘        └────────────┬─────────────┘
                               │                                  │
                               │      HTTPS / PostgREST / Realtime WS
                               ▼                                  ▼
                    ┌──────────────────────────────────────────────────────────┐
                    │                  Supabase (eu-central-1)                 │
                    │  ┌───────────┐ ┌────────────────┐ ┌────────────────────┐ │
                    │  │  GoTrue   │ │ Postgres + RLS  │ │  Edge Functions     │ │
                    │  │  (Auth)   │ │ 40 migrations,  │ │  (Deno) — email &   │ │
                    │  │           │ │ 45+ RLS policies│ │  push notifications │ │
                    │  └───────────┘ └────────────────┘ └────────────────────┘ │
                    │  ┌───────────┐ ┌────────────────┐                        │
                    │  │  Storage  │ │   Realtime      │                       │
                    │  │ (media,   │ │ (messages, feed,│                       │
                    │  │  CVs)     │ │  live dashboards│                       │
                    │  └───────────┘ └────────────────┘                        │
                    └───────────────────────┬──────────────────────────────────┘
                                             │ HTTPS (no direct DB access)
                                             ▼
                              ┌───────────────────────────────┐
                              │  AI Microservice (Flask)       │
                              │  /api/parse-cv · /api/chat ·   │
                              │  /api/suggest-skills           │
                              │  → Google Gemini                │
                              └───────────────────────────────┘
```

The AI microservice never touches the database directly — it receives a JWT-authenticated request from a client, calls Gemini, and returns structured JSON. All persistence goes back through Supabase, under the same RLS rules as everything else.

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| **Mobile app** | [Flutter](https://flutter.dev) + [go_router](https://pub.dev/packages/go_router) | One codebase compiling to native ARM for Android and iOS, with a router that reacts to live Supabase auth state (role- and account-status-aware redirects) instead of a static route table. |
| **Web admin** | [React](https://react.dev) 19 + [Vite](https://vitejs.dev) + [react-router-dom](https://reactrouter.com) | A fast dev loop for an internal-only admin surface with no SEO or server-rendering requirement. |
| **Backend** | [Supabase](https://supabase.com) (Postgres, Auth, Storage, Edge Functions, Realtime) | One managed platform for a relational database, authentication, row-level authorization, file storage, serverless functions, and realtime subscriptions — no hand-rolled auth or a separate pub/sub service. |
| **Database** | Postgres, via Supabase | The data is relational by nature — profiles, skills, endorsements, connections, messages, opportunities, and applications are many-to-many with real referential-integrity requirements. Chosen deliberately over NoSQL. |
| **AI microservice** | Python + [Flask](https://flask.palletsprojects.com) + [Google Gemini](https://ai.google.dev) (`google-genai`, model `gemini-2.5-flash`) | CV parsing, an onboarding/profile chat assistant, and skill suggestions — kept as a separate service so it deploys and iterates independently of the Supabase Edge Functions layer. |
| **Push notifications** | Firebase Cloud Messaging | Confirmed working end-to-end on a real device build. |

## Repository Structure

```
richfield-connect/
├── mobile/                 Flutter app — the primary product surface
│   └── lib/
│       ├── screens/        Feature screens (feed, portfolio, messaging, admin moderation, ...)
│       ├── services/       Supabase/AI/notification service wrappers
│       ├── router/         go_router config, auth-aware redirects
│       ├── widgets/        Shared UI components
│       └── config/         Environment/server-address resolution
├── web/                    React admin panel (Vite) — administrators only
│   └── src/pages/          Dashboard, Analytics, Users, Moderation, Opportunities,
│                           Events, Announcements, AuditLog, Login
├── ai/                     Python/Flask AI microservice
│   └── app.py              /health · /api/parse-cv · /api/chat · /api/suggest-skills
├── supabase/
│   ├── migrations/         40 numbered, sequential SQL migrations — source of truth for the schema
│   ├── functions/          Edge Functions: email-confirmed, send-notification-email,
│   │                       send-push-notification
│   └── scripts/            One-off operational scripts (e.g. admin provisioning)
└── README.md
```

### Folder ownership

Each folder has a single owner during development, to keep concurrent work conflict-free. Cross-folder changes happen only as explicit, reviewed, one-time exceptions — never assumed.

| Folder | Owner | Focus |
|---|---|---|
| `/supabase/migrations/` | Reilyn (Tech Lead) | Database schema, Row-Level Security, security hardening |
| `/supabase/functions/` | Reilyn (Tech Lead) | Edge Functions, Firebase Cloud Messaging delivery |
| `/ai/` | Reilyn (Tech Lead) | AI microservice |
| `/mobile/` | Keshav | Flutter app, realtime & push notifications |
| `/web/` | Saiyusha | React admin dashboard, Vercel deployment, technical documentation |

All work happens on a branch and merges into `main` via pull request — nobody pushes to `main` directly.

## Getting Started

### Prerequisites

- A Supabase project (Postgres + Auth + Storage + Edge Functions + Realtime enabled)
- [Node.js](https://nodejs.org) 18+ (web admin panel and Supabase scripts)
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) for the mobile app
- Python 3.11+ for the AI microservice

### 1. Database

Apply the migrations in `supabase/migrations/` **in numeric order** — they are additive and sequential, never skip or reorder them:

```bash
supabase db push
```

or via the Supabase SQL editor / MCP tools, one file at a time.

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

Set your Supabase project URL and anon key in `mobile/lib/config/supabase_config.dart` (the anon key is safe to commit — it is rate-limited and RLS-gated, not a secret). Point the app at the AI microservice by setting `app_config.ai_base_url` in Supabase (picked up automatically by every signed-in client within a minute, no rebuild needed), or override per-device via the in-app "AI server address" dialog.

```bash
flutter analyze   # run before flutter run — catches issues early
flutter run
```

### 4. Admin provisioning

There is no self-registration path for administrators, by design. To create the first admin account:

```bash
cd supabase/scripts
npm install
cp .env.example .env   # fill in SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ADMIN_EMAIL, ADMIN_PASSWORD, ...
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

Set the following as environment variables (or in a `.env` file, never committed):

```
GEMINI_API_KEY=...
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
```

```bash
flask run
```

The service is typically exposed behind an ngrok tunnel during development; `curl <url>/health` to confirm liveness before publishing a new URL to `app_config.ai_base_url`.

## Security Model

- **Row-Level Security is the real authorization boundary.** Every table with sensitive data has RLS policies enforced at the database level — not just conditional rendering in the UI. A raw REST call from a suspended, unauthenticated, or wrong-role client is rejected by Postgres itself.
- **Column-level privacy.** `profiles.email` and `profiles.fcm_token` are not readable by ordinary members; `select *` on `profiles` is refused outright. Every client read lists its columns explicitly. An admin-only Postgres view (`admin_profiles`) is the one read path that includes email.
- **Secrets live in Supabase Vault, not in the database in plain sight.** Dashboard webhooks read their signing secret and gateway key from Vault (`admin_upsert_vault_secret`) rather than carrying them as literal trigger arguments.
- **Suspended accounts can read and delete their own content, but not create or edit it.** Enforced via `WITH CHECK` clauses tied to `profiles.account_status = 'active'` on every relevant INSERT/UPDATE policy.
- **No self-registering administrators**, ever — see [Admin provisioning](#4-admin-provisioning).
- **Domain-restricted student signup**, enforced by a database trigger, not client-side validation.
- **POPIA compliance** — `export_my_data()` and `delete_my_account()` give every member a genuine self-service path for their own data, backed by real database functions.
- **Verified onboarding** — alumni go through a claim-and-review flow, and business accounts go through manual admin approval before they can post anything, both logged to an audit trail and triggering a real notification email.

## AI Microservice

The Flask service (`ai/app.py`) uses Google's `google-genai` SDK against `gemini-2.5-flash` and exposes:

| Endpoint | Method | Purpose |
|---|---|---|
| `/health` | GET | Liveness check |
| `/api/parse-cv` | POST | Accepts a PDF upload or raw text; Gemini reads the PDF directly (so scanned CVs still work) and returns strict, schema-validated JSON. 5 MB cap, magic-byte validated. |
| `/api/chat` | POST | Context-aware onboarding/career assistant — injected with the caller's real profile data. |
| `/api/suggest-skills` | POST | Skill and opportunity-matching suggestions based on profile content. |

The service holds its own `SUPABASE_SERVICE_ROLE_KEY` to read profile context, but never writes to the database directly or bypasses RLS on behalf of a client — every mutation still goes back through the normal authenticated Supabase path.

## Testing & Quality

- **Mobile**: `flutter analyze` (zero errors/warnings) and a growing suite of unit/widget tests, including tests that drive real UI (e.g. the portfolio entry sheet) rather than mocking it away.
- **Database**: every non-trivial RLS policy and RPC is verified with a rolled-back SQL transaction against the live schema before being trusted — not just read from the migration file.
- **Web**: `npm run lint` and `npm run build` as a baseline gate before merge.
- **Manual QA**: signed-in flows are tested on a real Android device wherever possible (physical-device testing has, in practice, caught more real bugs on this project than the emulator).

## Engineering Process

- **Branch → PR → merge**, always. Every change lands via a pull request; nobody pushes to `main` directly.
- **Folder ownership** keeps concurrent work on `/mobile/`, `/web/`, `/supabase/migrations/`, and `/supabase/functions/` conflict-free — cross-folder touches are explicit, flagged exceptions, never silent.
- **Numbered, sequential database migrations** are the schema's single source of truth — 40 and counting, all verified live before merge.
- **Security-first defaults**: every new table ships with RLS from day one; every write path that matters is checked in the database, not just the client.

## Team

| Member | Role |
|---|---|
| **Reilyn** | Tech Lead — database & security architecture, AI microservice, Firebase Cloud Messaging |
| **Keshav** | Mobile — Flutter application, realtime & push notifications |
| **Saiyusha** | Web — React admin dashboard, Vercel deployment, technical documentation |

---

*Built for the Richfield / AAA Hackathon 2026.*
