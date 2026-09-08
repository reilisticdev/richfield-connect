/**
 * supabase/scripts/provision-admin.ts
 *
 * One-time bootstrap script to create the first administrator account.
 *
 * WHY THIS EXISTS (see supabase/migrations/005_signup_role_restriction.sql):
 *   handle_new_user() raises an exception and rolls back the auth.users
 *   insert if raw_user_meta_data->>'role' = 'administrator'. That trigger
 *   fires for EVERY insert into auth.users, including ones made through
 *   supabase.auth.admin.createUser() with the service role key. So you
 *   CANNOT create an administrator in one call — it will always fail.
 *
 * THE ACTUAL PATH (see migration 004_role_change_lockdown.sql):
 *   prevent_unauthorised_role_change() allows a role change through when
 *   auth.role() = 'service_role'. Requests made with the service role key
 *   are evaluated as that role by PostgREST, so a two-step flow works:
 *     1. Create the user with no role in metadata (defaults to 'student',
 *        insert succeeds).
 *     2. UPDATE profiles.role = 'administrator' using the service-role
 *        client. This passes the trigger check and bypasses RLS.
 *
 * USAGE
 *   Run locally only, never in a client or CI runner that isn't fully
 *   trusted. Copy .env.example to .env in this folder and fill in:
 *     SUPABASE_URL                 (bare project URL, e.g. https://<ref>.supabase.co
 *                                    — do NOT include /rest/v1 or any path suffix,
 *                                    supabase-js appends that itself)
 *     SUPABASE_SERVICE_ROLE_KEY    (service_role secret — never ship this)
 *     ADMIN_EMAIL
 *     ADMIN_PASSWORD               (temporary — force a reset on first login)
 *     ADMIN_FIRST_NAME (optional)
 *     ADMIN_LAST_NAME  (optional)
 *
 *   npx tsx supabase/scripts/provision-admin.ts
 *
 * SAFETY
 *   - Refuses to run if an administrator profile already exists, unless
 *     --force is passed. This script is meant to run exactly once.
 *   - Does NOT print the password back out. Rotate it after first login.
 *   - Sets app_metadata.requires_mfa_setup = true so the app can force an
 *     MFA enrollment screen before granting access to any admin route.
 *     There is no Admin API to enroll a TOTP factor without the user's own
 *     session, so this flag is how you enforce it at the app layer.
 */

import "dotenv/config";
import { createClient } from "@supabase/supabase-js";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing required environment variable: ${name}`);
    process.exit(1);
  }
  return value;
}

async function main() {
  const SUPABASE_URL = requireEnv("SUPABASE_URL");
  const SERVICE_ROLE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const ADMIN_EMAIL = requireEnv("ADMIN_EMAIL");
  const ADMIN_PASSWORD = requireEnv("ADMIN_PASSWORD");
  const ADMIN_FIRST_NAME = process.env.ADMIN_FIRST_NAME ?? null;
  const ADMIN_LAST_NAME = process.env.ADMIN_LAST_NAME ?? null;
  const force = process.argv.includes("--force");

  if (ADMIN_PASSWORD.length < 12) {
    console.error("ADMIN_PASSWORD must be at least 12 characters. Use a generated passphrase, not something memorable.");
    process.exit(1);
  }

  // Service-role client: bypasses RLS, and is evaluated as auth.role() =
  // 'service_role' inside triggers/policies that check for it.
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // --- Guard: refuse to run twice -----------------------------------------
  const { count, error: countError } = await supabase
    .from("profiles")
    .select("id", { count: "exact", head: true })
    .eq("role", "administrator");

  if (countError) {
    console.error("Failed to check for existing administrators:", countError.message);
    process.exit(1);
  }

  if (count && count > 0 && !force) {
    console.error(
      `${count} administrator account(s) already exist. This script is meant to run once. ` +
      `Pass --force if you deliberately need to create another.`
    );
    process.exit(1);
  }

  // --- Step 1: create the auth user with NO role in metadata -------------
  // Leaving role unset lets handle_new_user() default it to 'student' and
  // insert successfully. Setting 'administrator' here will throw.
  const { data: created, error: createError } = await supabase.auth.admin.createUser({
    email: ADMIN_EMAIL,
    password: ADMIN_PASSWORD,
    email_confirm: true, // skip the confirmation email loop for a bootstrap account
    user_metadata: {
      first_name: ADMIN_FIRST_NAME,
      last_name: ADMIN_LAST_NAME,
      // role intentionally omitted
    },
    app_metadata: {
      requires_mfa_setup: true,
    },
  });

  if (createError || !created?.user) {
    console.error("Failed to create auth user:", createError?.message);
    process.exit(1);
  }

  const user = created.user;
  if (!user) {
    console.error("Unexpected: user creation reported success but returned no user.");
    process.exit(1);
  }
  const userId = user.id;
  console.log(`Created auth user ${userId} for ${ADMIN_EMAIL}`);

  // --- Step 2: promote to administrator via service-role update ----------
  const { data: updated, error: updateError } = await supabase
    .from("profiles")
    .update({ role: "administrator", account_status: "active" })
    .eq("id", userId)
    .select()
    .single();

  if (updateError) {
    console.error(
      "User was created but promotion to administrator failed:",
      updateError.message,
      "\nYou now have an orphaned student-role auth user. Delete it via " +
      "supabase.auth.admin.deleteUser() before retrying, or fix and rerun with --force."
    );
    process.exit(1);
  }

  console.log("Promoted to administrator:", {
    id: updated.id,
    email: updated.email,
    role: updated.role,
    account_status: updated.account_status,
  });

  console.log(
    "\nDone. Next steps:\n" +
    "  1. Have this person log in with the temporary password and change it immediately.\n" +
    "  2. Your app must check app_metadata.requires_mfa_setup on login and force an\n" +
    "     MFA enrollment screen (supabase.auth.mfa.enroll) before allowing access to any\n" +
    "     admin route. Clear the flag only after a factor is verified.\n" +
    "  3. Delete or rotate SUPABASE_SERVICE_ROLE_KEY from your local shell history/.env\n" +
    "     once this is done — it should not sit around after bootstrap.\n"
  );
}

main().catch((err) => {
  console.error("Unexpected error:", err);
  process.exit(1);
});
