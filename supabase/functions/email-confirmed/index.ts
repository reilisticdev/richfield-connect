// supabase/functions/email-confirmed/index.ts
//
// Where the "confirm your email" link lands after GoTrue has verified it.
//
// Until 2026-09-12 that was the project's default Site URL,
// http://localhost:3000 — a dead end in the browser (Keshav's QA). This is
// the destination now, set both as the Site URL and as the app's
// emailRedirectTo:
//   https://omyagiwmdabalxifyoth.supabase.co/functions/v1/email-confirmed
//
// What it does, per device:
//   * phone  -> 302 to richfield://auth/confirmed?<query>. The app opens,
//               supabase_flutter exchanges the PKCE `code` for a session
//               (the code verifier lives only on the phone that registered)
//               and the app shows "Your email is confirmed".
//   * laptop -> a plain-text confirmation. Plain on purpose: the shared
//               *.supabase.co functions domain rewrites HTML responses to
//               text/plain with a sandbox CSP (verified 2026-09-12), so a
//               styled page is not possible here without a custom domain.
//   * expired / used link (GoTrue appends error_code=otp_expired) -> a
//               plain-text explanation pointing at "Resend confirmation
//               email" in the app.
//
// Reads no data, holds no secrets, so verify_jwt is off — a browser
// following an email link has no JWT.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const APP_LINK = "richfield://auth/confirmed";

const CONFIRMED = `Richfield Connect

Your email is confirmed. Your account is good to go.

Open the Richfield Connect app on your phone and sign in with your email and password.
(Alumni and business accounts are then reviewed by a Richfield administrator before you can use the app.)
`;

const EXPIRED = `Richfield Connect

This confirmation link has expired or was already used.

Open the Richfield Connect app, tap Sign in, then "Resend confirmation email" to get a fresh code and link.
`;

function isPhone(userAgent: string): boolean {
  return /android|iphone|ipad|ipod|mobile/i.test(userAgent);
}

function text(body: string): Response {
  return new Response(body, {
    status: 200,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    },
  });
}

Deno.serve((req: Request) => {
  const url = new URL(req.url);
  const failed = url.searchParams.has("error") ||
    url.searchParams.has("error_code") ||
    url.searchParams.has("error_description");
  if (failed) return text(EXPIRED);

  if (isPhone(req.headers.get("user-agent") ?? "")) {
    // Forward the query string (PKCE `code`) so the app can finish sign-in.
    return new Response(null, {
      status: 302,
      headers: {
        "Location": APP_LINK + url.search,
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      },
    });
  }
  return text(CONFIRMED);
});
