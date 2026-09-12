import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

// Reports store only an id, so the queue loads the reported post or comment
// itself; the decision should be made on the content, not on "post #1a2b3c4d".
const preview = (text) => {
  const trimmed = (text ?? "").trim();
  if (!trimmed) return "(no text: image or video only)";
  return trimmed.length > 160 ? `${trimmed.slice(0, 160)}…` : trimmed;
};

const contentLabel = (type) =>
  type === "comment" ? "Comment" : type === "video" ? "Video post" : "Post";

function Moderation() {
  const [businesses, setBusinesses] = useState([]);
  const [loadingBusinesses, setLoadingBusinesses] = useState(true);

  const [alumni, setAlumni] = useState([]);
  const [loadingAlumni, setLoadingAlumni] = useState(true);

  const [flaggedContent, setFlaggedContent] = useState([]);
  const [loadingFlagged, setLoadingFlagged] = useState(true);

  const [error, setError] = useState(null);

  const fetchPendingBusinesses = async () => {
    setLoadingBusinesses(true);

    // admin_profiles (migration 037): the only API path that still returns
    // email, and only to administrators.
    const { data, error } = await supabase
      .from("admin_profiles")
      .select(
        "id, first_name, last_name, email, account_status, business_profiles(company_name)"
      )
      .eq("role", "business")
      .eq("account_status", "pending");

    if (error) {
      console.error("Error fetching pending businesses:", error);
      setBusinesses([]);
    } else {
      setBusinesses(data || []);
    }

    setLoadingBusinesses(false);
  };

  const fetchPendingAlumni = async () => {
    setLoadingAlumni(true);

    const { data, error } = await supabase
      .from("verification_claims")
      .select(
        // `profiles:` aliases the admin_profiles embed so the JSX below keeps
        // reading claim.profiles.* unchanged.
        "id, student_number, programme, campus, graduation_year, status, profiles:admin_profiles(first_name, last_name, email)"
      )
      .eq("status", "pending");

    if (error) {
      console.error("Error fetching pending alumni claims:", error);
      setAlumni([]);
    } else {
      setAlumni(data || []);
    }

    setLoadingAlumni(false);
  };

  const fetchFlaggedContent = async () => {
    setLoadingFlagged(true);

    const { data, error } = await supabase
      .from("content_reports")
      .select(
        "id, content_id, content_type, reason, status, created_at, profiles(first_name, last_name)"
      )
      .eq("status", "pending")
      .order("created_at", { ascending: true });

    if (error) {
      console.error("Error fetching flagged content:", error);
      setFlaggedContent([]);
      setLoadingFlagged(false);
      return;
    }

    const reports = data || [];
    const postIds = reports
      .filter((report) => report.content_type !== "comment")
      .map((report) => report.content_id);
    const commentIds = reports
      .filter((report) => report.content_type === "comment")
      .map((report) => report.content_id);

    const [posts, comments] = await Promise.all([
      postIds.length
        ? supabase
            .from("posts")
            .select("id, body, profiles(first_name, last_name)")
            .in("id", postIds)
        : Promise.resolve({ data: [] }),
      commentIds.length
        ? supabase
            .from("comments")
            .select("id, body, profiles(first_name, last_name)")
            .in("id", commentIds)
        : Promise.resolve({ data: [] }),
    ]);

    if (posts.error || comments.error) {
      console.error("Error loading reported content:", posts.error || comments.error);
    }

    const targets = new Map();
    [...(posts.data || []), ...(comments.data || [])].forEach((item) =>
      targets.set(item.id, item)
    );

    setFlaggedContent(
      reports.map((report) => ({
        ...report,
        target: targets.get(report.content_id) ?? null,
      }))
    );
    setLoadingFlagged(false);
  };

  useEffect(() => {
    fetchPendingBusinesses();
    fetchPendingAlumni();
    fetchFlaggedContent();
  }, []);

  const updateBusinessStatus = async (id, status) => {
    const { error } =
      status === "Approved"
        ? await supabase.rpc("approve_business_account", {
            target_business_id: id,
          })
        : await supabase.rpc("reject_business_account", {
            target_business_id: id,
            reason: null,
          });

    if (error) {
      console.error("Error updating business status:", error);
      setError("Could not update business account.");
      return;
    }

    setBusinesses((current) =>
      current.filter((business) => business.id !== id)
    );
  };

  const updateAlumniStatus = async (id, status) => {
    if (status === "Approved") {
      const { error } = await supabase.rpc("approve_alumni_verification", {
        claim_id: id,
      });

      if (error) {
        console.error("Error approving alumni verification:", error);
        setError("Could not approve alumni verification.");
        return;
      }
    } else {
      const reason =
        window.prompt(
          "Reason for rejection:",
          "Documentation did not match student record"
        ) ?? "Not specified";

      const { error } = await supabase.rpc("reject_alumni_verification", {
        claim_id: id,
        reason,
      });

      if (error) {
        console.error("Error rejecting alumni verification:", error);
        setError("Could not reject alumni verification.");
        return;
      }
    }

    setAlumni((current) => current.filter((person) => person.id !== id));
  };

  // Closes every pending report about the same item, not just the row clicked.
  const closeReports = async (report, status) => {
    const { error } = await supabase
      .from("content_reports")
      .update({ status })
      .eq("content_id", report.content_id)
      .eq("status", "pending");

    if (error) {
      console.error("Error updating reports:", error);
      return false;
    }

    setFlaggedContent((current) =>
      current.filter((item) => item.content_id !== report.content_id)
    );
    return true;
  };

  const keepContent = async (report) => {
    if (!(await closeReports(report, "dismissed"))) {
      setError("Could not update flagged content.");
    }
  };

  const removeContent = async (report) => {
    const noun = contentLabel(report.content_type).toLowerCase();

    if (report.target) {
      if (!window.confirm(`Remove this ${noun} for everyone? This can't be undone.`)) {
        return;
      }

      const table = report.content_type === "comment" ? "comments" : "posts";
      const { data: removed, error: deleteError } = await supabase
        .from(table)
        .delete()
        .eq("id", report.content_id)
        .select("id");

      if (deleteError || !removed?.length) {
        console.error("Error removing content:", deleteError);
        setError(`Could not remove the ${noun}.`);
        return;
      }
    }

    if (!(await closeReports(report, "actioned"))) {
      setError(`The ${noun} was removed, but its reports could not be closed.`);
    }
  };

  return (
    <div className="admin-page">
      <div className="page-header">
        <div>
          <h1>Moderation</h1>
          <p>
            Review and manage pending accounts, alumni verification, and
            flagged content.
          </p>
        </div>
      </div>

      {error && <p className="form-error">{error}</p>}

      {/* Business Accounts */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Pending Business Accounts</h2>
            <p>Review businesses requesting access to Richfield Connect.</p>
          </div>

          <span className="count-badge">
            {businesses.length} Pending
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Business</span>
            <span>Contact</span>
            <span>Status</span>
            <span>Actions</span>
          </div>

          {loadingBusinesses ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : businesses.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No pending business accounts</strong>
                <small>
                  There are currently no business registrations waiting for
                  approval.
                </small>
              </div>
            </div>
          ) : (
            businesses.map((business) => (
              <div className="table-row" key={business.id}>
                <div>
                  <strong>
                    {business.business_profiles?.company_name ??
                      `${business.first_name} ${business.last_name}`}
                  </strong>
                  <small>
                    {business.first_name} {business.last_name}
                  </small>
                </div>

                <div>{business.email}</div>

                <div>
                  <span className="status-badge pending">
                    Pending
                  </span>
                </div>

                <div className="action-buttons">
                  <button
                    className="approve-button"
                    onClick={() =>
                      updateBusinessStatus(business.id, "Approved")
                    }
                  >
                    Approve
                  </button>

                  <button
                    className="reject-button"
                    onClick={() =>
                      updateBusinessStatus(business.id, "Rejected")
                    }
                  >
                    Reject
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </section>

      {/* Alumni Verification */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Alumni Verification</h2>
            <p>Review alumni claims and verify their identity.</p>
          </div>

          <span className="count-badge">
            {alumni.length} Pending
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Alumni</span>
            <span>Verification</span>
            <span>Status</span>
            <span>Actions</span>
          </div>

          {loadingAlumni ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : alumni.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No alumni verification requests</strong>
                <small>
                  There are currently no alumni claims waiting for review.
                </small>
              </div>
            </div>
          ) : (
            alumni.map((claim) => (
              <div className="table-row" key={claim.id}>
                <div>
                  <strong>
                    {claim.profiles?.first_name} {claim.profiles?.last_name}
                  </strong>
                  <small>Student no. {claim.student_number}</small>
                </div>

                <div>
                  {claim.programme} — {claim.campus} ({claim.graduation_year})
                </div>

                <div>
                  <span className="status-badge pending">
                    Pending
                  </span>
                </div>

                <div className="action-buttons">
                  <button
                    className="approve-button"
                    onClick={() => updateAlumniStatus(claim.id, "Approved")}
                  >
                    Approve
                  </button>

                  <button
                    className="reject-button"
                    onClick={() => updateAlumniStatus(claim.id, "Rejected")}
                  >
                    Reject
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </section>

      {/* Flagged Content */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Flagged Content</h2>
            <p>
              Posts and comments members reported from the app. Remove deletes
              the content for everyone; Keep closes the report.
            </p>
          </div>

          <span className="count-badge">
            {flaggedContent.length} Review
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Content</span>
            <span>Reported By</span>
            <span>Reason</span>
            <span>Actions</span>
          </div>

          {loadingFlagged ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : flaggedContent.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No flagged content</strong>
                <small>There is currently nothing waiting for review.</small>
              </div>
            </div>
          ) : (
            flaggedContent.map((content) => (
              <div className="table-row" key={content.id}>
                <div>
                  <strong>
                    {content.target
                      ? preview(content.target.body)
                      : "Already deleted"}
                  </strong>
                  <small>
                    {contentLabel(content.content_type)}
                    {content.target?.profiles
                      ? ` by ${content.target.profiles.first_name} ${content.target.profiles.last_name}`
                      : ""}
                  </small>
                </div>

                <div>
                  {content.profiles
                    ? `${content.profiles.first_name} ${content.profiles.last_name}`
                    : "Unknown user"}
                </div>

                <div>{content.reason}</div>

                <div className="action-buttons">
                  <button
                    className="approve-button"
                    onClick={() => keepContent(content)}
                  >
                    Keep
                  </button>

                  <button
                    className="reject-button"
                    onClick={() => removeContent(content)}
                  >
                    Remove
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </section>
    </div>
  );
}

export default Moderation;
