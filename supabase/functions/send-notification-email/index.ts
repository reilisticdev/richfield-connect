// supabase/functions/send-notification-email/index.ts
//
// Triggered by Supabase Database Webhooks (Dashboard > Database > Webhooks),
// NOT called directly by any client. Two webhooks feed this one function:
//
//   1. INSERT on public.profiles          -> welcome email
//   2. INSERT on public.verification_audit -> alumni OR business decision
//      (has the admin's `reason` text, which profiles alone doesn't)
//
// verification_audit rows carry exactly one of claim_id (alumni, via
// approve/reject_alumni_verification) or business_id (business, via
// approve_business_account - see supabase/migrations/021_business_approval.sql)
// - branch on whichever is set. The old provisional profiles-UPDATE path
// for business decisions is gone now that this table handles it for real.
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
  const { type, table, record } = payload;

  try {
    // --- Welcome email: fires when handle_new_user() inserts the row ----
    if (table === "profiles" && type === "INSERT") {
      const { email, first_name } = record;
      if (!email) return new Response("no email on record", { status: 200 });
      const { subject, html } = welcomeEmail({ firstName: first_name ?? "there" });
      await sendViaResend(email, subject, html);
      return new Response("welcome email sent", { status: 200 });
    }

    // --- Alumni/business decision: fires when an admin calls
    // approve/reject_alumni_verification or approve_business_account.
    // Exactly one of claim_id/business_id is set per row (enforced by
    // verification_audit_exactly_one_target in 021_business_approval.sql).
    if (table === "verification_audit" && type === "INSERT") {
      const { claim_id, business_id, decision, reason } = record;

      // Observed in production logs (2026-09-08): a real webhook delivery
      // came through with claim_id as the literal 3-char string "null"
      // rather than JSON/SQL null, which is truthy in JS and blew up
      // Postgres with "invalid input syntax for type uuid: null" instead
      // of falling through to the business_id branch. Root cause looks
      // like it's upstream of this function (how the trigger/pg_net
      // payload gets built) - flagged to Reilyn to dig into separately -
      // but guarding here means a payload shaped like that degrades to a
      // clear "neither target present" error instead of a stack trace.
      const hasClaimId = claim_id != null && claim_id !== "null" && claim_id !== "";
      const hasBusinessId = business_id != null && business_id !== "null" && business_id !== "";

      if (hasClaimId) {
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

      if (hasBusinessId) {
        const { data: profile, error: profileError } = await supabase
          .from("profiles")
          .select("email, first_name")
          .eq("id", business_id)
          .single();
        if (profileError || !profile?.email) throw new Error(`could not resolve profile for business ${business_id}`);

        const { subject, html } = decision === "approved"
          ? businessApprovedEmail({ firstName: profile.first_name ?? "there" })
          : businessRejectedEmail({ firstName: profile.first_name ?? "there", reason });

        await sendViaResend(profile.email, subject, html);
        return new Response("business decision email sent", { status: 200 });
      }

      throw new Error("verification_audit row has neither claim_id nor business_id");
    }

    return new Response("no matching handler for this event", { status: 200 });
  } catch (err) {
    console.error("send-notification-email failed:", err);
    // Return 200 so Supabase doesn't endlessly retry a permanently-failing
    // payload; the error is in the function logs for you to catch.
    return new Response(`handled with error: ${err}`, { status: 200 });
  }
});
