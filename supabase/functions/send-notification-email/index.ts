// supabase/functions/send-notification-email/index.ts
//
// Triggered by Supabase Database Webhooks (Dashboard > Database > Webhooks),
// NOT called directly by any client. Two webhooks feed this one function:
//
//   1. INSERT on public.profiles          -> welcome email
//   2. INSERT on public.verification_audit -> alumni approved/rejected
//      (has the admin's `reason` text, which profiles alone doesn't)
//
// Business approval doesn't have an audit table yet (no
// approve_business_account function exists in the migrations as of this
// write-up) — the UPDATE-on-profiles fallback below covers it once that
// lands, but confirm the exact shape with Reil before relying on it.
//
// SECURITY: this function must not be publicly guessable-and-callable.
// When you create the Database Webhook, add a custom HTTP header
// (e.g. "x-webhook-secret: <random value>") and set the same value as the
// WEBHOOK_SECRET env var below via `supabase secrets set`. Every request is
// checked against it before touching Resend.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  welcomeEmail,
  alumniApprovedEmail,
  alumniRejectedEmail,
  businessApprovedEmail,
  businessRejectedEmail,
} from "./templates.ts";

// Throws at module load (visible in deploy/cold-start logs) instead of
// silently becoming `undefined` and getting swallowed by the catch-all
// 200 response below.
function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const RESEND_API_KEY = requireEnv("RESEND_API_KEY");
const WEBHOOK_SECRET = requireEnv("WEBHOOK_SECRET");
const FROM_ADDRESS = Deno.env.get("NOTIFICATIONS_FROM_ADDRESS") ?? "Richfield Connect <notifications@yourverifieddomain.org>";

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"), // service_role: this function needs to read across profiles/claims regardless of RLS
);

async function sendViaResend(to: string, subject: string, html: string) {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: FROM_ADDRESS, to, subject, html }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Resend API error (${res.status}): ${body}`);
  }
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  const payload = await req.json();
  const { type, table, record, old_record } = payload;

  try {
    // --- Welcome email: fires when handle_new_user() inserts the row ----
    if (table === "profiles" && type === "INSERT") {
      const { email, first_name } = record;
      if (!email) return new Response("no email on record", { status: 200 });
      const { subject, html } = welcomeEmail({ firstName: first_name ?? "there" });
      await sendViaResend(email, subject, html);
      return new Response("welcome email sent", { status: 200 });
    }

    // --- Alumni decision: fires when an admin calls approve/reject_alumni_verification ---
    if (table === "verification_audit" && type === "INSERT") {
      const { claim_id, decision, reason } = record;

      const { data: claim, error: claimError } = await supabase
        .from("verification_claims")
        .select("user_id")
        .eq("id", claim_id)
        .single();
      if (claimError || !claim) throw new Error(`could not resolve claim ${claim_id}: ${claimError?.message}`);

      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .select("email, first_name")
        .eq("id", claim.user_id)
        .single();
      if (profileError || !profile?.email) throw new Error(`could not resolve profile for claim ${claim_id}`);

      const { subject, html } = decision === "approved"
        ? alumniApprovedEmail({ firstName: profile.first_name ?? "there" })
        : alumniRejectedEmail({ firstName: profile.first_name ?? "there", reason });

      await sendViaResend(profile.email, subject, html);
      return new Response("alumni decision email sent", { status: 200 });
    }

    // --- Business decision: provisional, pending Reil's approval function ---
    // Fires on any profiles UPDATE where account_status flips away from
    // 'pending' for a business-role row. Replace with an audit-table-backed
    // trigger (like the alumni one above) once that function exists, so you
    // get a real `reason` instead of none.
    if (table === "profiles" && type === "UPDATE") {
      const roleIsBusiness = record.role === "business";
      const statusChanged = old_record?.account_status === "pending" && record.account_status !== "pending";
      if (roleIsBusiness && statusChanged && record.email) {
        const { subject, html } = record.account_status === "active"
          ? businessApprovedEmail({ firstName: record.first_name ?? "there" })
          : businessRejectedEmail({ firstName: record.first_name ?? "there", reason: null });
        await sendViaResend(record.email, subject, html);
        return new Response("business decision email sent", { status: 200 });
      }
    }

    return new Response("no matching handler for this event", { status: 200 });
  } catch (err) {
    console.error("send-notification-email failed:", err);
    // Return 200 so Supabase doesn't endlessly retry a permanently-failing
    // payload; the error is in the function logs for you to catch.
    return new Response(`handled with error: ${err}`, { status: 200 });
  }
});
