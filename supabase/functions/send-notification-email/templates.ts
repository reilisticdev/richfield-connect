// supabase/functions/send-notification-email/templates.ts
//
// Plain TS template literals rather than separate .html files — Edge
// Functions bundle as a single deployable unit, and reading loose files at
// runtime is fragile across Deno Deploy environments. Keeping templates as
// exported functions keeps everything in one deploy with no path issues.
//
// Every template takes the recipient's real data — no lorem ipsum, no
// placeholder brand assets left in.

interface BaseData {
  firstName: string;
}

interface RejectionData extends BaseData {
  reason?: string | null;
}

// firstName/reason originate from user-controlled signup metadata and admin
// free-text respectively — escape before interpolating into outbound HTML.
function escapeHtml(input: string): string {
  return input
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

const shell = (bodyHtml: string) => `
<!DOCTYPE html>
<html>
  <body style="margin:0;padding:0;background:#f4f5f7;font-family:Arial,Helvetica,sans-serif;">
    <table role="presentation" width="100%" style="background:#f4f5f7;padding:32px 0;">
      <tr>
        <td align="center">
          <table role="presentation" width="480" style="background:#ffffff;border-radius:8px;overflow:hidden;">
            <tr>
              <td style="background:#0f2942;padding:24px 32px;">
                <span style="color:#ffffff;font-size:20px;font-weight:bold;">Richfield Connect</span>
              </td>
            </tr>
            <tr>
              <td style="padding:32px;color:#1a1a1a;font-size:15px;line-height:1.5;">
                ${bodyHtml}
              </td>
            </tr>
            <tr>
              <td style="padding:16px 32px;background:#f4f5f7;color:#7a7a7a;font-size:12px;">
                Richfield Connect &middot; This is an automated message, please do not reply.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;

export function welcomeEmail(data: BaseData) {
  const safeFirstName = escapeHtml(data.firstName);
  return {
    subject: "Welcome to Richfield Connect",
    html: shell(`
      <h2 style="margin-top:0;">Hi ${safeFirstName},</h2>
      <p>Your Richfield Connect account has been created. You can now sign in and start exploring the platform.</p>
      <p>If you didn't create this account, you can safely ignore this email.</p>
    `),
  };
}

export function alumniApprovedEmail(data: BaseData) {
  const safeFirstName = escapeHtml(data.firstName);
  return {
    subject: "Your alumni status has been verified",
    html: shell(`
      <h2 style="margin-top:0;">Hi ${safeFirstName},</h2>
      <p>Good news — an administrator has reviewed and approved your alumni verification claim. Your account now has full alumni access.</p>
    `),
  };
}

export function alumniRejectedEmail(data: RejectionData) {
  const safeFirstName = escapeHtml(data.firstName);
  const safeReason = data.reason ? escapeHtml(data.reason) : null;
  return {
    subject: "Update on your alumni verification",
    html: shell(`
      <h2 style="margin-top:0;">Hi ${safeFirstName},</h2>
      <p>An administrator reviewed your alumni verification claim and was unable to approve it${safeReason ? `:</p><p style="padding:12px;background:#f4f5f7;border-radius:4px;">${safeReason}</p><p>` : "."}
      You're welcome to submit a new claim with corrected details.</p>
    `),
  };
}

export function businessApprovedEmail(data: BaseData) {
  const safeFirstName = escapeHtml(data.firstName);
  return {
    subject: "Your business account has been approved",
    html: shell(`
      <h2 style="margin-top:0;">Hi ${safeFirstName},</h2>
      <p>Your business account has been approved. You now have full access to the platform.</p>
    `),
  };
}

export function businessRejectedEmail(data: RejectionData) {
  const safeFirstName = escapeHtml(data.firstName);
  const safeReason = data.reason ? escapeHtml(data.reason) : null;
  return {
    subject: "Update on your business account application",
    html: shell(`
      <h2 style="margin-top:0;">Hi ${safeFirstName},</h2>
      <p>An administrator reviewed your business account application and was unable to approve it${safeReason ? `:</p><p style="padding:12px;background:#f4f5f7;border-radius:4px;">${safeReason}</p><p>` : "."}
      Reach out to support if you'd like to reapply.</p>
    `),
  };
}
