# Richfield Connect - Mobile App

Flutter app, the primary product surface for students, alumni, and business users.
See the [root README](../README.md) for the full project overview and tech stack
rationale; this file covers the mobile app specifically.

## Getting started

```bash
cd mobile
flutter pub get
```

Set your Supabase project URL and anon key in `mobile/lib/config/supabase_config.dart`
(the anon key is safe to commit - it's rate-limited and RLS-gated, not a secret).

```bash
flutter analyze   # run before flutter run - catches issues early
flutter run
```

## Structure

lib/
|-- main.dart App entry point
|-- config/ Supabase config, environment values
|-- router/ go_router setup - routes react to live Supabase auth state
| (role- and account-status-aware redirects)
|-- screens/ One file per screen (see below)
|-- services/ One service per domain area, wrapping Supabase calls
`-- widgets/ Shared, reusable widgets


### Screens

| Screen | Purpose |
|---|---|
| `career_pathways_screen.dart` | Career pathway explorer: where alumni from your programme ended up (jobs are browsed/applied for on the Jobs tab in `main.dart`) |
| `network_screen.dart` / `member_profile_screen.dart` | Connections and viewing another user's profile |
| `messages_screen.dart` / `chat_screen.dart` | Direct messaging |
| `events_screen.dart` | Institutional events feed |
| `edit_profile_screen.dart` / `portfolio_entry_sheet.dart` | Building the verified digital portfolio |
| `cv_import_screen.dart` | CV parsing hand-off to the AI microservice |
| `ai_assistant_screen.dart` | AI-assisted onboarding / profile / post-writing help |
| `notifications_screen.dart` | In-app notifications |
| `privacy_settings_screen.dart` | Per-section portfolio visibility controls |
| `forgot_password_screen.dart` | Password reset flow |

### Services

Each file in `lib/services/` wraps a single domain's Supabase (or AI microservice)
calls, so screens don't talk to Supabase directly: e.g. `auth_service.dart` (sign-up/
sign-in and role-aware error mapping via `auth_error_mapper.dart`), `feed_service.dart`,
`jobs_service.dart`, `portfolio_service.dart`, `career_pathway_service.dart`,
`connections_service.dart`, `messaging_service.dart` + `realtime_hub.dart` (live
updates), `notifications_service.dart` + `push_notification_service.dart`,
`privacy_service.dart`, and the three `*_analytics_service.dart` files (student,
business, admin dashboards).

## Testing

```bash
flutter test
```

`test/widget_test.dart` is the starting point for widget tests - extend it as new
screens are added rather than leaving coverage at the default template test.
