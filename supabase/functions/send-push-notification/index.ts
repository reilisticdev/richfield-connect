// supabase/functions/send-push-notification/index.ts
//
// Triggered by the same kind of Database Webhook as send-notification-email
// (INSERT on public.verification_audit) — a SEPARATE function rather than
// adding push to that one, so a working email path can't be broken by
// changes here, and so this can be reviewed/wired independently.
//
// Sends via FCM HTTP v1, which needs an OAuth2 access token minted from a
// Firebase service account — not a static server key. Supabase's own docs
// (supabase.com/docs/guides/functions/examples/push-notifications, FCM tab)
// show this exact approach but have you commit the service account JSON as
// a file under supabase/functions/. Deliberately NOT done that way here:
// this repo just went through a real incident (see 2026-09-10, GitHub
// flagged an exposed key in google-services.json committed straight to
// main) — a service account private key is a categorically bigger secret
// than that Android client key, so it goes in as a Supabase secret
// (FCM_SERVICE_ACCOUNT_JSON, the raw downloaded JSON as one string) and is
// read via Deno.env.get like everything else in this project, never
// written to a file in the repo.
//
// SETUP (Javel — this is the FCM half of what you already handed over):
//   1. Firebase Console > Project Settings > Service Accounts >
//      Generate new private key. Downloads a .json file.
//   2. supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat path/to/that-file.json)"
//   3. Create a Database Webhook (same place as the existing one for
//      send-notification-email): table verification_audit, event Insert,
//      target this function, HTTP header x-webhook-secret set to the same
//      WEBHOOK_SECRET value already in use.
//
// SECURITY: same pattern as send-notification-email — a shared-secret
// header, checked before touching anything else.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const WEBHOOK_SECRET = requireEnv("WEBHOOK_SECRET");

// Parsed once per cold start, not per request — JSON.parse and building the
// JWT client are the same cost every time either way.
const serviceAccount = JSON.parse(requireEnv("FCM_SERVICE_ACCOUNT_JSON")) as {
  project_id: string;
  client_email: string;
  private_key: string;
};

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"), // needs to read profiles across users regardless of RLS
);

// Mirrors the official Supabase FCM example's getAccessToken() almost
// verbatim (supabase.com/docs/guides/functions/examples/push-notifications)
// — the JWT/OAuth2 exchange itself isn't project-specific, only where the
// credentials come from is.
function getAccessToken(): Promise<string> {
  return new Promise((resolve, reject) => {
    const jwtClient = new JWT({
      email: serviceAccount.client_email,
      key: serviceAccount.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    jwtClient.authorize((err, tokens) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(tokens!.access_token!);
    });
  });
}

async function sendPush(fcmToken: string, title: string, body: string) {
  const accessToken = await getAccessToken();

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
        },
      }),
    },
  );

  if (!res.ok) {
    const responseBody = await res.text();
    throw new Error(`FCM send failed (${res.status}): ${responseBody}`);
  }
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  const payload = await req.json();
  const { type, table, record } = payload;

  try {
    if (table !== "verification_audit" || type !== "INSERT") {
      return new Response("no matching handler for this event", { status: 200 });
    }

    const { claim_id, business_id, decision } = record;

    // Same "null" the literal string vs SQL null guard as
    // send-notification-email — observed in production logs 2026-09-08,
    // documented there, applies to this webhook's payload shape too.
    const hasClaimId = claim_id != null && claim_id !== "null" && claim_id !== "";
    const hasBusinessId = business_id != null && business_id !== "null" && business_id !== "";

    let targetUserId: string | null = null;

    if (hasClaimId) {
      const { data: claim, error: claimError } = await supabase
        .from("verification_claims")
        .select("user_id")
        .eq("id", claim_id)
        .single();
      if (claimError || !claim) throw new Error(`could not resolve claim ${claim_id}: ${claimError?.message}`);
      targetUserId = claim.user_id;
    } else if (hasBusinessId) {
      targetUserId = business_id;
    } else {
      throw new Error("verification_audit row has neither claim_id nor business_id");
    }

    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("fcm_token, first_name")
      .eq("id", targetUserId)
      .single();
    if (profileError || !profile) throw new Error(`could not resolve profile for ${targetUserId}`);

    // No token yet (permission never granted, or app never opened since)
    // is an expected, common state — not an error. Log and return 200 so
    // Supabase doesn't retry a payload that will never succeed.
    if (!profile.fcm_token) {
      console.log(`send-push-notification: no fcm_token on file for ${targetUserId}, skipping`);
      return new Response("no fcm token on file", { status: 200 });
    }

    const title = decision === "approved" ? "You're verified! ✅" : "Update on your verification";
    const body = decision === "approved"
      ? "Your Richfield Connect verification was approved. Welcome aboard!"
      : "There's an update on your verification request — check the app for details.";

    await sendPush(profile.fcm_token, title, body);
    return new Response("push sent", { status: 200 });
  } catch (err) {
    console.error("send-push-notification failed:", err);
    // Same reasoning as send-notification-email: 200 so this doesn't retry
    // forever, error is in the function logs to catch.
    return new Response(`handled with error: ${err}`, { status: 200 });
  }
});
